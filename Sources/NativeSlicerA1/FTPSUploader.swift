import Foundation
import Network

/// Real implicit-FTPS client (RESEARCH-P0-007.md §"FTPS (File Transfer)"):
/// port 990, TLS wrapping the control channel from connect, fixed
/// username `bblp`, password = the printer's LAN access code (same
/// credential `PrinterConnection` uses for MQTT), uploads into
/// `/sdcard/bbl_plater/`. No SFTP/SSH, no plaintext fallback — the
/// control channel is TLS-wrapped before any FTP command is sent, same
/// as implicit FTPS always works.
///
/// Built directly on `Network.framework` (the same framework
/// `PrinterDiscovery.swift` already uses for its `NWListener`) rather
/// than a new dependency: Foundation has no implicit-FTPS client, and no
/// FTP library is already a project dependency (AGENTS.md §15 — prefer
/// existing dependencies/stdlib before adding a new one).
enum FTPSError: Error, LocalizedError {
    case connectionFailed(String)
    case unexpectedReply(expected: [Int], got: String)
    case malformedPassiveReply(String)
    case transferFailed(String)
    case invalidRemoteFileName(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason): return "FTPS connection failed: \(reason)"
        case .unexpectedReply(let expected, let got): return "FTPS unexpected reply (expected \(expected)): \(got)"
        case .malformedPassiveReply(let reply): return "FTPS malformed PASV reply: \(reply)"
        case .transferFailed(let reason): return "FTPS transfer failed: \(reason)"
        case .invalidRemoteFileName(let name): return "FTPS invalid remote file name: \(name)"
        }
    }
}

final class FTPSUploader {
    private let host: String
    private let port: UInt16
    private let username: String
    private let password: String

    /// - Parameters:
    ///   - host: printer LAN IP (same host `PrinterConnection` connects to).
    ///   - password: the printer's LAN access code.
    init(host: String, username: String = "bblp", password: String, port: UInt16 = 990) {
        self.host = host
        self.username = username
        self.password = password
        self.port = port
    }

    /// Uploads `localURL`'s bytes to `/sdcard/bbl_plater/<remoteFileName>`
    /// via `STOR`, then returns the exact remote path
    /// `PrinterConnection.startPrint(fileName:)` needs.
    @discardableResult
    func upload(fileAt localURL: URL, remoteFileName: String) async throws -> String {
        // P8-002 security review: every current caller derives
        // `remoteFileName` from `URL(fileURLWithPath:).lastPathComponent`
        // of an internally UUID-generated path (`DeviceSessionModel`),
        // never raw user input — but `STOR \(remotePath)` builds a
        // plaintext FTP control-channel command line, so a future
        // caller passing an attacker-influenced name containing CR/LF
        // could inject additional FTP commands, and "/" could escape
        // the fixed `/sdcard/bbl_plater/` directory. Reject both here,
        // at the one function that actually formats the command, rather
        // than trusting every future call site to sanitize first.
        // Checked at the `unicodeScalars` level, not `Character`: Swift
        // collapses an adjacent CR+LF pair into ONE extended grapheme
        // cluster (`"\r\n".count == 1`), so comparing `Character`s
        // against `"\r"`/`"\n"` separately never matches a real CRLF
        // pair — exactly the injection this guard exists to catch.
        // Caught by `BackgroundSliceRegressionTests`-style direct
        // testing (`FTPSUploaderIntegrationTests
        // .testUploadRejectsInjectionCharactersInRemoteFileName`) before
        // this reached a real connection attempt.
        guard !remoteFileName.isEmpty,
              !remoteFileName.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" || $0 == "/" })
        else {
            throw FTPSError.invalidRemoteFileName(remoteFileName)
        }
        let control = try await Self.connectTLS(host: host, port: port)

        try await Self.expectReply(control, codes: [220])
        try await Self.sendLine("USER \(username)", to: control)
        try await Self.expectReply(control, codes: [230, 331])
        try await Self.sendLine("PASS \(password)", to: control)
        try await Self.expectReply(control, codes: [230])
        try await Self.sendLine("TYPE I", to: control)
        try await Self.expectReply(control, codes: [200])

        let dataPort = try await Self.enterPassiveMode(control)
        let data = try await Self.connectTLS(host: host, port: dataPort)

        let remotePath = "/sdcard/bbl_plater/\(remoteFileName)"
        try await Self.sendLine("STOR \(remotePath)", to: control)
        try await Self.expectReply(control, codes: [150, 125])

        let fileData = try Data(contentsOf: localURL)
        try await Self.writeAll(fileData, to: data)
        data.cancel()

        try await Self.expectReply(control, codes: [226, 250])
        try? await Self.sendLine("QUIT", to: control)
        return remotePath
    }

