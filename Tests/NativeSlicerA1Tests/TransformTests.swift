import XCTest
import simd
@testable import NativeSlicerA1

final class TransformTests: XCTestCase {
    func testIdentityMatrixLeavesPointUnchanged() {
        let p = SIMD4<Float>(1, 2, 3, 1)
        let result = Transform.identity.matrix * p
        XCTAssertEqual(result, p)
    }

    func testTranslationThenScaleAppliesScaleFirst() {
        // Transform composes as translate(rotate(scale(p))): scaling a unit
        // point by 2 then translating by (1,0,0) should land at (3,0,0),
        // not (4,0,0) — proves composition order, not just that it compiles.
        let t = Transform.identity.scaled(by: SIMD3(2, 2, 2)).translated(by: SIMD3(1, 0, 0))
        let p = SIMD4<Float>(1, 0, 0, 1)
        let result = t.matrix * p
        assertApproximatelyEqual(result, SIMD4<Float>(3, 0, 0, 1))
    }

    func testRotation90DegreesAroundZ() {
        let quat = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        let t = Transform.identity.rotated(by: quat)
        let result = t.matrix * SIMD4<Float>(1, 0, 0, 1)
        assertApproximatelyEqual(result, SIMD4<Float>(0, 1, 0, 1))
    }

    func testMatrixInitDecomposesTRSRoundTrip() {
        let original = Transform.identity
            .scaled(by: SIMD3(2, 3, 4))
            .rotated(by: simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1)))
            .translated(by: SIMD3(5, -1, 2))
        let decomposed = Transform(matrix: original.matrix)

        assertApproximatelyEqual(
            SIMD4(decomposed.translation, 1),
            SIMD4(original.translation, 1)
        )
        assertApproximatelyEqual(
            SIMD4(decomposed.scale, 1),
            SIMD4(original.scale, 1)
        )
        // Same resulting matrix on a test point is the real contract (the
        // quaternion itself may differ by sign, which represents the same
        // rotation).
        let p = SIMD4<Float>(1, 0.5, -0.5, 1)
        assertApproximatelyEqual(decomposed.matrix * p, original.matrix * p)
    }

    func testMatrixInitRetainsMirroredScale() {
        let original = Transform.identity.scaled(by: SIMD3(-1, 2, 3))
        let decomposed = Transform(matrix: original.matrix)
        let p = SIMD4<Float>(1, 0.5, -0.5, 1)

        assertApproximatelyEqual(decomposed.matrix * p, original.matrix * p)
    }
}

final class UndoStackTests: XCTestCase {
    func testUndoRedoRoundTrip() {
        var stack = UndoStack(initial: 0)
        stack.push(1)
        stack.push(2)
        XCTAssertEqual(stack.current, 2)
        XCTAssertEqual(stack.undo(), 1)
        XCTAssertEqual(stack.undo(), 0)
        XCTAssertFalse(stack.canUndo)
        XCTAssertEqual(stack.redo(), 1)
        XCTAssertEqual(stack.redo(), 2)
        XCTAssertFalse(stack.canRedo)
    }

    func testPushAfterUndoDiscardsRedoHistory() {
        var stack = UndoStack(initial: 0)
        stack.push(1)
        stack.push(2)
        stack.undo() // back to 1
        stack.push(99)
        XCTAssertEqual(stack.current, 99)
        XCTAssertFalse(stack.canRedo, "redo history (2) must be discarded after a new push")
    }
}

final class SceneObjectTests: XCTestCase {
    func testApplyUndoRedo() {
        var object = SceneObject(sourceMeshID: UUID(), plateID: 1)
        XCTAssertEqual(object.transform, .identity)

        let moved = Transform.identity.translated(by: SIMD3(5, 0, 0))
        object.apply(moved)
        XCTAssertEqual(object.transform, moved)

        object.undo()
        XCTAssertEqual(object.transform, .identity)

        object.redo()
        XCTAssertEqual(object.transform, moved)
    }
}

private extension XCTestCase {
    func assertApproximatelyEqual(_ a: SIMD4<Float>, _ b: SIMD4<Float>, accuracy: Float = 0.0001, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.w, b.w, accuracy: accuracy, file: file, line: line)
    }
}
