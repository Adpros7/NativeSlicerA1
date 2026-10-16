import CoreGraphics
import simd

/// Converts a screen-space click (origin top-left, AppKit-flipped Y
/// already accounted for by the caller) into a world-space ray, by
/// unprojecting the near and far clip-space points through the inverse
/// view-projection matrix — the standard perspective-unprojection
/// technique, not a reimplemented approximation.
func screenPointToRay(
    screenPoint: CGPoint, viewSize: CGSize, camera: Camera
) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
    let aspect = Float(viewSize.width / max(viewSize.height, 1))
    let viewProjection = camera.projectionMatrix(aspect: aspect) * camera.viewMatrix
    let inverse = viewProjection.inverse

    // NDC: x,y in [-1,1], y flipped since screenPoint's origin is top-left.
    let ndcX = Float(screenPoint.x / viewSize.width) * 2 - 1
    let ndcY = 1 - Float(screenPoint.y / viewSize.height) * 2

    func unproject(_ ndcZ: Float) -> SIMD3<Float> {
        let clip = SIMD4<Float>(ndcX, ndcY, ndcZ, 1)
        let world = inverse * clip
        return SIMD3(world.x, world.y, world.z) / world.w
    }

    let nearPoint = unproject(0)
    let farPoint = unproject(1)
    return (origin: nearPoint, direction: normalize(farPoint - nearPoint))
}

/// Möller–Trumbore ray-triangle intersection, in whatever space `origin`/
/// `direction` and the mesh's vertices share (caller transforms the ray
/// into the mesh's local space first). Returns the nearest hit point in
/// that same space, or nil if the ray misses every triangle.
func rayMeshIntersection(origin: SIMD3<Float>, direction: SIMD3<Float>, mesh: LoadedMesh) -> SIMD3<Float>? {
    var closestT: Float = .greatestFiniteMagnitude
    var hit: SIMD3<Float>?
    let epsilon: Float = 1e-6

    mesh.vertices.withUnsafeBufferPointer { v in
        mesh.indices.withUnsafeBufferPointer { idx in
            func vertex(_ i: UInt32) -> SIMD3<Float> {
                let o = Int(i) * 3
                return SIMD3(v[o], v[o + 1], v[o + 2])
            }
            var i = 0
            while i + 2 < idx.count {
                let v0 = vertex(idx[i]), v1 = vertex(idx[i + 1]), v2 = vertex(idx[i + 2])
                let edge1 = v1 - v0, edge2 = v2 - v0
                let pvec = cross(direction, edge2)
                let det = dot(edge1, pvec)
                if abs(det) > epsilon {
                    let invDet = 1 / det
                    let tvec = origin - v0
                    let u = dot(tvec, pvec) * invDet
                    if u >= 0, u <= 1 {
                        let qvec = cross(tvec, edge1)
                        let vv = dot(direction, qvec) * invDet
                        if vv >= 0, u + vv <= 1 {
                            let t = dot(edge2, qvec) * invDet
                            if t > epsilon, t < closestT {
                                closestT = t
                                hit = origin + direction * t
                            }
                        }
                    }
                }
                i += 3
            }
        }
    }
    return hit
}
