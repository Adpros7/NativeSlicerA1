// Tests/NativeSlicerA1Tests/ToolpathViewModeTests.swift
// P1-012: G-code toolpath view-mode coloring unit tests.

import XCTest
@testable import NativeSlicerA1

final class ToolpathViewModeTests: XCTestCase {

    /// Helper: create a ToolpathSegment with known values for testing.
    private func makeSegment(
        start: (Float, Float, Float) = (0, 0, 0),
        end: (Float, Float, Float) = (1, 1, 1),
        width: Float = 0.4,
        height: Float = 0.32,
        isTravel: Bool = false,
        feedrate: Float = 2000,
        temperature: Float = 210,
        layerDuration: Float = 1.5,
        extruderID: Int32 = 0,
        extrusionRole: Float = 0
    ) -> ToolpathSegment {
        ToolpathSegment(
            start: SIMD3(start.0, start.1, start.2),
            end: SIMD3(end.0, end.1, end.2),
            width: width,
            height: height,
            isTravel: isTravel,
            feedrate: feedrate,
            temperature: temperature,
            layerDuration: layerDuration,
            extruderID: extruderID,
            extrusionRole: extrusionRole
        )
    }

    // MARK: - FeatureType mode

    func testFeatureTypeExternalPerimeterMatchesUpstreamColor() {
        let seg = makeSegment(extrusionRole: 2) // erExternalPerimeter
        let color = seg.color(for: .featureType)
        XCTAssertEqual(color.x, 1.00, accuracy: 0.01)
        XCTAssertEqual(color.y, 0.49, accuracy: 0.01)
        XCTAssertEqual(color.z, 0.22, accuracy: 0.01)
    }

    func testFeatureTypeInternalInfillMatchesUpstreamColor() {
        let seg = makeSegment(extrusionRole: 4) // erInternalInfill
        let color = seg.color(for: .featureType)
        XCTAssertEqual(color.x, 0.69, accuracy: 0.01)
        XCTAssertEqual(color.y, 0.19, accuracy: 0.01)
        XCTAssertEqual(color.z, 0.16, accuracy: 0.01)
    }

    func testFeatureTypeSupportMaterialMatchesUpstreamColor() {
        let seg = makeSegment(extrusionRole: 14) // erSupportMaterial
        let color = seg.color(for: .featureType)
        XCTAssertEqual(color.x, 0.0, accuracy: 0.01)
        XCTAssertEqual(color.y, 1.0, accuracy: 0.01)
        XCTAssertEqual(color.z, 0.0, accuracy: 0.01)
    }

    func testFeatureTypeSkirtMatchesUpstreamColor() {
        let seg = makeSegment(extrusionRole: 12) // erSkirt
        let color = seg.color(for: .featureType)
        XCTAssertEqual(color.x, 0.0, accuracy: 0.01)
        XCTAssertEqual(color.y, 0.53, accuracy: 0.01)
        XCTAssertEqual(color.z, 0.43, accuracy: 0.01)
    }

    func testFeatureTypeOutOfRangeRoleFallsBackToGray() {
        let seg = makeSegment(extrusionRole: 99)
        let color = seg.color(for: .featureType)
        XCTAssertEqual(color.x, 0.6, accuracy: 0.01)
        XCTAssertEqual(color.y, 0.6, accuracy: 0.01)
        XCTAssertEqual(color.z, 0.6, accuracy: 0.01)
    }

    // MARK: - Height mode (viridis colormap)

    func testHeightMinIsPurple() {
        let seg = makeSegment(height: 0.05)
        let color = seg.color(for: .height)
        // Low height → purple (low R, low G, higher B)
        XCTAssertLessThan(color.x, 0.3)
        XCTAssertLessThan(color.y, 0.1)
        XCTAssertGreaterThan(color.z, 0.3)
    }

