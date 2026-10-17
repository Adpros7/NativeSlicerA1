import SwiftUI

/// P5-003/P5-005: real in-app model search/browse/download against the
/// documented MyMiniFactory API — results render in this app's own list,
/// not a hand-off to the system browser (contrast `MakerWorldLinks`,
/// which has no public API to call). Files download straight through
/// `ProjectDocument.importModel`, the same path local STL/3MF imports
/// use.
struct MyMiniFactoryView: View {
    @ObservedObject var document: ProjectDocument
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyField = MyMiniFactoryAccount.apiKey ?? ""
    @State private var clientIDField = MyMiniFactoryAccount.clientID ?? ""
    @State private var clientSecretField = ""
    @State private var query = ""
    @State private var results: [MMFObjectSummary] = []
    @State private var selectedObject: MMFObjectSummary?
    @State private var files: [MMFFile] = []
    @State private var statusMessage: String?
    @State private var isBusy = false
    @State private var authPresenter = MyMiniFactoryAuthPresenter()

    private var client: MyMiniFactoryClient {
        MyMiniFactoryClient(apiKey: MyMiniFactoryAccount.apiKey, accessToken: MyMiniFactoryAccount.accessToken)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MyMiniFactory").font(.headline)

            GroupBox("Account") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SecureField("API key (search only)", text: $apiKeyField)
                        Button("Save") { MyMiniFactoryAccount.apiKey = apiKeyField.isEmpty ? nil : apiKeyField }
                    }
                    HStack {
                        TextField("OAuth client ID", text: $clientIDField)
                        SecureField("OAuth client secret", text: $clientSecretField)
                    }
                    HStack {
                        Button(MyMiniFactoryAccount.isSignedIn ? "Signed in ✓ — Re-sign in" : "Sign In (enables download)") {
                            Task { await signIn() }
                        }
                        .disabled(clientIDField.isEmpty || clientSecretField.isEmpty)
                        if MyMiniFactoryAccount.isSignedIn {
                            Button("Sign Out") { MyMiniFactoryAccount.signOut() }
                        }
                    }
                    Text("Downloading real file bytes requires OAuth sign-in — the API spec restricts download_url to OAuth-connected users. Register your own app at myminifactory.com (account settings) with redirect URI \(MyMiniFactory.redirectURI).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                TextField("Search models…", text: $query)
                    .onSubmit { Task { await search() } }
                Button("Search") { Task { await search() } }
                    .disabled(query.isEmpty || isBusy)
            }

            if let statusMessage {
                Text(statusMessage).font(.caption).foregroundColor(.secondary)
            }

            HSplitView {
                List(results) { item in
                    Text(item.name ?? "Untitled")
                        .fontWeight(selectedObject?.id == item.id ? .bold : .regular)
                        .onTapGesture { Task { await loadFiles(for: item) } }
                }
                .frame(minWidth: 220)

                List(files) { file in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(file.filename ?? "file").font(.body)
                            if let size = file.size { Text("\(size) bytes").font(.caption).foregroundColor(.secondary) }
                        }
                        Spacer()
                        Button("Import") { Task { await download(file) } }
                            .disabled(isBusy)
                    }
                }
                .frame(minWidth: 260)
            }
            .frame(minHeight: 280)

            HStack {
                Spacer()
                Button("Close") { dismiss() }
            }
        }
        .padding()
        .frame(minWidth: 620, minHeight: 460)
    }

    private func signIn() async {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        do {
            try await authPresenter.signIn(clientID: clientIDField, clientSecret: clientSecretField, anchor: window)
            statusMessage = "Signed in to MyMiniFactory."
        } catch {
            statusMessage = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    private func search() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let response = try await client.search(query: query)
            results = response.items
            statusMessage = "\(response.totalCount) result(s)."
        } catch {
            statusMessage = "Search failed: \(error.localizedDescription)"
            results = []
        }
    }

    private func loadFiles(for object: MMFObjectSummary) async {
        selectedObject = object
        isBusy = true
        defer { isBusy = false }
        do {
            let response = try await client.objectFiles(objectID: object.id)
            files = response.items
        } catch {
            statusMessage = "Failed to list files: \(error.localizedDescription)"
            files = []
        }
    }

    private func download(_ file: MMFFile) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let ext = (file.filename as NSString?)?.pathExtension.lowercased() ?? ""
            guard ["stl", "3mf"].contains(ext) else {
                statusMessage = "Unsupported file type .\(ext) — only .stl/.3mf can be imported."
                return
            }
            let data = try await client.downloadFile(file)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try data.write(to: tempURL)
            document.importModel(at: tempURL)
            statusMessage = "Imported \(file.filename ?? "model") into the scene."
        } catch {
            statusMessage = "Download failed: \(error.localizedDescription)"
        }
    }
}
