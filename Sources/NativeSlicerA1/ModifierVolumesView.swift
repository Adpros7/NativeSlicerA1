import SwiftUI

/// P4-013: modifier mesh editor for the selected object. Edits
/// `SceneObject.modifiers`, which `document.slice()` threads into the
/// real engine's own `ModelVolumeType::PARAMETER_MODIFIER` region
/// derivation — no local infill-region computation happens here, the
/// resulting toolpath comes from the next real slice.
struct ModifierVolumesView: View {
    @ObservedObject var document: ProjectDocument
    let objectID: UUID

    private var modifiers: [ModifierPlacement] {
        document.objects.first(where: { $0.id == objectID })?.modifiers ?? []
    }

    var body: some View {
        Form {
            Section("Modifier Meshes (infill density override)") {
                if modifiers.isEmpty {
                    Text("No modifiers — uniform settings throughout the object.")
                        .foregroundStyle(.secondary)
                }
                ForEach(modifiers) { modifier in
                    HStack {
                        Text(String(format: "(%.0f, %.0f, %.0f)", modifier.center.x, modifier.center.y, modifier.center.z))
                            .foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .leading)
                        Slider(value: radiusBinding(modifier.id), in: 1...30) { Text("Radius") }
                        Text(String(format: "%.0f mm", modifier.radius)).monospacedDigit().frame(width: 50)
                        Slider(value: densityBinding(modifier.id), in: 0...100) { Text("Density") }
                        Text(String(format: "%.0f%%", modifier.infillDensityPercent)).monospacedDigit().frame(width: 45)
                        Button(role: .destructive) {
                            document.selectedModifierID = modifier.id
                            document.removeSelectedModifier(from: objectID)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                Button("Add Modifier") { document.addModifier(to: objectID) }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 260)
    }

    private func radiusBinding(_ id: UUID) -> Binding<Float> {
        Binding(
            get: { modifiers.first(where: { $0.id == id })?.radius ?? 5 },
            set: { newValue in
                document.selectedModifierID = id
                document.updateSelectedModifier(in: objectID) { $0.radius = newValue }
            }
        )
    }

    private func densityBinding(_ id: UUID) -> Binding<Float> {
        Binding(
            get: { modifiers.first(where: { $0.id == id })?.infillDensityPercent ?? 100 },
            set: { newValue in
                document.selectedModifierID = id
                document.updateSelectedModifier(in: objectID) { $0.infillDensityPercent = newValue }
            }
        )
    }
}
