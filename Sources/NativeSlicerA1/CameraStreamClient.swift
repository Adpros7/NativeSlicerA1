import Foundation
import Network

/// P7-001: real A1/P1 chamber camera client — the documented (not
/// "proprietary/unimplementable") `OpenBambuAPI/video.md` protocol:
/// implicit-TLS TCP on port 6000, an 80-byte auth packet, then
/// repeating 16-byte frame headers each followed by that many bytes of
/// JPEG payload. Same `Network.framework` TLS pattern as
/// `FTPSUploader.swift`. 1 fps is a real A1 hardware limitation
/// (RESEARCH-P0-010.md), not a NativeSlicerA1 shortcut.
enum CameraStreamError: Error, LocalizedError {
    case connectionFailed(String)
    case invalidFrame(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason): return "Camera connection failed: \(reason)"
        case .invalidFrame(let reason): return "Camera protocol error: \(reason)"
        }
    }
}

final class CameraStreamClient {
    private let host: String
    private let username: String
    private let password: String
    private var connection: NWConnection?

    /// - Parameters:
    ///   - host: printer LAN IP (same host `PrinterConnection` connects to).
    ///   - password: the printer's LAN access code.
    init(host: String, username: String = "bblp", password: String) {
        self.host = host
        self.username = username
        self.password = password
    }

    /// Builds the real 80-byte auth packet: `(0x40,0x3000,0,0)` as
    /// little-endian `UInt32`s, then username/password each ASCII,
    /// NUL-padded to 32 bytes (`OpenBambuAPI/video.md` §A1 and
    /// P1 → Authentication).
    static func authPacket(username: String, password: String) -> Data {
        var data = Data()
        for value: UInt32 in [0x40, 0x3000, 0, 0] {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(Self.padded(username, to: 32))
        data.append(Self.padded(password, to: 32))
        return data
    }

    private static func padded(_ string: String, to length: Int) -> Data {
        var bytes = Array(string.utf8.prefix(length))
        bytes += Array(repeating: 0, count: length - bytes.count)
        return Data(bytes)
    }

    /// Parses one real 16-byte frame header into its JPEG payload size
    /// (the only field this client needs; `itrack`/flags are read but
    /// unused, matching the documented protocol's "normally 0"/"normally
    /// 1" values with no NativeSlicerA1-specific behavior keyed on them).
    static func payloadSize(fromHeader header: Data) throws -> Int {
        guard header.count == 16 else {
            throw CameraStreamError.invalidFrame("header must be 16 bytes, got \(header.count)")
        }
        let size = header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
        let littleEndianSize = UInt32(littleEndian: size)
        guard littleEndianSize > 0, littleEndianSize < 20 * 1024 * 1024 else {
            throw CameraStreamError.invalidFrame("implausible payload size \(littleEndianSize)")
        }
        return Int(littleEndianSize)
    }

    /// Connects, authenticates, and receives exactly one real JPEG
    /// frame. The A1's 1 fps hardware limit (RESEARCH-P0-010.md) makes a
    /// per-call single-frame fetch — not a continuous stream — the
    /// natural shape for a UI "refresh snapshot" action. `port`
    /// defaults to the real A1/P1 hardware port (6000); overridable for
    /// local protocol testing, same as `FTPSUploader`'s `port` default.
    func fetchFrame(port: UInt16 = 6000) async throws -> Data {
        let connection = try await Self.connectTLS(host: host, port: port)
        self.connection = connection
        defer { connection.cancel() }

        try await Self.send(Self.authPacket(username: username, password: password), to: connection)
        let header = try await Self.receiveExact(16, from: connection)
        let payloadSize = try Self.payloadSize(fromHeader: header)
        let jpeg = try await Self.receiveExact(payloadSize, from: connection)
        guard jpeg.starts(with: [0xFF, 0xD8]) else {
            throw CameraStreamError.invalidFrame("payload does not start with JPEG SOI marker")
        }
        return jpeg
    }

    // MARK: - Network.framework plumbing (same pattern as FTPSUploader)

    private static func connectTLS(host: String, port: UInt16) async throws -> NWConnection {
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, complete in complete(true) },
            DispatchQueue.global()
        )
        let parameters = NWParameters(tls: tlsOptions, tcp: .init())
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: parameters)

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
                    guardOnce.resumeOnce { continuation.resume(throwing: CameraStreamError.connectionFailed(error.localizedDescription)) }
                case .cancelled:
                    guardOnce.resumeOnce { continuation.resume(throwing: CameraStreamError.connectionFailed("cancelled before ready")) }
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    private static func send(_ data: Data, to connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: CameraStreamError.connectionFailed(error.localizedDescription)) }
                else { continuation.resume(returning: ()) }
            })
        }
    }

    /// Reads exactly `count` bytes, concatenating chunks as needed — the
    /// documented protocol explicitly notes a JPEG payload "might be
    /// received in multiple chunks".
    private static func receiveExact(_ count: Int, from connection: NWConnection) async throws -> Data {
        var collected = Data()
        while collected.count < count {
            let remaining = count - collected.count
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: CameraStreamError.connectionFailed(error.localizedDescription))
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(throwing: CameraStreamError.connectionFailed("connection closed before \(count) bytes received"))
                    } else {
                        continuation.resume(returning: Data())
                    }
                }
            }
            collected.append(chunk)
        }
        return collected
    }
}
