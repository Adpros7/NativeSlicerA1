import XCTest
import Network
import Security
@testable import NativeSlicerA1

/// Real end-to-end proof of `CameraStreamClient`: a genuine TLS
/// `NWListener` (reusing the same test identity fixture as
/// `FTPSUploaderIntegrationTests`) validates the real 80-byte auth
/// packet byte-for-byte, then sends a real 16-byte header + minimal
/// valid JPEG (SOI/EOI markers) — proving the documented protocol round
/// trips over a real socket and TLS handshake, not a mock.
final class CameraStreamClientIntegrationTests: XCTestCase {
    func testFetchesRealJPEGFrameOverRealTLSConnection() async throws {
        let identity = try Self.loadTestIdentity()
        let jpeg = Data([0xFF, 0xD8, 0x00, 0x01, 0x02, 0xFF, 0xD9])

        let server = TestCameraServer(identity: identity, framePayload: jpeg)
        let port = try await server.start()
        defer { server.stop() }

        let client = CameraStreamClient(host: "127.0.0.1", password: "testpass")
        let received = try await client.fetchFrame(port: port)

        XCTAssertEqual(received, jpeg)
        let authBytes = try await server.waitForAuthPacket()
        XCTAssertEqual(authBytes, CameraStreamClient.authPacket(username: "bblp", password: "testpass"))
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
            throw XCTSkip("Could not import test TLS identity (status \(status))")
        }
        return identity
    }
}

private final class TestCameraServer: @unchecked Sendable {
    private let identity: SecIdentity
    private let framePayload: Data
    private var listener: NWListener?
    private let lock = NSLock()
    private var authContinuation: CheckedContinuation<Data, Error>?
    private var receivedAuth: Data?

    init(identity: SecIdentity, framePayload: Data) {
        self.identity = identity
        self.framePayload = framePayload
    }

    func start() async throws -> UInt16 {
        let tlsOptions = NWProtocolTLS.Options()
        guard let secIdentity = sec_identity_create(identity) else {
            fatalError("sec_identity_create failed for test fixture identity")
        }
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentity)
        let listener = try NWListener(using: NWParameters(tls: tlsOptions, tcp: .init()))
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        return try await withCheckedThrowingContinuation { continuation in
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
            listener.start(queue: .global())
        }
    }

    func stop() { listener?.cancel() }

    func waitForAuthPacket() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let receivedAuth {
                lock.unlock()
                continuation.resume(returning: receivedAuth)
            } else {
                authContinuation = continuation
                lock.unlock()
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 80, maximumLength: 80) { [weak self] data, _, _, _ in
            guard let self, let data else { return }
            self.lock.lock()
            self.receivedAuth = data
            let continuation = self.authContinuation
            self.authContinuation = nil
            self.lock.unlock()
            continuation?.resume(returning: data)

            var header = Data()
            for value: UInt32 in [UInt32(self.framePayload.count), 0, 1, 0] {
                withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
            }
            connection.send(content: header + self.framePayload, completion: .contentProcessed { _ in })
        }
    }
}