    // MARK: - Network.framework plumbing

    /// Opens a TLS connection with a custom verify block accepting the
    /// printer's self-signed certificate — no public CA signs it, the
    /// same trust model `PrinterConnection`'s MQTT `didReceiveTrust`
    /// already accepts for this exact device.
    private static func connectTLS(host: String, port: UInt16) async throws -> NWConnection {
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, complete in complete(true) },
            DispatchQueue.global()
        )
        let parameters = NWParameters(tls: tlsOptions, tcp: .init())
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: parameters
        )
        final class ResumeGuard: @unchecked Sendable {
            private let lock = NSLock()
            private var hasResumed = false
            func resumeOnce(_ body: () -> Void) {
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                body()
            }
        }
        let guardOnce = ResumeGuard()
        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guardOnce.resumeOnce { continuation.resume(returning: connection) }
                case .failed(let error):
                    guardOnce.resumeOnce { continuation.resume(throwing: FTPSError.connectionFailed(error.localizedDescription)) }
                case .cancelled:
                    guardOnce.resumeOnce { continuation.resume(throwing: FTPSError.connectionFailed("cancelled before ready")) }
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    private static func sendLine(_ line: String, to connection: NWConnection) async throws {
        let data = Data("\(line)\r\n".utf8)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: FTPSError.connectionFailed(error.localizedDescription)) }
                else { continuation.resume(returning: ()) }
            })
        }
    }

    /// Reads one FTP control-channel reply line (`"NNN message\r\n"`, or
    /// a multi-line reply's final `"NNN message\r\n"` — FTP multi-line
    /// replies use `"NNN-..."` continuation lines ending with a matching
    /// `"NNN "` final line; this reads raw bytes until a `\n` and returns
    /// that one line, which is sufficient for every reply this printer's
    /// FTPS server actually sends during upload).
    private static func readLine(from connection: NWConnection) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: FTPSError.connectionFailed(error.localizedDescription))
                    return
                }
                guard let data, let text = String(data: data, encoding: .utf8) else {
                    continuation.resume(throwing: FTPSError.connectionFailed("no reply data"))
                    return
                }
                continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private static func expectReply(_ connection: NWConnection, codes: [Int]) async throws {
        let line = try await readLine(from: connection)
        guard let code = Int(line.prefix(3)), codes.contains(code) else {
            throw FTPSError.unexpectedReply(expected: codes, got: line)
        }
    }

    /// Sends `PASV`, parses the real
    /// `227 Entering Passive Mode (h1,h2,h3,h4,p1,p2).` reply format.
    private static func enterPassiveMode(_ connection: NWConnection) async throws -> UInt16 {
        try await sendLine("PASV", to: connection)
        let line = try await readLine(from: connection)
        guard line.hasPrefix("227") else { throw FTPSError.unexpectedReply(expected: [227], got: line) }
        return try parsePassivePort(line)
    }

    static func parsePassivePort(_ reply: String) throws -> UInt16 {
        guard let open = reply.firstIndex(of: "("), let close = reply.firstIndex(of: ")"), open < close else {
            throw FTPSError.malformedPassiveReply(reply)
        }
        let numbers = reply[reply.index(after: open)..<close].split(separator: ",").compactMap { Int($0) }
        guard numbers.count == 6 else { throw FTPSError.malformedPassiveReply(reply) }
        let port = (numbers[4] << 8) + numbers[5]
        guard (0...65535).contains(port) else { throw FTPSError.malformedPassiveReply(reply) }
        return UInt16(port)
    }

    private static func writeAll(_ data: Data, to connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: FTPSError.transferFailed(error.localizedDescription)) }
                else { continuation.resume(returning: ()) }
            })
        }
    }
}
