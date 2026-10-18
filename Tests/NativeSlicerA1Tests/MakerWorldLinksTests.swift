import XCTest
@testable import NativeSlicerA1

/// P5-001/P5-002/P5-003: MakerWorld integration. Sign-in stays
/// delegated to the system browser — the real bind-ticket SSO
/// mechanism is closed-source (no public implementation to cite;
/// `NetworkAgent.cpp`'s `func_request_bind_ticket()` wraps a
/// proprietary plugin even in both upstreams) — but browsing now uses
/// a real embedded `WKWebView` (`MakerWorldWebView`), matching Bambu
/// Studio's own approach exactly (`WebViewDialog.cpp`'s
/// `SetMakerworldModelID`/`OpenMakerworldSearchPage`). The domain
/// whitelist gates every URL this app will ever navigate to or hand
/// to the system browser — RESEARCH-P0-011-CONNECTIVITY.md §3.2 flags
/// exactly this as a required security control.
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

    /// Matches BambuStudio's `WebViewPanel::SetMakerworldModelID()`
    /// exactly (`WebViewDialog.cpp:2225-2230`): `{host}studio/webview
    /// ?modelid={id}&from=bambustudio`.
    func testModelURLMatchesBambuStudioFormat() {
        let url = MakerWorldLinks.modelURL(for: "123456")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "https://makerworld.com/studio/webview?modelid=123456&from=bambustudio")
        XCTAssertTrue(MakerWorldLinks.isTrusted(url!), "a URL this app constructs itself must always pass its own trust check")
    }

    /// Matches BambuStudio's `WebViewPanel::OpenMakerworldSearchPage()`
    /// exactly (`WebViewDialog.cpp:2213`): `{host}studio/webview/search
    /// ?from=bambustudio&keyword={kw}&from_studio_home=true`.
    func testSearchURLMatchesBambuStudioFormat() {
        let url = MakerWorldLinks.searchURL(for: "benchy")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "https://makerworld.com/studio/webview/search?from=bambustudio&keyword=benchy&from_studio_home=true")
        XCTAssertTrue(MakerWorldLinks.isTrusted(url!))
    }

    /// A search keyword containing characters that are meaningful in a
    /// URL query (space, `&`) must be percent-encoded, not passed
    /// through raw — an unencoded `&` would silently truncate/corrupt
    /// the query string.
    func testSearchURLPercentEncodesSpecialCharacters() {
        let url = MakerWorldLinks.searchURL(for: "cable clip & holder")
        XCTAssertNotNil(url)
        XCTAssertFalse(url!.absoluteString.contains(" "), "raw space must be percent-encoded")
        XCTAssertEqual(url?.query?.components(separatedBy: "&").count, 4, "the real '&' must be escaped, not read back as a 4th query parameter")
    }

    /// Matches BambuStudio's JSON bridge format from
    /// `GUI_App.cpp::handle_web_request()` (`sequence_id`, `command`,
    /// `data`) — the exact shape the embedded page's
    /// `window.postMessage()` sends.
    func testBridgeMessageParsesRealBambuStudioJSONShape() {
        let json = """
        {"sequence_id": "42", "command": "modelmall_model_open", "data": {"id": "987654"}}
        """
        let message = MakerWorldBridgeMessage(jsonString: json)
        XCTAssertNotNil(message)
        XCTAssertEqual(message?.sequenceId, "42")
        XCTAssertEqual(message?.command, "modelmall_model_open")
        XCTAssertEqual(message?.data?["id"] as? String, "987654")
    }

    /// Malformed/garbage JSON from the embedded page must fail to
    /// parse rather than crash, matching BambuStudio's own silent
    /// drop of unrecognized/malformed bridge payloads.
    func testBridgeMessageRejectsMalformedJSON() {
        XCTAssertNil(MakerWorldBridgeMessage(jsonString: "not json at all"))
        XCTAssertNil(MakerWorldBridgeMessage(jsonString: "{\"sequence_id\": \"1\"}"), "missing required 'command' field")
    }
}
