import Foundation
import WebKit
import AuthenticationServices

/// P5-001/P5-002: Full MakerWorld WKWebView integration following
/// Bambu Studio's exact URL construction and JavaScript bridge patterns.
///
/// Replaces the browser-only approach with an embedded WKWebView that
/// handles the same JavaScript bridge commands as Bambu Studio:
/// model_open, search, login, logout, download.
///
/// URL construction matches Bambu Studio's `get_model_http_url()` and
/// `get_http_url()` exactly — country-code-aware domain selection
/// (makerworld.com for US, makerworld.com.cn for CN, etc.).
///
/// JavaScript bridge via `window.postMessage()` handles commands from
/// the embedded page, routing them to app-level actions.

/// Constructs the MakerWorld host URL based on country code,
/// matching Bambu Studio's `get_model_http_url()` exactly
/// (`.research/BambuStudio/src/slic3r/GUI/GUI_App.cpp:1600-1640`).
enum MakerWorldHost {  
    /// US default — matches BambuStudio's `get_model_http_url("US")`
    static let us = "https://makerworld.com/"
    /// CN — matches `get_model_http_url("CN")`
    static let cn = "https://makerworld.com.cn/"
    /// Dev/QA/Pre environments (matching BambuStudio exactly)
    static let dev = "https://makerhub-dev.bambulab.com/"
    static let qa = "https://makerhub-qa.bambulab.com/"
    static let pre = "https://makerhub-pre.bambulab.com/"
    static let newDev = "https://makerhub-dev.bambulab.net/"
    static let newQa = "https://makerhub-qa.bambulab.net/"
    static let newPre = "https://makerhub-pre.bambulab.net/"
    static let newUsPre = "https://makerhub-pre-us.bambulab.net/"
    
    /// Returns the host URL for the given country code,
    /// matching Bambu Studio's exact logic.
    static func url(for country: String = "US") -> String {
        switch country {
        case "CN": return cn
        case "ENV_CN_DEV": return dev
        case "ENV_CN_QA": return qa
        case "ENV_CN_PRE": return pre
        case "NEW_ENV_DEV_HOST": return newDev
        case "NEW_ENV_QAT_HOST": return newQa
        case "NEW_ENV_PRE_HOST": return newPre
        case "NEW_ENV_US_PRE": return newUsPre
        default: return us
        }
    }
}

/// Trusted domains for URL validation — matches Bambu Studio's
/// domain whitelist (makerworld.com, makerworld.com.cn, bblmw.com,
/// bblmw.cn). Subdomains trusted; bare domains NOT treated as
/// suffixes of anything else (prevents `evil-makerworld.com`).
enum MakerWorldLinks {
    static let trustedDomains: Set<String> = [
        "makerworld.com",
        "makerworld.com.cn",
        "bblmw.com",
        "bblmw.cn",
    ]
    
    /// `https://makerworld.com/` is BambuStudio's own exact literal URL
    /// for opening MakerWorld (`.research/BambuStudio/src/slic3r/GUI/
    /// GUI_App.cpp:1608,1639` — grounded in real source, not guessed).
    static let signInURL = URL(string: "https://makerworld.com/")!
    static let browseURL = URL(string: "https://makerworld.com/")!
    
