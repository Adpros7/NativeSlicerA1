import SwiftUI

/// P3-003/Calibration: native SwiftUI flow-rate calibration sheet for
/// pass 1 only (0.80→1.20, 0.05 step). Displays the fixed range and
/// selected printer/filament; generate invokes the real engine off the
/// main actor and updates the document's toolpath and lastError.
struct CalibrationView: View {
    @ObservedObject var document: ProjectDocument
    @State private var loader: BambuProfileLoader?
    @State private var loadError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if loader != nil {
                Form {
                    Section("Flow Rate Calibration — Pass 1") {
                        Text("Prints 9 models from flow ratio 0.80 to 1.20 in 0.05 increments.")
                            .font(.subheadline)
                        Text("Range: 0.80 → 1.20 (step 0.05) • 9 values")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section("Selected Profile") {
                        labeledValue("Printer", document.profileSelection.machine)
                        labeledValue("Process", document.profileSelection.process)
                        labeledValue("Filament", document.profileSelection.filament)
                    }
                    Section {
                        Button("Generate Calibration G-code") {
                            Task { await document.calibrate() }
                        }
                        .disabled(document.isSlicing)
                    } footer: {
                        if document.isSlicing {
                            ProgressView("Generating…").padding(.top, 4)
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
        .frame(minWidth: 380, minHeight: 300)
        .task {
            guard loader == nil, loadError == nil else { return }
            do { loader = try BambuProfileLoader() } catch { loadError = "Failed to load profiles: \(error)" }
        }
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(.secondary) }
    }
}

#Preview {
    let doc = ProjectDocument()
    doc.importModel(at: URL(fileURLWithPath: "/dev/null"))
    return CalibrationView(document: doc)
}
