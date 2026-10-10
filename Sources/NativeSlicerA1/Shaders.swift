/// Metal shader source for the viewport, compiled at runtime via
/// `MTLDevice.makeLibrary(source:)`. SwiftPM executable targets (no Xcode
/// build phase, no app bundle `default.metallib`) can't compile `.metal`
/// files at build time, so this is the boring portable option.
///
/// Normals are computed per-triangle from screen-space position
/// derivatives (`dfdx`/`dfdy`) rather than from a CPU-side normal buffer —
/// `libslic3r`'s `indexed_triangle_set` only exposes positions, and flat
/// per-triangle shading is the correct look for a mesh preview anyway.
let viewportShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
};

struct VertexOut {
    float4 clipPosition [[position]];
    float3 worldPosition;
};

struct Uniforms {
    float4x4 modelViewProjection;
    float4x4 model;
    float4 color;
};

vertex VertexOut viewport_vertex(VertexIn in [[stage_in]],
                                  constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    float4 world = uniforms.model * float4(in.position, 1.0);
    out.worldPosition = world.xyz;
    out.clipPosition = uniforms.modelViewProjection * float4(in.position, 1.0);
    return out;
}

fragment float4 viewport_fragment(VertexOut in [[stage_in]],
                                   constant Uniforms &uniforms [[buffer(1)]]) {
    float3 normal = normalize(cross(dfdx(in.worldPosition), dfdy(in.worldPosition)));
    float3 lightDirection = normalize(float3(0.4, 0.8, 0.5));
    float diffuse = max(dot(normal, lightDirection), 0.0);
    float ambient = 0.35;
    float3 lit = uniforms.color.rgb * (ambient + diffuse * 0.65);
    return float4(lit, uniforms.color.a);
}
"""