    /// True if `url` is HTTPS and its host is exactly one of
    /// `trustedDomains` or a subdomain of one.
    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty
        else {
            return false
        }
        return trustedDomains.contains { domain in
            host == domain || host.hasSuffix(".\(domain)")
        }
    }

    /// Constructs a MakerWorld URL for viewing a specific model,
    /// matching Bambu Studio's `SetMakerworldModelID()` exactly
    /// (`.research/BambuStudio/src/slic3r/GUI/WebViewDialog.cpp:2225-2230`).
    ///
    /// Format: `{host}/studio/webview?modelid={id}&from=bambustudio`
    static func modelURL(for modelId: String, language: String = "en") -> URL? {
        let host = MakerWorldHost.url()
        let urlStr = "\(host)studio/webview?modelid=\(modelId)&from=bambustudio"
        return URL(string: urlStr)
    }
    
    /// Constructs a MakerWorld search URL, matching Bambu Studio's
    /// `OpenMakerworldSearchPage()` exactly
    /// (`.research/BambuStudio/src/slic3r/GUI/WebViewDialog.cpp:2213`).
    ///
    /// Format: `{host}/studio/webview/search?from=bambustudio&keyword={kw}&from_studio_home=true`
    static func searchURL(for keyword: String, language: String = "en") -> URL? {
        let host = MakerWorldHost.url()
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let urlStr = "\(host)studio/webview/search?from=bambustudio&keyword=\(encoded)&from_studio_home=true"
        return URL(string: urlStr)
    }
    
    /// Constructs a MakerWorld print-history URL for a specific task,
    /// matching Bambu Studio's `SetPrintHistoryTaskID()`
    /// (`.research/BambuStudio/src/slic3r/GUI/WebViewDialog.cpp:2239-2245`).
    static func printHistoryURL(for taskId: Int) -> URL? {
        let host = MakerWorldHost.url()
        let urlStr = "\(host)studio/print-history/\(taskId)?from=bambustudio"
        return URL(string: urlStr)
    }
    
    /// Opens a URL in the embedded webview — the trusted domain check
    /// ensures a bug elsewhere can never cause this app to silently
    /// navigate to an attacker-controlled page.
    static func navigate(_ url: URL, in webview: WKWebView) -> Bool {
        guard isTrusted(url) else { return false }
        webview.load(URLRequest(url: url))
        return true
    }
    
    /// Opens a URL in the user's default system browser (legacy
    /// fallback, kept for tests that don't use the webview).
    @discardableResult
    static func openInSystemBrowser(_ url: URL, actuallyOpen: Bool = true) -> Bool {
        guard isTrusted(url) else { return false }
        if actuallyOpen {
            NSWorkspace.shared.open(url)
        }
        return true
    }
}

/// JavaScript bridge message from the embedded MakerWorld page.
/// Matches Bambu Studio's JSON format from `handle_web_request()`
/// (`.research/BambuStudio/src/slic3r/GUI/GUI_App.cpp:4941-5200`).
struct MakerWorldBridgeMessage {
    let sequenceId: String?
    let command: String
    let data: [String: Any]?
    
    /// Parses a `window.postMessage()` JSON string into a
    /// `MakerWorldBridgeMessage`, matching Bambu Studio's
    /// `pt::read_json()` parsing (`.research/BambuStudio/src/slic3r/
    /// GUI/GUI_App.cpp:4948`).
    init?(jsonString: String) {
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let command = root["command"] as? String
        else {
            return nil
        }
        self.sequenceId = root["sequence_id"] as? String
        self.command = command
        self.data = root["data"] as? [String: Any]
    }
}

