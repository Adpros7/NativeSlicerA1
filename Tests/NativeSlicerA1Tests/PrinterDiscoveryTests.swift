import XCTest
@testable import NativeSlicerA1

final class PrinterDiscoveryTests: XCTestCase {
    // Real NOTIFY format captured from a Bambu printer broadcast
    // (RESEARCH-P0-007.md — community reverse-engineering docs).
    private let sampleNotify = """
    NOTIFY * HTTP/1.1\r
    HOST: 239.255.255.250:1900\r
    Server: UPnP/1.0\r
    Location: 192.168.2.80\r
    NT: urn:bambulab-com:device:3dprinter:1\r
    USN: 01P00A392000494\r
    Cache-Control: max-age=1800\r
    DevModel.bambu.com: C12\r
    DevName.bambu.com: 3DP-01P-426\r
    DevSignal.bambu.com: -38\r
    DevConnect.bambu.com: lan\r
    DevBind.bambu.com: free\r
    DevVersion.bambu.com: 01.08.00.00\r
    DevCap.bambu.com: 1\r
    """

    func testParsesRealNotifyPacket() {
        let printer = SSDPNotifyParser.parse(sampleNotify)
        XCTAssertEqual(printer?.serial, "01P00A392000494")
        XCTAssertEqual(printer?.ipAddress, "192.168.2.80")
        XCTAssertEqual(printer?.model, "C12")
        XCTAssertEqual(printer?.name, "3DP-01P-426")
        XCTAssertEqual(printer?.signalStrengthDBm, -38)
        XCTAssertEqual(printer?.connectionMode, "lan")
    }

    func testRejectsNonBambuNotify() {
        let other = "NOTIFY * HTTP/1.1\r\nNT: urn:schemas-upnp-org:device:Basic:1\r\nUSN: x\r\nLocation: 1.2.3.4\r\n"
        XCTAssertNil(SSDPNotifyParser.parse(other))
    }

    func testRejectsMalformedPacket() {
        XCTAssertNil(SSDPNotifyParser.parse("garbage not even headers"))
    }
}

extension PrinterDiscoveryTests {
    /// Smoke test: proves the listener actually binds UDP 1990/2021 without
    /// throwing (real socket I/O, not just that the type compiles).
    func testListenerBindsRealSockets() throws {
        let discovery = PrinterDiscovery()
        try discovery.start()
        discovery.stop()
    }
}
