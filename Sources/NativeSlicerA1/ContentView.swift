import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var document = ProjectDocument()
    @State private var showingCalibration = false
    @State private var showingSettings = false
    @State private var showingLayerHeights = false

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
                Button("Layer Heights…") { showingLayerHeights = true }
                    .disabled(document.selection == nil)
                Button(document.isSlicing ? "Slicing…" : "Slice", action: document.slice)
                // G-code view mode picker (P1-012)
                Menu("View Mode") {
                    ForEach(ToolpathViewMode.allCases) { mode in
                        Button(mode.rawValue) { document.toolpathViewMode = mode }
                            .foregroundColor(document.toolpathViewMode == mode ? .accentColor : .primary)
                    }
                }
                // P3-005 support-paint controls: toggle paint mode,
                // brush type, brush radius. Click/drag in the viewport
                // while active paints the real engine's TriangleSelector
                // (via ProjectDocument.paintAt), picked up by the next
                // Slice.
                Toggle("Paint Support", isOn: $document.paintMode)
                    .disabled(document.selection == nil)
                if document.paintMode {
                    Picker("Brush", selection: $document.paintType) {
                        Text("Enforcer").tag(SupportPaintType.enforcer)
                        Text("Blocker").tag(SupportPaintType.blocker)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    Slider(value: $document.paintBrushRadius, in: 1...20) {
                        Text("Radius")
                    }
                    .frame(width: 120)
                    Text("\(document.paintBrushRadius, specifier: "%.1f")mm")
                        .monospacedDigit()
                    Button("Undo Paint") {
                        if let selection = document.selection { document.undoPaint(for: selection) }
                    }
                    .disabled(document.selection.map(document.canUndoPaint(for:)) != true)
                    Button("Redo Paint") {
                        if let selection = document.selection { document.redoPaint(for: selection) }
                    }
                    .disabled(document.selection.map(document.canRedoPaint(for:)) != true)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SlicingSettingsView(document: document)
        }
        .sheet(isPresented: $showingLayerHeights) {
            if let selection = document.selection {
                LayerHeightRangesView(document: document, objectID: selection)
            }
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
