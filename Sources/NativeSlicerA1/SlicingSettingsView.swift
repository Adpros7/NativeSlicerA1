import SwiftUI

/// P3-003: printer/nozzle, process, and filament profile pickers plus a
/// handful of common setting overrides (layer height, walls, infill,
/// supports, nozzle/bed temperature), all backed by the same vendored A1
/// profile closure (`BambuProfileLoader`) and config keys (`SlicingJob`)
/// the slicing pipeline itself uses — selections here are exactly what
/// `document.slice()`/`document.save(to:)` apply, not a separate UI-only
/// model. Process/filament pickers are filtered to profiles the chosen
/// machine declares compatible (`compatible_printers`), and switching
/// machines snaps away from any now-incompatible selection — "invalid
/// combinations are rejected safely" without a dead-end picker state.
struct SlicingSettingsView: View {
    @ObservedObject var document: ProjectDocument
    @State private var loader: BambuProfileLoader?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loader {
                Form {
                    Section("Printer") {
                        Picker("Nozzle", selection: machineBinding(loader: loader)) {
                            ForEach(loader.instantiableProfileNames(type: "machine"), id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Section("Material") {
                        Picker("Process", selection: processBinding(loader: loader)) {
                            ForEach(compatibleProcesses(loader: loader), id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Filament", selection: filamentBinding(loader: loader)) {
                            ForEach(compatibleFilaments(loader: loader), id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Section("Overrides") {
                        let values = effectiveValues(loader: loader)
                        Stepper(value: doubleBinding(key: "layer_height", in: values, default: 0.2), in: 0.05...0.3, step: 0.01) {
                            labeledValue("Layer height", String(format: "%.2f mm", doubleBinding(key: "layer_height", in: values, default: 0.2).wrappedValue))
                        }
                        Stepper(value: intBinding(key: "wall_loops", in: values, default: 2), in: 1...8) {
                            labeledValue("Wall loops", "\(intBinding(key: "wall_loops", in: values, default: 2).wrappedValue)")
                        }
                        Slider(value: doubleBinding(key: "sparse_infill_density", in: values, default: 15, isPercent: true), in: 0...100, step: 1) {
                            Text("Infill density")
                        }
                        labeledValue("Infill density", "\(Int(doubleBinding(key: "sparse_infill_density", in: values, default: 15, isPercent: true).wrappedValue))%")
                        Toggle("Enable supports", isOn: boolBinding(key: "enable_support", in: values, default: false))
                        Stepper(value: intBinding(key: "nozzle_temperature", in: values, default: 220), in: 150...300) {
                            labeledValue("Nozzle temperature", "\(intBinding(key: "nozzle_temperature", in: values, default: 220).wrappedValue)°C")
                        }
                        Stepper(value: intBinding(key: "hot_plate_temp", in: values, default: 55), in: 0...120) {
                            labeledValue("Bed temperature", "\(intBinding(key: "hot_plate_temp", in: values, default: 55).wrappedValue)°C")
                        }
                    }
                }
                .formStyle(.grouped)
            } else if let loadError {
                Text(loadError).foregroundStyle(.red).padding()
            } else {
                ProgressView().padding()
            }
        }
        .frame(minWidth: 380, minHeight: 440)
        .task {
            guard loader == nil, loadError == nil else { return }
            do { loader = try BambuProfileLoader() } catch { loadError = "Failed to load profiles: \(error)" }
        }
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(.secondary) }
    }

    private func compatibleProcesses(loader: BambuProfileLoader) -> [String] {
        loader.instantiableProfileNames(type: "process").filter { loader.isCompatible($0, withMachine: document.profileSelection.machine) }
    }

    private func compatibleFilaments(loader: BambuProfileLoader) -> [String] {
        loader.instantiableProfileNames(type: "filament").filter { loader.isCompatible($0, withMachine: document.profileSelection.machine) }
    }

    private func machineBinding(loader: BambuProfileLoader) -> Binding<String> {
        Binding(
            get: { document.profileSelection.machine },
            set: { newMachine in
                document.profileSelection.machine = newMachine
                // Switching machine can orphan the current process/filament
                // pick — snap to the first compatible option rather than
                // leaving a selection that would fail validation at
                // slice/save time (P3-003 "invalid combinations rejected
                // safely"). The vendored A1 closure always has at least one
                // compatible process+filament per machine (verified for
                // all 4 nozzle variants), so the "no compatible option"
                // branch is unreachable with real profile data — it's
                // handled anyway (surfaced immediately via `lastError`
                // rather than silently keeping a now-incompatible
                // selection that would only fail later at slice/save).
                if !loader.isCompatible(document.profileSelection.process, withMachine: newMachine) {
                    if let replacement = compatibleProcesses(loader: loader).first {
                        document.profileSelection.process = replacement
                    } else {
                        document.lastError = "No process profile is compatible with \(newMachine)"
                    }
                }
                if !loader.isCompatible(document.profileSelection.filament, withMachine: newMachine) {
                    if let replacement = compatibleFilaments(loader: loader).first {
                        document.profileSelection.filament = replacement
                    } else {
                        document.lastError = "No filament profile is compatible with \(newMachine)"
                    }
                }
            }
        )
    }

    private func processBinding(loader: BambuProfileLoader) -> Binding<String> {
        Binding(get: { document.profileSelection.process }, set: { document.profileSelection.process = $0 })
    }

    private func filamentBinding(loader: BambuProfileLoader) -> Binding<String> {
        Binding(get: { document.profileSelection.filament }, set: { document.profileSelection.filament = $0 })
    }

    /// The resolved A1 profile's current value for every engine config
    /// key, including `document.profileSelection.overrides` applied on
    /// top — the exact merge `SlicingJob.resolvedConfigEntries` performs
    /// before slicing, so a slider the user hasn't touched still shows the
    /// selected process/filament's real default, not a hardcoded guess.
    private func effectiveValues(loader: BambuProfileLoader) -> [String: String] {
        let entries = (try? SlicingJob.resolvedConfigEntries(loader: loader, selection: document.profileSelection)) ?? []
        return Dictionary(entries, uniquingKeysWith: { _, new in new })
    }

    private func doubleBinding(key: String, in values: [String: String], default def: Double, isPercent: Bool = false) -> Binding<Double> {
        Binding(
            get: {
                guard let raw = values[key] else { return def }
                let trimmed = isPercent ? raw.trimmingCharacters(in: CharacterSet(charactersIn: "%")) : raw
                return Double(trimmed) ?? def
            },
            set: { newValue in
                document.profileSelection.overrides[key] = isPercent ? "\(Int(newValue))%" : String(format: "%.2f", newValue)
            }
        )
    }

    private func intBinding(key: String, in values: [String: String], default def: Int) -> Binding<Int> {
        Binding(
            get: { values[key].flatMap { Int($0) } ?? def },
            set: { document.profileSelection.overrides[key] = "\($0)" }
        )
    }

    private func boolBinding(key: String, in values: [String: String], default def: Bool) -> Binding<Bool> {
        Binding(
            get: { values[key].map { $0 == "1" } ?? def },
            set: { document.profileSelection.overrides[key] = $0 ? "1" : "0" }
        )
    }
}
