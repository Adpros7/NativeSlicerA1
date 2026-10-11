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

    func testFeatureTypePerimeterIsOrange() {
        let seg = makeSegment(extrusionRole: 0)
        let color = seg.color(for: .featureType)
        // Perimeter (role 0) should be orange
        XCTAssertGreaterThan(color.x, 0.9)
        XCTAssertGreaterThan(color.y, 0.5)
        XCTAssertLessThan(color.z, 0.2)
    }

    func testFeatureTypeInfillIsGreen() {
        let seg = makeSegment(extrusionRole: 3)
        let color = seg.color(for: .featureType)
        // Infill (role 3) should be green
        XCTAssertGreaterThan(color.y, 0.6)
        XCTAssertLessThan(color.x, 0.5)
    }

    func testFeatureTypeSupportIsBlue() {
        let seg = makeSegment(extrusionRole: 4)
        let color = seg.color(for: .featureType)
        // Support (role 4) should be blue
        XCTAssertGreaterThan(color.z, 0.8)
        XCTAssertLessThan(color.x, 0.4)
    }

    func testFeatureTypeSkirtIsGray() {
        let seg = makeSegment(extrusionRole: 7)  // skirt role
        let color = seg.color(for: .featureType)
        // Skirt/brim (roles 7, 8) should be gray
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
