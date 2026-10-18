import SwiftUI
import WebKit

/// P5-002/P5-003: real in-app MakerWorld browsing, matching Bambu
/// Studio's own approach exactly — an embedded webview showing the
/// real makerworld.com site (`MakerWorldWebView`), not a hand-off to
/// the system browser. Downloads use WKWebView's native
/// `WKDownloadDelegate` (the same mechanism Safari uses for a real
/// file download link), then feed the result through
/// `ProjectDocument.importModel`, the same path local STL/3MF imports
/// and MyMiniFactory downloads already use.
///
/// Sign-in remains delegated to the system browser
/// (`MakerWorldAuthPresenter`) — MakerWorld's real bind-ticket SSO is
/// still closed-source in both upstreams (RESEARCH-P0-011-
/// CONNECTIVITY.md §3.1), so this embedded webview relies on the
/// site's own session cookies the same way Bambu Studio's embedded
/// webview does, rather than reimplementing anything proprietary.
struct MakerWorldBrowserView: View {
    @ObservedObject var document: ProjectDocument
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var statusMessage: String?
    private let bridge = MakerWorldWebView()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search MakerWorld…", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { bridge.search(keyword: searchQuery) }
                Button("Search") { bridge.search(keyword: searchQuery) }
                    .disabled(searchQuery.isEmpty)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            MakerWorldWebContainer(bridge: bridge)
        }
        .frame(minWidth: 900, minHeight: 650)
        .onAppear {
            bridge.onFileDownloaded = { url in
                Task { @MainActor in
                    document.importModel(at: url)
                    statusMessage = "Imported \(url.lastPathComponent)"
                }
            }
            bridge.navigate(to: MakerWorldLinks.browseURL)
        }
    }
}

/// `NSViewRepresentable` wrapper exposing `MakerWorldWebView`'s
/// underlying `WKWebView` to SwiftUI, following the same pattern
/// `MetalViewport` uses for its own `NSView`-backed content.
private struct MakerWorldWebContainer: NSViewRepresentable {
    let bridge: MakerWorldWebView

    func makeNSView(context: Context) -> NSView {
        bridge.webViewView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // No per-update state to sync — `bridge` owns navigation.
    }
}