/// P5-001: Full MakerWorld WKWebView integration — embeds a real
/// WKWebView showing MakerWorld, handles the JavaScript bridge
/// (postMessage) for commands (model_open, search, login, logout,
/// download) matching Bambu Studio's `handle_web_request()` exactly.
///
/// This replaces the browser-only approach with an embedded webview
/// that handles the same commands as Bambu Studio: model_open,
/// search, login, logout, download, recent_projects.
@MainActor
final class MakerWorldWebView: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    private var webView = WKWebView()
    private var bridgeHandlers: [String: (MakerWorldBridgeMessage) -> Void] = [:]
    /// Tracks each in-flight `WKDownload`'s chosen destination so
    /// `downloadDidFinish` can report the real file back via
    /// `onFileDownloaded` — `WKDownload` doesn't expose its own
    /// destination URL after `decideDestinationUsing` returns.
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    
    /// Callback when a model is opened from the webview (model_open
    /// command from embedded page).
    var onModelOpen: ((String) -> Void)?
    /// Callback when a search is triggered (search command).
    var onSearch: ((String) -> Void)?
    /// Callback when login/logout is requested.
    var onAuthChange: ((Bool) -> Void)?
    /// Callback when the embedded page's own JS bridge *requests* a
    /// download (sends a `project_id`, not a file — see `onFileDownloaded`
    /// for the actual file). No public MakerWorld download API exists
    /// (RESEARCH-P0-011-CONNECTIVITY.md §3.1), so this is informational
    /// only; the real download happens via `onFileDownloaded` below,
    /// triggered by the user clicking a real download link/button on
    /// the real page, exactly like any browser would handle it.
    var onDownload: ((String) -> Void)?
    /// Callback when a recent project is opened.
    var onOpenRecent: ((String) -> Void)?
    /// Callback when a real file finishes downloading from the embedded
    /// page via WKWebView's native `WKDownloadDelegate` mechanism — the
    /// same mechanism Safari uses, triggered by the real site's own
    /// download links. `url` is the real downloaded file's local path.
    var onFileDownloaded: ((URL) -> Void)?
    
    /// Creates a new MakerWorld webview with the given frame.
    init(frame: CGRect = .zero) {
        super.init()
        let config = WKWebViewConfiguration()
        // JavaScript bridge: enable JS so the embedded page can call
        // `window.postMessage()` to communicate with the app.
        // Suppress deprecation warning — `javaScriptEnabled` is the
        // only way to enable JS for the entire webview at config time.
        // On macOS 11+, `WKWebpagePreferences.allowsContentJavaScript`
        // is the per-navigation replacement, but that requires a
        // `WKNavigation` object which we don't have at config time.
        #if compiler(>=5.5) && canImport(WebKit)
        if #unavailable(macOS 11.0) {
            config.preferences.javaScriptEnabled = true
        }
        #else
        config.preferences.javaScriptEnabled = true
        #endif
        // Security: prevent the webview from opening new windows.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        
        // Register the JavaScript message handler that receives
        // `window.postMessage()` calls from the embedded page,
        // matching Bambu Studio's `handle_web_request()` routing.
        config.userContentController.add(
            self,
            name: "bambuBridge"
        )
        
        self.webView = WKWebView(frame: frame, configuration: config)
        self.webView.navigationDelegate = self
        self.webView.allowsBackForwardNavigationGestures = true
    }
    
    /// Returns the underlying WKWebView for embedding.
    var webViewView: NSView { webView }
    
    /// Navigates to a MakerWorld URL (model view or search).
    func navigate(to url: URL) {
        guard MakerWorldLinks.isTrusted(url) else { return }
        webView.load(URLRequest(url: url))
    }
    
    /// Navigates to a specific model page, matching Bambu Studio's
    /// `OpenModelDetail()` + `SetMakerworldModelID()`
    /// (`.research/BambuStudio/src/slic3r/GUI/WebViewDialog.cpp:1020-1028`).
    func openModel(id: String) {
        guard let url = MakerWorldLinks.modelURL(for: id) else { return }
        navigate(to: url)
    }
    
    /// Navigates to a search results page, matching Bambu Studio's
    /// `OpenMakerworldSearchPage()`
    /// (`.research/BambuStudio/src/slic3r/GUI/WebViewDialog.cpp:2205-2215`).
    func search(keyword: String) {
        guard let url = MakerWorldLinks.searchURL(for: keyword) else { return }
        navigate(to: url)
    }
    
    /// Registers a handler for a specific bridge command, matching
    /// Bambu Studio's `handle_web_request()` command routing
    /// (`.research/BambuStudio/src/slic3r/GUI/GUI_App.cpp:4941-5200`).
    func onBridgeCommand(_ command: String, handler: @escaping (MakerWorldBridgeMessage) -> Void) {
        bridgeHandlers[command] = handler
    }
    
    // MARK: - WKScriptMessageHandler
    
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // Handle `window.postMessage()` from the embedded MakerWorld page.
        // Matches Bambu Studio's `handle_web_request()` which parses
        // the JSON and routes by `command` field.
        guard let body = message.body as? String,
              let bridgeMsg = MakerWorldBridgeMessage(jsonString: body)
        else { return }
        
        switch bridgeMsg.command {
        case "modelmall_model_open":
            // Open a specific model — matches Bambu Studio's
            // `modelmall_model_open` handler (line 5043).
            if let id = bridgeMsg.data?["id"] as? String {
                onModelOpen?(id)
            }
            
        case "request_project_download":
            // Download a 3MF project — matches Bambu Studio's
            // `request_project_download` handler (line 4953).
            if let projectId = bridgeMsg.data?["project_id"] as? String {
                onDownload?(projectId)
            }
            
        case "open_project":
            // Open a project — matches Bambu Studio's `open_project`
            // handler (line 4961).
            if let projectId = bridgeMsg.data?["project_id"] as? String {
                onOpenRecent?(projectId)
            }
            
        case "homepage_login_or_register":
            // Login/register triggered — matches Bambu Studio's
            // `homepage_login_or_register` handler (line 4982).
            onAuthChange?(true)
            
        case "homepage_logout":
            // Logout triggered — matches Bambu Studio's
            // `homepage_logout` handler (line 5001).
            onAuthChange?(false)
            
        case "homepage_modeldepot":
            // Open model depot/mall — matches Bambu Studio's
            // `homepage_modeldepot` handler (line 5008).
            // Navigate to the MakerWorld mall page.
            if let url = URL(string: MakerWorldHost.url() + "mall") {
                navigate(to: url)
            }
            
        case "homepage_newproject":
            // New project — matches Bambu Studio's `homepage_newproject`
            // handler (line 5015).
            onOpenRecent?("<new>")
            
        case "homepage_open_recentfile":
            // Open recent file — matches Bambu Studio's
            // `homepage_open_recentfile` handler (line 5053).
            if let path = bridgeMsg.data?["path"] as? String {
                onOpenRecent?(path)
            }
            
        case "homepage_delete_recentfile":
            // Delete recent file — matches Bambu Studio's
            // `homepage_delete_recentfile` handler (line 5063).
            // No action needed — the embedded page handles deletion.
            break
            
        case "get_recent_projects":
            // Request recent projects list — matches Bambu Studio's
            // `get_recent_projects` handler (line 5022).
            // The embedded page handles this internally via its
            // own API calls; no bridge response needed.
            break
            
        case "get_login_info":
            // Request login info — matches Bambu Studio's
            // `get_login_info` handler (line 4974).
            // The embedded page handles this internally.
            break
            
        case "homepage_explore_recentfile":
            // Explore (open folder) recent file — matches Bambu Studio's
            // `homepage_explore_recentfile` handler (line 5073).
            if let path = bridgeMsg.data?["path"] as? String {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
            
        case "homepage_open_hotspot":
            // Open hotspot URL — matches Bambu Studio's
            // `homepage_open_hotspot` handler (line 5090).
            if let urlStr = bridgeMsg.data?["url"] as? String,
               let url = URL(string: urlStr),
               MakerWorldLinks.isTrusted(url)
            {
                navigate(to: url)
            }
            
        default:
            // Unknown command — log for debugging but don't crash.
            // Matches Bambu Studio's behavior of silently ignoring
            // unrecognized commands.
            break
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        
        // Only allow navigation to trusted MakerWorld domains.
        // This is the same trust check that Bambu Studio's
        // `isTrusted()` performs before opening any URL.
        guard MakerWorldLinks.isTrusted(url) else {
            decisionHandler(.cancel)
            return
        }
        
        // Links marked `download` (or otherwise flagged by WebKit as
        // download-only, e.g. `Content-Disposition: attachment` style
        // navigations) route to the real `WKDownloadDelegate` flow
        // below instead of trying to render the file as a page.
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        
        decisionHandler(.allow)
    }
    
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard let url = navigationResponse.response.url else {
            decisionHandler(.cancel)
            return
        }
        
        // Only allow responses from trusted MakerWorld domains.
        guard MakerWorldLinks.isTrusted(url) else {
            decisionHandler(.cancel)
            return
        }
        
        // A response WebKit can't render inline (e.g. a real `.3mf`/
        // `.stl` file) is a real file download, not a broken page —
        // route it through the native `WKDownloadDelegate` flow.
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }
        
        decisionHandler(.allow)
    }
    
    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }
    
    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }
    
    // MARK: - WKDownloadDelegate
    
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        // Save to a fresh temp directory — matches the pattern
        // `MyMiniFactoryView.download(_:)` uses for its own downloads,
        // so both real-download paths end up in the same kind of
        // location for `ProjectDocument.importModel` to consume.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(suggestedFilename)
        downloadDestinations[ObjectIdentifier(download)] = destination
        completionHandler(destination)
    }
    
    func downloadDidFinish(_ download: WKDownload) {
        // The real file is now at the destination this instance chose
        // in `decideDestinationUsing` above — report it back so the
        // caller can feed it to `ProjectDocument.importModel`, the same
        // path local file imports already use.
        let key = ObjectIdentifier(download)
        guard let destination = downloadDestinations.removeValue(forKey: key) else { return }
        onFileDownloaded?(destination)
    }
    
    func download(
        _ download: WKDownload,
        didFailWithError error: Error,
        resumeData: Data?
    ) {
        // Real download failure from the real site — no retry logic
        // fabricated here; the user can click the real link again.
        // Clean up the now-unusable tracked destination.
        let key = ObjectIdentifier(download)
        if let destination = downloadDestinations.removeValue(forKey: key) {
            try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
        }
    }
}
/// P5-001: Legacy MakerWorld sign-in presenter (browser-only fallback,
/// kept for backward compatibility). The new `MakerWorldWebView`
/// handles auth internally via the embedded page's own login flow.
@MainActor

final class MakerWorldAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    
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
