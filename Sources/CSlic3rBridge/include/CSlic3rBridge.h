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

/// One `key = value` config entry, already serialized to libslic3r's own
/// config string format (the same format `BambuProfileLoader`'s resolved
/// JSON fields use: scalars as-is, arrays joined with `,` — matching
/// BambuStudio's own `ConfigBase::load_from_json` separator convention).
typedef struct {
    const char *key;
    const char *value;
} NSA1ConfigEntry;

/// Writes `object_count` placed objects, plus the full A1 engine config
/// resolved from `config_entries` (same seeding/null-keys_map-repair/
/// overlay as `nsa1_slice_to_gcode`), to a 3MF project file via
/// libslic3r's `store_3mf` (the same writer BambuStudio/OrcaSlicer use for
/// their own project format — P1-007). `config_entries` lets profile
/// selection and setting overrides persist across saves, not just
/// geometry (P3-003). Returns 0 on success, -1 on failure.
int nsa1_store_3mf(
    const char *path, const NSA1SceneObject *objects, size_t object_count,
    const NSA1ConfigEntry *config_entries, size_t config_entry_count);

/// Reads back every config key embedded by `nsa1_store_3mf` from a 3MF
/// project file via libslic3r's own `load_3mf` (P3-003 settings
/// persistence), as an array of `NSA1ConfigEntry`. `*out_count` is set to
/// the array length. Returns NULL (and `*out_count = 0`) on failure or if
/// the file has no embedded config (e.g. a bare P1-007-era project).
/// Free the result with `nsa1_free_config_entries`.
NSA1ConfigEntry *nsa1_load_3mf_config(const char *path, size_t *out_count);

/// Releases an array returned by `nsa1_load_3mf_config`. Safe to call
/// with NULL/0.
void nsa1_free_config_entries(NSA1ConfigEntry *entries, size_t count);


/// One real toolpath segment from the engine's own `GCodeProcessorResult`
/// (the same per-move data BambuStudio's own G-code preview consumes):
/// a straight line from `(start_x,start_y,start_z)` to `(end_x,end_y,end_z)`,
/// `is_travel` true for non-extruding (travel) moves, `width`/`height` the
/// extrusion cross-section in mm (0 for travel moves).
typedef struct {
    float start_x, start_y, start_z;
    float end_x, end_y, end_z;
    float width;
    float height;
    uint8_t is_travel;
} NSA1ToolpathSegment;

typedef struct {
    const NSA1ToolpathSegment *segments;
    size_t segment_count;
} NSA1Toolpath;

/// Slices `object_count` placed objects (mesh + column-major placement
/// matrix, same convention as `NSA1SceneObject`) with the resolved A1
/// printer/process/filament config and writes real G-code to
/// `out_gcode_path` via libslic3r's own `Print::apply`/`validate`/
/// `process`/`export_gcode` pipeline (P1-008). Returns 0 on success, -1 on
/// failure. On failure, `*out_error` is set to a newly allocated
/// human-readable message (free with `nsa1_free_string`); on success
/// `*out_error` is set to NULL.
///
/// If `out_toolpath` is non-NULL, it's set to the real per-move toolpath
/// data the engine's own `GCodeProcessorResult` already computed while
/// writing the G-code file (P1-009) — free with `nsa1_free_toolpath`. Set
/// to NULL on failure or if `out_toolpath` was itself NULL.
int nsa1_slice_to_gcode(
    const NSA1SceneObject *objects, size_t object_count,
    const NSA1ConfigEntry *config_entries, size_t config_entry_count,
    const char *out_gcode_path,
    NSA1Toolpath **out_toolpath,
    char **out_error);

/// Numeric values map to `CalibrationWorkflow` in Swift. Kept as a fixed
/// int32_t in the request so C callers do not depend on C++ enum layout.
enum {
    NSA1_CALIBRATION_FLOW_RATE,
    NSA1_CALIBRATION_PRESSURE_ADVANCE,
    NSA1_CALIBRATION_TEMPERATURE,
    NSA1_CALIBRATION_RETRACTION,
    NSA1_CALIBRATION_MAX_VOLUMETRIC_SPEED,
};

/// A requested real-engine calibration generation. `resource_path` must be
/// an app-bundled upstream model selected by Swift, never arbitrary user
/// input. The bridge still validates that it can be read. Config entries use
/// the exact resolved-profile format accepted by `nsa1_slice_to_gcode`.
typedef struct {
    int32_t workflow;
    double start;
    double end;
    double step;
    const char *resource_path;
    const NSA1ConfigEntry *config_entries;
    size_t config_entry_count;
} NSA1CalibrationRequest;

/// One generated calibration value. Z bounds are filled only by a successful
/// workflow that knows them; the resource-validation path returns no result.
typedef struct {
    size_t ordinal;
    double value;
    double start_z;
    double end_z;
} NSA1CalibrationBlock;

typedef struct {
    NSA1Toolpath *toolpath;
    NSA1CalibrationBlock *blocks;
    size_t block_count;
} NSA1CalibrationResult;

/// Validates and generates calibration G-code through the real engine. This
/// operation never uploads, sends, or starts a printer action. On failure
/// `*out_error` is a newly allocated message freed by `nsa1_free_string`.
int nsa1_generate_calibration_gcode(
    const NSA1CalibrationRequest *request,
    const char *out_gcode_path,
    NSA1CalibrationResult **out_result,
    char **out_error);

/// Releases every allocation in a successful calibration result. Safe with
/// NULL; `toolpath` follows the same ownership convention as
/// `nsa1_free_toolpath`.
void nsa1_free_calibration_result(NSA1CalibrationResult *result);

/// Releases a toolpath returned by `nsa1_slice_to_gcode`'s `out_toolpath`.
/// Safe to call with NULL.
void nsa1_free_toolpath(NSA1Toolpath *toolpath);

/// Releases a string returned by `nsa1_slice_to_gcode`'s `out_error`. Safe
/// to call with NULL.
void nsa1_free_string(char *s);


#ifdef __cplusplus
}
#endif

#endif
