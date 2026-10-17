import Foundation
import AppKit
import AuthenticationServices

/// P5-001/P5-002: MakerWorld integration, scoped to what's actually safe
/// and implementable.
///
/// MakerWorld's real SSO mechanism (`func_request_bind_ticket`,
/// `NetworkAgent.cpp`) is closed-source in BOTH upstreams — it wraps a
/// proprietary `bambu_networking` plugin binary with no public API docs
/// (RESEARCH-P0-011-CONNECTIVITY.md §3.1). There is nothing to
/// reimplement: this app cannot generate a bind ticket, and reverse-
/// engineering Bambu's internal endpoints would be a real ToS risk. So,
/// per TODO.md P5-001's own recommendation, auth and browsing are
/// delegated entirely to the system/default browser — this app never
/// embeds a webview, never touches MakerWorld credentials, and never
/// calls any MakerWorld API directly. The browser handles the user's
/// real login on Bambu's own domain; this app only ever opens URLs.
///
/// Every URL this app hands to the system is gated through `isTrusted`
/// first (RESEARCH-P0-011-CONNECTIVITY.md §3.2's explicit CDN/domain
/// whitelist requirement) so a bug elsewhere can never cause this app to
/// silently launch an attacker-controlled page under the guise of
/// "MakerWorld".
enum MakerWorldLinks {
    /// Exact real domains this app will ever open — MakerWorld's own
    /// site plus its two known CDN domains (RESEARCH-P0-011-
    /// CONNECTIVITY.md §3.2). Subdomains of these are trusted; the bare
    /// domains themselves are NOT treated as suffixes of anything else
    /// (so `evil-makerworld.com` or `makerworld.com.evil.example` are
    /// correctly rejected).
    static let trustedDomains: Set<String> = [
        "makerworld.com",
        "makerworld.com.cn",
        "bblmw.com",
        "bblmw.cn",
    ]

    /// `https://makerworld.com/` is BambuStudio's own exact literal URL
    /// for opening MakerWorld (`.research/BambuStudio/src/slic3r/GUI/
    /// GUI_App.cpp:1608,1639` — grounded in real source, not guessed).
    /// There is no publicly-cited separate login path; the real site
    /// itself prompts for sign-in when the user interacts with an
    /// account-gated action, same as visiting it in any browser.
    static let signInURL = URL(string: "https://makerworld.com/")!
    static let browseURL = URL(string: "https://makerworld.com/")!

    /// True if `url` is HTTPS and its host is exactly one of
    /// `trustedDomains` or a subdomain of one.
    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), !host.isEmpty else {
            return false
        }
        return trustedDomains.contains { domain in
            host == domain || host.hasSuffix(".\(domain)")
        }
    }

    /// Opens `url` in the user's default system browser — never an
    /// embedded webview — after verifying it's a real MakerWorld domain.
    /// `actuallyOpen: false` (tests only) validates the trust check
    /// without launching a real browser process.
    @discardableResult
    static func openInSystemBrowser(_ url: URL, actuallyOpen: Bool = true) -> Bool {
        guard isTrusted(url) else { return false }
        if actuallyOpen {
            NSWorkspace.shared.open(url)
        }
        return true
    }
}

/// P5-001: delegates MakerWorld sign-in to a real system browser session
/// (`ASWebAuthenticationSession`) rather than reimplementing the closed-
/// source bind-ticket exchange. MakerWorld has no documented OAuth
/// redirect scheme for third-party apps, so this app cannot detect
/// "signed in" as a completion callback the way a real OAuth flow would
/// — the session simply shows the real makerworld.com login page; the
/// user logs in with their real Bambu account directly on Bambu's own
/// domain (this app never sees the credentials) and dismisses the sheet
/// when done. `prefersEphemeralWebBrowserSession = false` so the
/// resulting session cookie persists in the shared system browser
/// session, the same as a normal Safari login would.
@MainActor
final class MakerWorldAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    /// `window` anchors the system auth sheet; pass the app's main
    /// window. Completion fires once the sheet closes (manually by the
    /// user, since there's no real redirect to detect) — this app
    /// intentionally does NOT claim to know whether login succeeded.
    func presentSignIn(anchor window: NSWindow, completion: @escaping () -> Void = {}) {
        guard MakerWorldLinks.isTrusted(MakerWorldLinks.signInURL) else { return }
        self.anchorWindow = window
        let session = ASWebAuthenticationSession(
            url: MakerWorldLinks.signInURL,
            callbackURLScheme: "nativeslicera1"
        ) { _, _ in
            completion()
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        session.start()
    }

    private var anchorWindow: NSWindow?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchorWindow ?? NSApplication.shared.windows.first ?? NSWindow()
    }
}
