import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var document = ProjectDocument()
    @State private var showingCalibration = false
    @State private var showingSettings = false
    @State private var showingLayerHeights = false
    @State private var showingModifiers = false
    @State private var showingPlatePreview = false
    @State private var showingMyMiniFactory = false
    @State private var makerWorldAuth = MakerWorldAuthPresenter()

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
                Button("Modifiers…") { showingModifiers = true }
                    .disabled(document.selection == nil)
                Button("Plates (\(document.plates.count))…") { showingPlatePreview = true }
                Button(document.isSlicing ? "Slicing…" : "Slice", action: document.slice)
                Menu("View Mode") {
                    ForEach(ToolpathViewMode.allCases) { mode in
                        Button(mode.rawValue) { document.toolpathViewMode = mode }
                            .foregroundColor(document.toolpathViewMode == mode ? .accentColor : .primary)
                    }
                }
                // P5-001/P5-002: MakerWorld integration, delegated
                // entirely to the system browser — see
                // MakerWorldLinks.swift's doc comment for why (the real
                // bind-ticket SSO mechanism is closed-source in both
                // upstreams). This app never embeds a webview or talks
                // to any MakerWorld API; it only ever opens the real
                // makerworld.com domain, gated by a real trust check.
                Menu("MakerWorld") {
                    Button("Sign In…") {
                        if let window = NSApp.keyWindow ?? NSApp.windows.first {
                            makerWorldAuth.presentSignIn(anchor: window)
                        }
                    }
                    Button("Browse Models…") {
                        MakerWorldLinks.openInSystemBrowser(MakerWorldLinks.browseURL)
                    }
                }
                // P5-003/P5-005: MyMiniFactory is a real in-app
                // integration (documented public API, not browser
                // delegation) — see MyMiniFactoryClient.swift's doc
                // comment.
                Button("MyMiniFactory…") { showingMyMiniFactory = true }
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
                // P4-006 interactive cut-plane gizmo: toggle plane mode
                // (click/drag in the viewport places the plane at the
                // clicked surface point, same raycast as paint mode),
                // fine-tune height/tilt with sliders, pick which side(s)
                // to keep, and perform the real engine cut.
                // The live wireframe preview is rendered by
                // MetalRenderer.setCutPlane (cyan quad + normal line).
                Toggle("Cut Plane", isOn: $document.cutPlaneMode)
                    .disabled(document.selection == nil)
                if document.cutPlaneMode, let plane = document.cutPlane,
                   let selection = document.selection,
                   let object = document.objects.first(where: { $0.id == selection }),
                   let box = document.worldBoundingBox(for: object) {
                    let zRange = (box.min.z - plane.halfExtent)...(box.max.z + plane.halfExtent)
                    Slider(value: cutPlaneHeightBinding, in: zRange) { Text("Height") }
                        .frame(width: 100)
                    Text("Z \(plane.center.z, specifier: "%.1f")")
                        .monospacedDigit()
                    Slider(value: cutPlaneTiltXBinding, in: -(.pi / 4)...(.pi / 4)) { Text("Tilt X") }
                        .frame(width: 80)
                    Slider(value: cutPlaneTiltYBinding, in: -(.pi / 4)...(.pi / 4)) { Text("Tilt Y") }
                        .frame(width: 80)
                    Toggle("Place Connector", isOn: $document.connectorPlacementMode)
                    if !document.cutConnectors.isEmpty {
                        Picker("Connector", selection: $document.selectedCutConnectorID) {
                            ForEach(Array(document.cutConnectors.enumerated()), id: \.element.id) { index, connector in
                                Text("Connector \(index + 1)").tag(Optional(connector.id))
                            }
                        }
                        .frame(width: 125)
                        Picker("Type", selection: connectorTypeBinding) {
                            ForEach(ConnectorType.allCases, id: \.self) { type in
                                Text(String(describing: type).capitalized).tag(type)
                            }
                        }
                        .frame(width: 105)
                        Slider(value: connectorRadiusBinding, in: 1...15) { Text("Radius") }
                            .frame(width: 80)
                        Slider(value: connectorHeightBinding, in: 2...30) { Text("Depth") }
                            .frame(width: 80)
                        Button("Delete Connector", role: .destructive, action: document.removeSelectedConnector)
                            .disabled(document.selectedCutConnectorID == nil)
                    }
                    Picker("Keep", selection: $document.cutKeepMode) {
                        Text("Both").tag(CutMode.both)
                        Text("Lower").tag(CutMode.lowerOnly)
                        Text("Upper").tag(CutMode.upperOnly)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    Button("Cut", action: document.performCut)
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
        .sheet(isPresented: $showingModifiers) {
            if let selection = document.selection {
                ModifierVolumesView(document: document, objectID: selection)
            }
        }
        .sheet(isPresented: $showingCalibration) {
            CalibrationView(document: document)
        }
        .sheet(isPresented: $showingPlatePreview) {
            PlatePreviewView(document: document)
        }
        .sheet(isPresented: $showingMyMiniFactory) {
            MyMiniFactoryView(document: document)
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

    private var cutPlaneHeightBinding: Binding<Float> {
        Binding(
            get: { document.cutPlane?.center.z ?? 0 },
            set: { newZ in document.cutPlane?.center.z = newZ }
        )
    }

    private var cutPlaneTiltXBinding: Binding<Float> {
        Binding(
            get: { document.cutPlane?.tiltX ?? 0 },
            set: { document.setCutPlaneTilt(x: $0) }
        )
    }

    private var cutPlaneTiltYBinding: Binding<Float> {
        Binding(
            get: { document.cutPlane?.tiltY ?? 0 },
            set: { document.setCutPlaneTilt(y: $0) }
        )
    }

    private var connectorTypeBinding: Binding<ConnectorType> {
        Binding(
            get: { selectedConnector?.preset.type ?? .plug },
            set: { type in document.updateSelectedConnector { $0.preset.type = type } }
        )
    }

    private var connectorRadiusBinding: Binding<Float> {
        Binding(
            get: { selectedConnector?.preset.radius ?? 5 },
            set: { radius in document.updateSelectedConnector { $0.preset.radius = radius } }
        )
    }

    private var connectorHeightBinding: Binding<Float> {
        Binding(
            get: { selectedConnector?.preset.height ?? 10 },
            set: { height in document.updateSelectedConnector { $0.preset.height = height } }
        )
    }

    private var selectedConnector: CutConnectorPlacement? {
        guard let id = document.selectedCutConnectorID else { return nil }
        return document.cutConnectors.first(where: { $0.id == id })
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
