import XCTest
@testable import NativeSlicerA1

final class FTPSUploaderTests: XCTestCase {
    func testParsesRealPassiveModeReply() throws {
        let port = try FTPSUploader.parsePassivePort("227 Entering Passive Mode (192,168,1,50,200,15).")
        XCTAssertEqual(port, 200 * 256 + 15)
    }

    func testMalformedPassiveReplyThrows() {
        XCTAssertThrowsError(try FTPSUploader.parsePassivePort("227 Entering Passive Mode"))
    }

    func testPassivePortOutOfRangeComponentsStillParseWithinUInt16() throws {
        // Edge values (0 and 255 per octet) must round-trip through the
        // real (h1<<8)+h2 formula without overflow.
        let port = try FTPSUploader.parsePassivePort("227 OK (10,0,0,1,255,255).")
        XCTAssertEqual(port, 65535)
    }
}
