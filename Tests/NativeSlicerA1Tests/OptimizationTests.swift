import XCTest
@testable import NativeSlicerA1

final class OptimizationTests: XCTestCase {
    private func segment(z: Float, tool: Int32, travel: Bool = false) -> ToolpathSegment {
        ToolpathSegment(
            start: SIMD3(0, 0, z), end: SIMD3(1, 0, z), width: 0.42,
            height: 0.2, isTravel: travel, feedrate: 1_000, temperature: 220,
            layerDuration: 1, extruderID: tool, extrusionRole: travel ? 0 : 1
        )
    }

    func testSameToolExtrusionsHaveNoTransitions() {
        let report = OptimizationReport.analyze(toolpath: [segment(z: 0.2, tool: 0), segment(z: 0.2, tool: 0)])
        XCTAssertEqual(report.totalToolChanges, 0)
        XCTAssertEqual(report.colorTransitions, [])
    }

    func testTravelDoesNotCreateAToolTransition() {
        let report = OptimizationReport.analyze(toolpath: [
            segment(z: 0.2, tool: 0),
            segment(z: 0.2, tool: 1, travel: true),
            segment(z: 0.2, tool: 0),
        ])
        XCTAssertEqual(report.totalToolChanges, 0)
    }

    func testToolChangeCountsOrderedTransition() {
        let report = OptimizationReport.analyze(toolpath: [segment(z: 0.2, tool: 0), segment(z: 0.2, tool: 1)])
        XCTAssertEqual(report.totalToolChanges, 1)
        XCTAssertEqual(report.colorTransitions, [ColorTransition(fromTool: 0, toTool: 1, count: 1)])
    }

    func testLayerSchedulesAreAscendingAndKeepFirstSeenOrder() {
        let report = OptimizationReport.analyze(toolpath: [
            segment(z: 0.4, tool: 1), segment(z: 0.2, tool: 0),
            segment(z: 0.4, tool: 0), segment(z: 0.2, tool: 1),
        ])
        XCTAssertEqual(report.layerSchedules, [
            LayerToolSchedule(z: 0.2, tools: [0, 1]),
            LayerToolSchedule(z: 0.4, tools: [1, 0]),
        ])
    }

    func testPurgeVolumeSumsOnlyUpstreamValues() {
        XCTAssertEqual(OptimizationReport.purgeVolumeMM3([2.5, 0, 7.25]), 9.75)
    }

    func testWithPurgeAndCollisionCarriesOnlySuppliedRealData() {
        let base = OptimizationReport.analyze(toolpath: [segment(z: 0.2, tool: 0)])
        let collision = SlicingEngine.CollisionValidation(isValid: true, exceptionType: 0, isWarning: false, message: nil)
        let withExtras = base.withPurgeAndCollision(purgeVolumeMM3: 3.5, collision: collision)

        XCTAssertEqual(withExtras.purgeVolumeMM3, 3.5)
        XCTAssertEqual(withExtras.collision?.isValid, true)
        XCTAssertNil(withExtras.collision?.message, "a valid collision state must not carry a leftover message")
        XCTAssertEqual(withExtras.colorTransitions, base.colorTransitions, "merging purge/collision must not alter the already-computed color analysis")
    }
}
