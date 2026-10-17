import SwiftUI

/// P6-006: surfaces the real engine-derived `OptimizationReport`
/// (`Optimization.swift`) after a slice — tool transitions and per-layer
/// schedule are available immediately from the already-computed
/// toolpath; purge volume and collision status require an explicit
/// "Check Purge & Collision" action since they run two additional real
/// engine calls (`ProjectDocument.refreshOptimizationDetails`).
struct OptimizationReportView: View {
    @ObservedObject var document: ProjectDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Optimization Report").font(.headline)

            if let report = document.optimizationReport {
                GroupBox("Tool Transitions") {
                    if report.colorTransitions.isEmpty {
                        Text("No tool changes — single-extruder slice.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(report.colorTransitions.enumerated()), id: \.offset) { _, transition in
                            Text("Tool \(transition.fromTool) → Tool \(transition.toTool): \(transition.count)×")
                        }
                        Text("Total tool changes: \(report.totalToolChanges)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                GroupBox("Layer Schedule") {
                    Text("\(report.layerSchedules.count) layer(s) analyzed")
                        .foregroundColor(.secondary)
                }

                GroupBox("Purge Volume") {
                    if let purge = report.purgeVolumeMM3 {
                        Text(String(format: "%.2f mm³ (upstream flush_per_filament)", purge))
                    } else {
                        Text("Not checked yet.").foregroundColor(.secondary)
                    }
                }

                GroupBox("Collision Validation") {
                    if let collision = report.collision {
                        HStack {
                            Image(systemName: collision.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(collision.isValid ? .green : .orange)
                            Text(collision.isValid ? "No collisions (Print::validate)" : (collision.message ?? "Collision detected"))
                        }
                    } else {
                        Text("Not checked yet.").foregroundColor(.secondary)
                    }
                }

                Button(document.isRefreshingOptimizationDetails ? "Checking…" : "Check Purge & Collision") {
                    Task { await document.refreshOptimizationDetails() }
                }
                .disabled(document.isRefreshingOptimizationDetails)
            } else {
                Text("Slice the plate first to see tool-transition, purge, and collision data from the real engine.")
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 360)
    }
}
