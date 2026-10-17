import XCTest
@testable import NativeSlicerA1

final class CameraStreamClientTests: XCTestCase {
    /// Byte-exact against the documented protocol
    /// (`OpenBambuAPI/video.md` §A1 and P1 → Authentication):
    /// 0x40,0x3000,0,0 little-endian, then username/password each
    /// NUL-padded to 32 bytes — 80 bytes total.
    func testAuthPacketMatchesDocumentedByteLayout() {
        let packet = CameraStreamClient.authPacket(username: "bblp", password: "12345678")
        XCTAssertEqual(packet.count, 80)

        let header = [UInt8](packet.prefix(16))
        XCTAssertEqual(header, [0x40, 0, 0, 0, 0x00, 0x30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

        let username = packet[packet.index(packet.startIndex, offsetBy: 16)..<packet.index(packet.startIndex, offsetBy: 48)]
        XCTAssertEqual(username.prefix(4), Data("bblp".utf8))
        XCTAssertTrue(username.dropFirst(4).allSatisfy { $0 == 0 })

        let password = packet[packet.index(packet.startIndex, offsetBy: 48)..<packet.index(packet.startIndex, offsetBy: 80)]
        XCTAssertEqual(password.prefix(8), Data("12345678".utf8))
        XCTAssertTrue(password.dropFirst(8).allSatisfy { $0 == 0 })
    }

    func testPayloadSizeParsesRealLittleEndianHeader() throws {
        // Documented header: payload size (4), itrack (4), flags (4), reserved (4).
        var header = Data()
        for value: UInt32 in [12345, 0, 1, 0] {
            withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
        }
        XCTAssertEqual(try CameraStreamClient.payloadSize(fromHeader: header), 12345)
    }

    func testPayloadSizeRejectsWrongHeaderLength() {
        XCTAssertThrowsError(try CameraStreamClient.payloadSize(fromHeader: Data(count: 10)))
    }

    func testPayloadSizeRejectsImplausibleSize() throws {
        var header = Data()
        for value: UInt32 in [0, 0, 1, 0] {
            withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
        }
        XCTAssertThrowsError(try CameraStreamClient.payloadSize(fromHeader: header))
    }
}
