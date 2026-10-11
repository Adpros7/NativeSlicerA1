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

/// Loads a 3MF file via libslic3r's `load_3mf` and returns the number of
/// top-level model objects it contains, or -1 on failure.
int64_t nsa1_3mf_object_count(const char *path);

/// Loads a 3MF file and returns the first volume's mesh of the model
/// object at `object_index`, or NULL on failure/out-of-range index.
NSA1Mesh *nsa1_load_3mf_mesh(const char *path, int64_t object_index);

/// Reads the first instance's placement matrix of the model object at
/// `object_index` into `out_matrix16` (column-major 4x4, i.e. `v' = M*v`
/// for column vectors — the same convention as Swift's `simd_float4x4`).
/// Returns 0 on success, -1 on failure/out-of-range index.
int nsa1_3mf_object_matrix(const char *path, int64_t object_index, double *out_matrix16);

/// One placed object to write into a 3MF project file: its mesh plus a
/// column-major 4x4 placement matrix (16 doubles, same convention as
/// `nsa1_3mf_object_matrix`/`simd_float4x4`).
typedef struct {
    const float *vertices;
    size_t vertex_count;
    const uint32_t *indices;
    size_t index_count;
    const double *matrix16;
} NSA1SceneObject;

/// Writes `object_count` placed objects to a 3MF project file via
/// libslic3r's `store_3mf` (the same writer BambuStudio/OrcaSlicer use for
/// their own project format — P1-007). Returns 0 on success, -1 on
/// failure.
int nsa1_store_3mf(const char *path, const NSA1SceneObject *objects, size_t object_count);

/// One `key = value` config entry, already serialized to libslic3r's own
/// config string format (the same format `BambuProfileLoader`'s resolved
/// JSON fields use: scalars as-is, arrays joined with `,` — matching
/// BambuStudio's own `ConfigBase::load_from_json` separator convention).
typedef struct {
    const char *key;
    const char *value;
} NSA1ConfigEntry;

/// Slices `object_count` placed objects (mesh + column-major placement
/// matrix, same convention as `NSA1SceneObject`) with the resolved A1
/// printer/process/filament config and writes real G-code to
/// `out_gcode_path` via libslic3r's own `Print::apply`/`validate`/
/// `process`/`export_gcode` pipeline (P1-008). Returns 0 on success, -1 on
/// failure. On failure, `*out_error` is set to a newly allocated
/// human-readable message (free with `nsa1_free_string`); on success
/// `*out_error` is set to NULL.
int nsa1_slice_to_gcode(
    const NSA1SceneObject *objects, size_t object_count,
    const NSA1ConfigEntry *config_entries, size_t config_entry_count,
    const char *out_gcode_path,
    char **out_error);

/// Releases a string returned by `nsa1_slice_to_gcode`'s `out_error`. Safe
/// to call with NULL.
void nsa1_free_string(char *s);

#ifdef __cplusplus
}
#endif

#endif
