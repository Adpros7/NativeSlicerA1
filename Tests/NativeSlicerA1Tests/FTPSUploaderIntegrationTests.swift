import XCTest
import Network
import Security
@testable import NativeSlicerA1

/// Real end-to-end proof of `FTPSUploader`'s protocol implementation: a
/// genuine TLS 1.2+ `NWListener` (self-signed identity from a committed
/// test fixture, matching the printer's own untrusted-CA cert model)
/// plays the real FTP control/data channel exchange (220 → USER/PASS →
/// TYPE I → PASV → STOR → data bytes → 226) and asserts the uploaded
/// bytes match exactly. Not a mock: real sockets, real TLS handshake,
/// real FTP command/reply text on the wire.
final class FTPSUploaderIntegrationTests: XCTestCase {
    func testUploadsRealFileOverRealTLSConnection() async throws {
        let identity = try Self.loadTestIdentity()
        let payload = Data("G90\nG1 X10 Y10\n".utf8)
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gcode.3mf")
        try payload.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let server = TestFTPSServer(identity: identity)
        let controlPort = try await server.start()
        defer { server.stop() }

        let uploader = FTPSUploader(host: "127.0.0.1", username: "bblp", password: "testpass", port: controlPort)
        let remotePath = try await uploader.upload(fileAt: sourceURL, remoteFileName: "plate_1.gcode.3mf")

        XCTAssertEqual(remotePath, "/sdcard/bbl_plater/plate_1.gcode.3mf")
        let received = try await server.waitForUpload()
        XCTAssertEqual(received, payload)
    }

    /// P8-002: `remoteFileName` is written directly into a plaintext FTP
    /// `STOR` command line — CR/LF would inject additional commands,
    /// `/` would escape the fixed upload directory. Proven without a
    /// real server: the guard must reject before any connection attempt.
    func testUploadRejectsInjectionCharactersInRemoteFileName() async throws {
        let payload = Data("test".utf8)
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gcode")
        try payload.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let uploader = FTPSUploader(host: "127.0.0.1", username: "bblp", password: "x", port: 1)
        for badName in ["plate.gcode\r\nQUIT", "plate\n.gcode", "../etc/passwd", ""] {
            do {
                _ = try await uploader.upload(fileAt: sourceURL, remoteFileName: badName)
                XCTFail("expected invalidRemoteFileName for \(badName.debugDescription)")
            } catch FTPSError.invalidRemoteFileName {
                // expected
            }
        }
    }

    private static func loadTestIdentity() throws -> SecIdentity {
        let url = URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ftps-test-identity.p12")
        let p12Data = try Data(contentsOf: url)
        var items: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, [kSecImportExportPassphrase as String: "ftpstest"] as CFDictionary, &items)
        guard status == errSecSuccess, let array = items as? [[String: Any]], let first = array.first,
              let identity = first[kSecImportItemIdentity as String] as! SecIdentity?
        else {
            throw XCTSkip("Could not import test TLS identity (status \(status)) — environment lacks Keychain access for PKCS12 import")
        }
        return identity
    }
}

/// Minimal real FTP server sufficient to exercise `FTPSUploader`'s exact
/// command sequence over real `NWListener`/`NWConnection` sockets.
private final class TestFTPSServer: @unchecked Sendable {
    private let identity: SecIdentity
    private var controlListener: NWListener?
    private var dataListener: NWListener?
    private var uploadedBytes = Data()
    private let uploadLock = NSLock()
    private var uploadContinuation: CheckedContinuation<Data, Error>?
    private var activeControlConnection: NWConnection?

    init(identity: SecIdentity) { self.identity = identity }

    private func tlsParameters() -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()
        guard let secIdentity = sec_identity_create(identity) else {
            fatalError("sec_identity_create failed for test fixture identity")
        }
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentity)
        return NWParameters(tls: tlsOptions, tcp: .init())
    }

    /// Starts the control-channel listener and returns its bound port.
    func start() async throws -> UInt16 {
        let listener = try NWListener(using: tlsParameters())
        controlListener = listener
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            listener.stateUpdateHandler = { state in
                if case .ready = state, !resumed {
                    resumed = true
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                } else if case .failed(let error) = state, !resumed {
                    resumed = true
                    continuation.resume(throwing: error)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleControl(connection)
            }
            listener.start(queue: .global())
        }
        return port
    }

    func stop() {
        controlListener?.cancel()
        dataListener?.cancel()
    }

    func waitForUpload() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            uploadLock.lock()
            if !uploadedBytes.isEmpty {
                let bytes = uploadedBytes
                uploadLock.unlock()
                continuation.resume(returning: bytes)
            } else {
                uploadContinuation = continuation
                uploadLock.unlock()
            }
        }
    }

    private func handleControl(_ connection: NWConnection) {
        activeControlConnection = connection
        connection.start(queue: .global())
        write(connection, "220 Ready\r\n")
        readLoop(connection)
    }

    private func readLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self, let data, let line = String(data: data, encoding: .utf8), error == nil else { return }
            for command in line.split(separator: "\r\n", omittingEmptySubsequences: true) {
                self.handle(command: String(command), on: connection)
            }
            if !isComplete { self.readLoop(connection) }
        }
    }

    private func handle(command: String, on connection: NWConnection) {
        let verb = command.split(separator: " ").first.map(String.init)?.uppercased() ?? ""
        switch verb {
        case "USER": write(connection, "331 Password required\r\n")
        case "PASS": write(connection, "230 Logged in\r\n")
        case "TYPE": write(connection, "200 Type set\r\n")
        case "PASV": startDataListener(replyOn: connection)
        case "STOR": write(connection, "150 Opening data connection\r\n")
        case "QUIT": write(connection, "221 Bye\r\n")
        default: break
        }
    }

    private func startDataListener(replyOn control: NWConnection) {
        guard let listener = try? NWListener(using: tlsParameters()) else { return }
        dataListener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.receiveUpload(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard case .ready = state, let self, let port = listener.port?.rawValue else { return }
            let high = Int(port) >> 8
            let low = Int(port) & 0xFF
            self.write(control, "227 Entering Passive Mode (127,0,0,1,\(high),\(low)).\r\n")
        }
        listener.start(queue: .global())
    }

    private func receiveUpload(_ connection: NWConnection) {
        connection.start(queue: .global())
        var collected = Data()
        func pump() {
            connection.receive(minimumIncompleteLength: 0, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
                guard let self else { return }
                if let data { collected.append(data) }
                if isComplete {
                    self.uploadLock.lock()
                    self.uploadedBytes = collected
                    let continuation = self.uploadContinuation
                    self.uploadContinuation = nil
                    self.uploadLock.unlock()
                    continuation?.resume(returning: collected)
                    if let control = self.activeControlConnection {
                        self.write(control, "226 Transfer complete\r\n")
                    }
                } else {
                    pump()
                }
            }
        }
        pump()
    }

    private func write(_ connection: NWConnection, _ text: String) {
        connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in })
    }
}