    func testHeightMaxIsYellow() {
        let seg = makeSegment(height: 1.0)
        let color = seg.color(for: .height)
        // High height → yellow (high R, high G, low B)
        XCTAssertGreaterThan(color.x, 0.7)
        XCTAssertGreaterThan(color.y, 0.8)
        XCTAssertLessThan(color.z, 0.4)
    }

    // MARK: - Feedrate mode

    func testFeedrateSlowIsPurple() {
        let seg = makeSegment(feedrate: 50)
        let color = seg.color(for: .feedrate)
        XCTAssertLessThan(color.x, 0.3)
    }

    func testFeedrateFastIsYellow() {
        let seg = makeSegment(feedrate: 5000)
        let color = seg.color(for: .feedrate)
        XCTAssertGreaterThan(color.y, 0.8)
    }

    // MARK: - Temperature mode

    func testTemperatureCoolIsPurple() {
        let seg = makeSegment(temperature: 180)
        let color = seg.color(for: .temperature)
        XCTAssertLessThan(color.z, 0.4)
    }

    func testTemperatureHotIsYellow() {
        let seg = makeSegment(temperature: 260)
        let color = seg.color(for: .temperature)
        XCTAssertGreaterThan(color.x, 0.7)
    }

    // MARK: - LayerTime mode (logarithmic)

    func testLayerTimeFastIsPurple() {
        let seg = makeSegment(layerDuration: 0.1)
        let color = seg.color(for: .layerTime)
        XCTAssertLessThan(color.x, 0.3)
    }

    func testLayerTimeSlowIsYellow() {
        let seg = makeSegment(layerDuration: 30)
        let color = seg.color(for: .layerTime)
        XCTAssertGreaterThan(color.y, 0.8)
    }

    // MARK: - Tool mode

    func testToolModeCyclesColors() {
        let seg0 = makeSegment(extruderID: 0)
        let seg1 = makeSegment(extruderID: 1)
        let seg2 = makeSegment(extruderID: 2)
        let seg3 = makeSegment(extruderID: 3)
        let seg4 = makeSegment(extruderID: 4)
        let seg5 = makeSegment(extruderID: 5)
        let seg6 = makeSegment(extruderID: 6) // wraps to 0

        let colors = [
            seg0.color(for: .tool),
            seg1.color(for: .tool),
            seg2.color(for: .tool),
            seg3.color(for: .tool),
            seg4.color(for: .tool),
            seg5.color(for: .tool),
            seg6.color(for: .tool),
        ]

        // Each tool should get a distinct color
        for i in 0..<6 {
            for j in (i+1)..<6 {
                XCTAssertFalse(
                    colors[i].x == colors[j].x && colors[i].y == colors[j].y && colors[i].z == colors[j].z,
                    "Tools \(i) and \(j) should have different colors"
                )
            }
        }
        // Tool 6 wraps to tool 0's color
        XCTAssertEqual(colors[0].x, colors[6].x, accuracy: 0.01)
        XCTAssertEqual(colors[0].y, colors[6].y, accuracy: 0.01)
        XCTAssertEqual(colors[0].z, colors[6].z, accuracy: 0.01)
    }

    // MARK: - Travel segments use fallback coloring

    func testTravelSegmentsUseGrayInNonFeatureModes() {
        // Travel segments still get the same viridis coloring for non-feature modes
        let travelSeg = makeSegment(isTravel: true, feedrate: 4000)
        let color = travelSeg.color(for: .feedrate)
        // Fast travel → yellow-ish
        XCTAssertGreaterThan(color.x, 0.6)
    }

    // MARK: - ViewMode enum

    func testAllViewModesAreIdentifiable() {
        let modes = ToolpathViewMode.allCases
        XCTAssertEqual(modes.count, 6)
        // All IDs should be unique
        let ids = modes.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testFeatureTypeIsFirstCase() {
        XCTAssertEqual(ToolpathViewMode.allCases.first, .featureType)
    }
}
