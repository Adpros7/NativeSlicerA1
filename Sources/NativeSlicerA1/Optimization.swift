import Foundation
import simd

/// One ordered, engine-emitted filament/tool transition. Counts are based
/// on adjacent extrusion moves only — travels never create a transition.
struct ColorTransition: Equatable, Hashable {
    let fromTool: Int32
    let toTool: Int32
    let count: Int
}

/// The final tool order that the vendored `ToolOrdering`/G-code processor
/// emitted for one Z layer. This observes upstream's actual schedule; it
/// does not attempt to reschedule regions in Swift.
struct LayerToolSchedule: Equatable {
    let z: Float
    let tools: [Int32]
}

/// P6-002/P6-004/P6-003/P6-005: read-only analysis of real engine
/// output. The A1's default one-tool output correctly reports zero
/// transitions; it never invents multi-color savings, purge volume, or
/// a collision state the engine didn't actually compute.
struct OptimizationReport: Equatable {
    let colorTransitions: [ColorTransition]
    let layerSchedules: [LayerToolSchedule]
    let totalToolChanges: Int
    /// Sum of upstream `flush_per_filament` (P6-003). `nil` until a
    /// caller has actually run `sliceToGCodeWithStatistics` and supplied
    /// it via `withPurgeAndCollision` — never a Swift-estimated guess.
    var purgeVolumeMM3: Double?
    /// Real `Print::validate()` sequential-collision result (P6-005).
    /// `nil` until a caller has actually run
    /// `validateSequentialCollision` and supplied it.
    var collision: SlicingEngine.CollisionValidation?

    static func analyze(toolpath: [ToolpathSegment]) -> OptimizationReport {
        var previousTool: Int32?
        var transitionCounts: [TransitionKey: Int] = [:]
        var toolsByLayer: [Int: [Int32]] = [:]

        for segment in toolpath where !segment.isTravel {
            let tool = segment.extruderID
            if let previousTool, previousTool != tool {
                transitionCounts[TransitionKey(from: previousTool, to: tool), default: 0] += 1
            }
            previousTool = tool

            // G-code Z values are millimetres. Rounding at 1 µm groups
            // numerical representation noise without merging real A1
            // layer heights (which differ by at least 0.05 mm).
            let layerKey = Int((segment.end.z * 1_000).rounded())
            if toolsByLayer[layerKey]?.contains(tool) != true {
                toolsByLayer[layerKey, default: []].append(tool)
            }
        }

        let colorTransitions = transitionCounts
            .map { ColorTransition(fromTool: $0.key.from, toTool: $0.key.to, count: $0.value) }
            .sorted { ($0.fromTool, $0.toTool) < ($1.fromTool, $1.toTool) }
        let layerSchedules = toolsByLayer.keys.sorted().map { key in
            LayerToolSchedule(z: Float(key) / 1_000, tools: toolsByLayer[key]!)
        }
        return OptimizationReport(
            colorTransitions: colorTransitions,
            layerSchedules: layerSchedules,
            totalToolChanges: colorTransitions.reduce(0) { $0 + $1.count }
        )
    }

    /// Attaches purge/collision data from separately-run real engine
    /// calls (`sliceToGCodeWithStatistics`, `validateSequentialCollision`)
    /// without re-deriving the color/layer analysis above.
    func withPurgeAndCollision(purgeVolumeMM3: Double, collision: SlicingEngine.CollisionValidation) -> OptimizationReport {
        var copy = self
        copy.purgeVolumeMM3 = purgeVolumeMM3
        copy.collision = collision
        return copy
    }

    /// P7-006: slicing recommendations derived strictly from this
    /// report's own already-real data — never a generic/fabricated tip.
    /// Empty when nothing actionable was actually observed (e.g. a
    /// clean single-tool slice with no collision checked).
    var recommendations: [String] {
        var items: [String] = []
        if totalToolChanges > 0 {
            items.append("\(totalToolChanges) tool change(s) detected — grouping same-color regions can reduce AMS swaps.")
        }
        if let collision, !collision.isValid {
            items.append("Sequential-print collision detected — re-arrange the plate before printing (\(collision.message ?? "see Print::validate")).")
        }
        if let purgeVolumeMM3, purgeVolumeMM3 > 0 {
            items.append(String(format: "%.1f mm³ of purge volume — fewer filament changes or a higher purge tolerance in Settings would reduce this.", purgeVolumeMM3))
        }
        return items
    }

    /// Sums upstream `flush_per_filament` volumes. Configuration changes
    /// are deliberately not made here: reducing purge is a user/hardware
    /// safety decision, not an automatic Swift-side optimization.
    static func purgeVolumeMM3(_ upstreamFlushVolumes: [Double]) -> Double {
        upstreamFlushVolumes.reduce(0, +)
    }

    private struct TransitionKey: Hashable {
        let from: Int32
        let to: Int32
    }
}
