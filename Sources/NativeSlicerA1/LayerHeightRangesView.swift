import SwiftUI

/// P4-014: Z-range list editor for the selected object's variable layer
/// height overrides. Edits `SceneObject.layerHeightRanges`, which
/// `document.slice()` threads straight into the real engine's
/// `ModelObject::layer_config_ranges` (`nsa1_make_connector_mesh`'s
/// sibling bridge field) — no separate preview computation here, the
/// resulting layer heights come from the next real slice.
struct LayerHeightRangesView: View {
    @ObservedObject var document: ProjectDocument
    let objectID: UUID
    @State private var ranges: [LayerHeightRange]

    init(document: ProjectDocument, objectID: UUID) {
        self.document = document
        self.objectID = objectID
        let existing = document.objects.first(where: { $0.id == objectID })?.layerHeightRanges ?? []
        _ranges = State(initialValue: existing)
    }

    var body: some View {
        Form {
            Section("Variable Layer Height") {
                if ranges.isEmpty {
                    Text("No Z-range overrides — uniform layer height throughout.")
                        .foregroundStyle(.secondary)
                }
                ForEach($ranges.indices, id: \.self) { i in
                    HStack {
                        Stepper(value: $ranges[i].zMin, in: 0...500, step: 0.5) {
                            labeledValue("Z min", String(format: "%.1f mm", ranges[i].zMin))
                        }
                        Stepper(value: $ranges[i].zMax, in: 0...500, step: 0.5) {
                            labeledValue("Z max", String(format: "%.1f mm", ranges[i].zMax))
                        }
                        Stepper(value: $ranges[i].layerHeight, in: 0.05...0.3, step: 0.01) {
                            labeledValue("Height", String(format: "%.2f mm", ranges[i].layerHeight))
                        }
                        Button(role: .destructive) {
                            ranges.remove(at: i)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                Button("Add Range") {
                    ranges.append(LayerHeightRange(zMin: 0, zMax: 10, layerHeight: 0.2))
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 280)
        .onChange(of: ranges) { _, newValue in
            document.setLayerHeightRanges(newValue, for: objectID)
        }
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
