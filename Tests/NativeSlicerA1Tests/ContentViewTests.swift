import XCTest
@testable import NativeSlicerA1

final class ContentViewTests: XCTestCase {
    /// Proves the test target is wired correctly (imports the app target,
    /// compiles, and runs under `swift test`). Replace/expand once real
    /// view models and slicing logic exist to test.
    func testAppTargetIsImportable() {
        _ = ContentView()
    }
}
