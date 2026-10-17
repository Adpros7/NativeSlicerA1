import SwiftUI

/// Phase 6.5 usability milestone: the sidebar's real printer/filament/
/// process summary (read directly from `document.profileSelection`,
/// the same values `SlicingSettingsView`/`document.slice()` use — no
/// separate UI-only copy) plus the placed-object list with a real empty
/// state instead of a blank panel.
struct SidebarView: View {
    @ObservedObject var document: ProjectDocument
    let onOpenSettings: () -> Void
    let onImport: () -> Void

    var body: some View {
        List(selection: $document.selection) {
            Section("Printer") {
                LabeledContent("Machine", value: document.profileSelection.machine)
                LabeledContent("Process", value: document.profileSelection.process)
                LabeledContent("Filament", value: document.profileSelection.filament)
                Button("Settings…", action: onOpenSettings)
            }

            Section("Objects (\(document.objectsOnActivePlate.count))") {
                if document.objects.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No objects on the plate.")
                            .foregroundColor(.secondary)
                        Button("Import Model…", action: onImport)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(document.objects) { object in
                        let triangleCount = document.mesh(for: object)?.triangleCount ?? 0
                        Text("Object (\(triangleCount) triangles)")
                            .tag(object.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
    }
}
