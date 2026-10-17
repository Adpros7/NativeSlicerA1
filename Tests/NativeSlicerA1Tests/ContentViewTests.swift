import XCTest
@testable import NativeSlicerA1

final class ContentViewTests: XCTestCase {
    /// Proves the test target is wired correctly and the real app shell
    /// (sidebar, viewport, Device view, all sheets) type-checks and
    /// constructs without a live window.
    @MainActor
    func testAppTargetIsImportable() {
        _ = ContentView()
    }

    /// Phase 6.5: the three real top-level workflows this app exposes —
    /// adding/removing a case here is a real product decision, not
    /// incidental, so this pins the exact set.
    func testWorkflowCasesArePreparePreviewDevice() {
        XCTAssertEqual(SlicerWorkflow.allCases.map(\.rawValue), ["Prepare", "Preview", "Device"])
    }
}
