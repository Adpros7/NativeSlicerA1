import Foundation
import simd

/// P4-013: a local per-volume config override region, persisted on its
/// parent `SceneObject`. Scoped to the single most common real modifier
/// use case (infill density override within a sub-region) rather than a
/// fully generic config-key editor — the real engine mechanism
/// (`ModelVolumeType::PARAMETER_MODIFIER`) supports any config key;
/// `configEntries` is the seam to extend this later without touching the
/// slicing pipeline.
struct ModifierPlacement: Identifiable, Equatable {
    let id: UUID
    /// Object-local center (mm), matching `ModifierVolume.transform`'s
    /// "relative to the parent object's own coordinate space" convention.
    var center: SIMD3<Float>
    var radius: Float
    var infillDensityPercent: Float

    init(id: UUID = UUID(), center: SIMD3<Float>, radius: Float = 5, infillDensityPercent: Float = 100) {
        self.id = id
        self.center = center
        self.radius = radius
        self.infillDensityPercent = infillDensityPercent
    }

    var configEntries: [(key: String, value: String)] {
        [("sparse_infill_density", "\(max(0, min(100, Int(infillDensityPercent))))%")]
    }

    /// A real, if simple, closed UV-sphere mesh — any valid watertight
    /// mesh works as a modifier volume for the real engine's region
    /// derivation; no engine-side primitive generator is needed for this.
    var mesh: LoadedMesh {
        Self.sphereMesh(radius: radius)
    }

    static func sphereMesh(radius: Float, stacks: Int = 10, slices: Int = 16) -> LoadedMesh {
        var vertices: [Float] = []
        var indices: [UInt32] = []
        for stack in 0...stacks {
            let phi = Float.pi * Float(stack) / Float(stacks) // 0...pi
            let y = cos(phi) * radius
            let ringRadius = sin(phi) * radius
            for slice in 0...slices {
                let theta = 2 * Float.pi * Float(slice) / Float(slices)
                vertices.append(contentsOf: [ringRadius * cos(theta), y, ringRadius * sin(theta)])
            }
        }
        let ringSize = slices + 1
        for stack in 0..<stacks {
            for slice in 0..<slices {
                let a = UInt32(stack * ringSize + slice)
                let b = UInt32(stack * ringSize + slice + 1)
                let c = UInt32((stack + 1) * ringSize + slice)
                let d = UInt32((stack + 1) * ringSize + slice + 1)
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        return LoadedMesh(vertices: vertices, indices: indices)
    }
}
