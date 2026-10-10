#ifndef CSLIC3R_BRIDGE_H
#define CSLIC3R_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Loads an STL file via libslic3r's TriangleMesh::ReadSTLFile and returns
/// its triangle (facet) count, or -1 on failure. This is the minimal proof
/// that the Swift package actually links against and calls into the real
/// vendored libslic3r static library (RESEARCH.md P0-001..P0-004) rather
/// than a hand-rolled parser — the STL/3MF importers (P1-004/P1-005) build
/// on this same bridge.
int64_t nsa1_stl_triangle_count(const char *path);

/// Flat, C-ABI-safe view of a triangle mesh: `vertices` is `vertex_count`
/// XYZ float triples, `indices` is `index_count` (always a multiple of 3)
/// triangle vertex indices into `vertices`. Owns its own heap buffers;
/// free with `nsa1_free_mesh`.
typedef struct {
    const float *vertices;
    size_t vertex_count;
    const uint32_t *indices;
    size_t index_count;
} NSA1Mesh;

/// Loads an STL file via libslic3r's TriangleMesh::ReadSTLFile and returns
/// a flat vertex/index buffer view, or NULL on failure. The real geometry
/// backing P1-004 (STL import) and the Metal viewport's mesh rendering.
NSA1Mesh *nsa1_load_stl_mesh(const char *path);

/// Releases a mesh returned by `nsa1_load_stl_mesh`. Safe to call with NULL.
void nsa1_free_mesh(NSA1Mesh *mesh);

#ifdef __cplusplus
}
#endif

#endif
