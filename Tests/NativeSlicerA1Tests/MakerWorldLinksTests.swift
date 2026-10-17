import XCTest
@testable import NativeSlicerA1

/// P5-001/P5-002: MakerWorld integration is explicitly scoped to
/// delegating auth and browsing to the system browser (TODO.md's own
/// recommendation, RESEARCH-P0-011-CONNECTIVITY.md §3) — the bind-ticket
/// SSO mechanism is closed-source (no public implementation to cite;
/// `NetworkAgent.cpp`'s `func_request_bind_ticket()` wraps a proprietary
/// plugin even in both upstreams), so this app never embeds a webview or
/// talks to any MakerWorld API directly. The one real, testable piece of
/// logic is the domain whitelist that gates every URL this app will ever
/// hand to the system browser — RESEARCH-P0-011-CONNECTIVITY.md's §3.2
/// flags exactly this as a required security control.
final class MakerWorldLinksTests: XCTestCase {
    func testRealMakerWorldDomainsAreTrusted() {
        XCTAssertTrue(MakerWorldLinks.isTrusted(URL(string: "https://makerworld.com")!))
        XCTAssertTrue(MakerWorldLinks.isTrusted(URL(string: "https://www.makerworld.com/en/login")!))
        XCTAssertTrue(MakerWorldLinks.isTrusted(URL(string: "https://makerworld.com.cn")!), "real China-region domain, BambuStudio GUI_App.cpp:1611")
        XCTAssertTrue(MakerWorldLinks.isTrusted(URL(string: "https://public-cdn.bblmw.com/models/abc.3mf")!))
        XCTAssertTrue(MakerWorldLinks.isTrusted(URL(string: "https://makerworld.bblmw.cn/x")!))
    }

    /// A lookalike/attacker-controlled domain must never be treated as
    /// trusted just because it contains or is prefixed by a real one.
    func testLookalikeDomainsAreRejected() {
        XCTAssertFalse(MakerWorldLinks.isTrusted(URL(string: "https://makerworld.com.evil.example")!))
        XCTAssertFalse(MakerWorldLinks.isTrusted(URL(string: "https://evil-makerworld.com")!))
        XCTAssertFalse(MakerWorldLinks.isTrusted(URL(string: "https://notmakerworld.com")!))
        XCTAssertFalse(MakerWorldLinks.isTrusted(URL(string: "http://makerworld.com")!), "http (non-TLS) must not be trusted for an auth/credential-adjacent flow")
    }

    func testSignInAndBrowseURLsAreThemselvesTrusted() {
        XCTAssertTrue(MakerWorldLinks.isTrusted(MakerWorldLinks.signInURL))
        XCTAssertTrue(MakerWorldLinks.isTrusted(MakerWorldLinks.browseURL))
    }

    /// `openInSystemBrowser` is the single chokepoint every MakerWorld
    /// URL in this app must go through — it must refuse an untrusted URL
    /// rather than silently handing it to `NSWorkspace`.
    func testOpenInSystemBrowserRefusesUntrustedURLs() {
        XCTAssertFalse(MakerWorldLinks.openInSystemBrowser(URL(string: "https://evil.example/phish")!, actuallyOpen: false))
        XCTAssertTrue(MakerWorldLinks.openInSystemBrowser(MakerWorldLinks.browseURL, actuallyOpen: false))
    }
}
