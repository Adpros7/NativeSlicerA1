import simd

/// Orbit camera around a fixed target: mouse-drag orbits, scroll wheel
/// zooms. ~30 lines of arcball-adjacent math, not worth a dependency (see
/// ARCHITECTURE.md P0-006).
struct Camera {
    var target = SIMD3<Float>(0, 0, 0)
    var azimuth: Float = .pi / 4 // radians around Y, measured from +Z
    var elevation: Float = .pi / 6 // radians above the XZ plane
    var distance: Float = 300 // mm

    private let minElevation: Float = -.pi / 2 + 0.01
    private let maxElevation: Float = .pi / 2 - 0.01

    mutating func orbit(deltaAzimuth: Float, deltaElevation: Float) {
        azimuth -= deltaAzimuth
        elevation = min(max(elevation + deltaElevation, minElevation), maxElevation)
    }

    mutating func zoom(by factor: Float) {
        distance = min(max(distance * factor, 10), 5000)
    }

    var eye: SIMD3<Float> {
        target + distance * SIMD3(
            cos(elevation) * sin(azimuth),
            sin(elevation),
            cos(elevation) * cos(azimuth)
        )
    }

    var viewMatrix: simd_float4x4 { lookAt(eye: eye, target: target, up: SIMD3(0, 1, 0)) }

    func projectionMatrix(aspect: Float) -> simd_float4x4 {
        perspective(fovyRadians: .pi / 4, aspect: aspect, near: 1, far: 10000)
    }
}

/// Right-handed look-at matrix (camera looks down -Z in view space).
func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
    let z = normalize(eye - target)
    let x = normalize(cross(up, z))
    let y = cross(z, x)
    return simd_float4x4(
        SIMD4(x.x, y.x, z.x, 0),
        SIMD4(x.y, y.y, z.y, 0),
        SIMD4(x.z, y.z, z.z, 0),
        SIMD4(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
    )
}

/// Right-handed perspective matrix mapping view-space Z to Metal's clip-space
/// depth range [0, 1] (not OpenGL's [-1, 1] — using a GL-style matrix here
/// would clip half the usable depth range).
func perspective(fovyRadians fovy: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
    let yScale = 1 / tan(fovy * 0.5)
    let xScale = yScale / aspect
    let zScale = far / (near - far)
    let wzScale = near * far / (near - far)
    return simd_float4x4(
        SIMD4(xScale, 0, 0, 0),
        SIMD4(0, yScale, 0, 0),
        SIMD4(0, 0, zScale, -1),
        SIMD4(0, 0, wzScale, 0)
    )
}
