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

/// P6-002/P6-004: read-only analysis of the real engine toolpath returned
/// by `GCodeProcessorResult`. The A1's default one-tool output correctly
/// reports zero transitions; it never invents multi-color savings.
struct OptimizationReport: Equatable {
    let colorTransitions: [ColorTransition]
    let layerSchedules: [LayerToolSchedule]
    let totalToolChanges: Int

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

    private struct TransitionKey: Hashable {
        let from: Int32
        let to: Int32
    }
}
