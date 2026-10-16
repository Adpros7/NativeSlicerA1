import XCTest
import simd
@testable import NativeSlicerA1

/// P4-007: cut lineage must survive a 3MF save/reload, reusing the real
/// upstream `ModelObject::cut_id`/`Metadata/cut_information.xml`
/// round trip (`bbs_3mf.cpp`'s `_add_cut_information_file_to_archive`/
/// importer) rather than inventing a parallel persisted-attribute format.
final class CutGroupIDPersistenceTests: XCTestCase {
    private func cubeMesh(size: Float = 20) -> LoadedMesh {
        let x = size, y = size, z = size
        let v: [Float] = [
            x, y, 0, x, 0, 0, 0, 0, 0, 0, y, 0,
            x, y, z, 0, y, z, 0, 0, z, x, 0, z,
        ]
        let i: [UInt32] = [
            0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7,
            0, 4, 7, 0, 7, 1, 1, 7, 6, 1, 6, 2,
            2, 6, 5, 2, 5, 3, 4, 0, 3, 4, 3, 5,
        ]
        return LoadedMesh(vertices: v, indices: i)
    }

    func testCutGroupIDRoundTripsThroughThreeMF() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = directory.appendingPathComponent("cut-pair.3mf")

        try SlicingEngine.storeThreeMF(
            atPath: project.path,
            objects: [
                (mesh: cubeMesh(), transform: matrix_identity_float4x4),
                (mesh: cubeMesh(size: 10), transform: matrix_identity_float4x4),
            ],
            configEntries: [],
            cutGroupIDs: [42, 42]
        )

        XCTAssertEqual(SlicingEngine.loadThreeMFCutGroupID(atPath: project.path, objectIndex: 0), 42)
        XCTAssertEqual(SlicingEngine.loadThreeMFCutGroupID(atPath: project.path, objectIndex: 1), 42)
    }

    func testObjectsWithNoCutGroupIDLoadAsNil() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = directory.appendingPathComponent("uncut.3mf")

        try SlicingEngine.storeThreeMF(
            atPath: project.path,
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            configEntries: []
        )

        XCTAssertNil(SlicingEngine.loadThreeMFCutGroupID(atPath: project.path, objectIndex: 0))
    }
}
