import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var document = ProjectDocument()
    @State private var showingCalibration = false
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            ObjectListView(document: document)
        } detail: {
            MetalViewport(document: document)
                .frame(minWidth: 480, minHeight: 320)
                .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Import…", action: importModel)
                Button("Open Project…", action: openProject)
                Button("Save Project…", action: saveProject)
                    .disabled(document.objects.isEmpty)
                Button("Delete", action: deleteSelection)
                    .disabled(document.selection == nil)
                Button("Calibration…") { showingCalibration = true }
                Button("Settings…") { showingSettings = true }
                Button(document.isSlicing ? "Slicing…" : "Slice", action: document.slice)
                // G-code view mode picker (P1-012)
                Menu("View Mode") {
                    ForEach(ToolpathViewMode.allCases) { mode in
                        Button(mode.rawValue) { document.toolpathViewMode = mode }
                            .foregroundColor(document.toolpathViewMode == mode ? .accentColor : .primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SlicingSettingsView(document: document)
        }
        .sheet(isPresented: $showingCalibration) {
            CalibrationView(document: document)
        }
        .alert("Error", isPresented: Binding(
            get: { document.lastError != nil },
            set: { if !$0 { document.lastError = nil } }
        )) {
            Button("OK") { document.lastError = nil }
        } message: {
            Text(document.lastError ?? "")
        }
    }

    private func importModel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "stl")!, UTType(filenameExtension: "3mf")!]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { document.importModel(at: url) }
    }

    private func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "3mf")!]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        document.load(from: url)
    }

    private func saveProject() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "3mf")!]
        panel.nameFieldStringValue = "Untitled.3mf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        document.save(to: url)
    }

    private func deleteSelection() {
        guard let selection = document.selection else { return }
        document.removeObject(selection)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { document.importModel(at: url) }
            }
        }
        return true
    }
}

/// Sidebar listing placed objects; selecting one highlights it in the
/// viewport (`MetalRenderer` colors the selected object's mesh).
private struct ObjectListView: View {
    @ObservedObject var document: ProjectDocument

    var body: some View {
        List(document.objects, selection: $document.selection) { object in
            let triangleCount = document.mesh(for: object)?.triangleCount ?? 0
            Text("Object (\(triangleCount) triangles)")
                .tag(object.id)
        }
        .frame(minWidth: 180)
    }
}

#Preview {
    ContentView()
}
