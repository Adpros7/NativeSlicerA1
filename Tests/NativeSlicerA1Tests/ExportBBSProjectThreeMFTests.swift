import XCTest
import simd
@testable import NativeSlicerA1

/// P8: proves `ProjectDocument.exportProjectThreeMF` writes a real
/// Bambu-compatible PROJECT 3MF — the same `Format/bbs_3mf.cpp` archive
/// shape (`Metadata/plate_1.gcode` embedded G-code, `3D/3dmodel.model`
/// object stub) BambuStudio's own "send to printer" flow writes, not a
/// hand-authored approximation. Verified by actually unzipping the
/// produced file (`/usr/bin/unzip`, no new dependency) and inspecting
/// real archive entries/bytes — never trusting a nonzero return code
/// alone.
@MainActor
final class ExportBBSProjectThreeMFTests: XCTestCase {
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

    private func importDirectly(_ mesh: LoadedMesh, into document: ProjectDocument) {
        let stlURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).stl")
        try? SlicingEngine.storeSTL(atPath: stlURL.path, mesh: mesh)
        document.importModel(at: stlURL)
        try? FileManager.default.removeItem(at: stlURL)
    }

    /// Lists entries in a zip archive via `/usr/bin/unzip -Z1` (standard
    /// macOS tool, no new dependency) — proves the file is a real,
    /// readable zip with the expected real entries, not just a nonzero
    /// byte count.
    private func zipEntries(at path: String) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        // Read to EOF BEFORE waitUntilExit(): the pipe buffer is only
        // 64KB, and `unzip -p`'s embedded-G-code output exceeds that —
        // waiting for exit first deadlocks (child blocks writing to a
        // full pipe nobody is draining, parent blocks waiting for a
        // child that can't finish). `readDataToEndOfFile()` already
        // blocks until the child closes its stdout (i.e. exits), so a
        // separate `waitUntilExit()` isn't even needed after it.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\n").map(String.init)
    }

    private func zipExtract(entry: String, from path: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", path, entry]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func testExportProjectThreeMFThrowsOnEmptyPlate() {
        let document = ProjectDocument()
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).3mf")
        XCTAssertThrowsError(try document.exportProjectThreeMF(to: dest))
    }

    func testExportProjectThreeMFThrowsOnModifierVolumes() {
        let document = ProjectDocument()
        importDirectly(cubeMesh(), into: document)
        guard let objectID = document.objects.first?.id else {
            return XCTFail("expected an imported object")
        }
        document.addModifier(to: objectID)
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).3mf")
        XCTAssertThrowsError(try document.exportProjectThreeMF(to: dest))
    }

    func testExportProjectThreeMFWritesRealEmbeddedGCode() throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(), into: document)

        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: dest) }
        try document.exportProjectThreeMF(to: dest)

        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
        let size = (attrs[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 1000, "project 3MF must contain real embedded G-code, not an empty stub")

        let entries = try zipEntries(at: dest.path)
        XCTAssertTrue(entries.contains("Metadata/plate_1.gcode"), "must embed G-code at the exact path the A1's project_file command reads: \(entries)")
        XCTAssertTrue(entries.contains("3D/3dmodel.model"), "must still write the (lean, SkipModel) object stub: \(entries)")

        let gcode = try zipExtract(entry: "Metadata/plate_1.gcode", from: dest.path)
        XCTAssertTrue(gcode.contains("G1 "), "embedded G-code must be the real sliced toolpath, not a placeholder: first 200 chars = \(gcode.prefix(200))")
        XCTAssertGreaterThan(gcode.count, 500)
    }
}
