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

/// Writes a single triangle mesh to a binary STL file via
/// TriangleMesh::write_binary (P1-010). Returns 0 on success, -1 on
/// failure (out_error is set to a newly allocated message).
int nsa1_store_stl(const char *path, const NSA1Mesh *mesh, char **out_error);

/// Loads a binary STL file into a flat vertex/index mesh (P1-010).
/// Returns NULL on failure.
NSA1Mesh *nsa1_load_stl_mesh_binary(const char *path);

/// Writes a single triangle mesh to an OBJ file via
/// TriangleMesh::WriteOBJFile (P1-010). Returns 0 on success, -1 on
/// failure (out_error is set to a newly allocated message).
int nsa1_store_obj(const char *path, const NSA1Mesh *mesh, char **out_error);

/// Loads an OBJ file into a flat vertex/index mesh (P1-010).
/// Returns NULL on failure.
NSA1Mesh *nsa1_load_obj_mesh(const char *path);

/// Loads an STEP file into a flat vertex/index mesh via libslic3r's
/// Step class (OpenCascade tessellation, P1-010). Returns NULL on
/// failure.
NSA1Mesh *nsa1_load_step_mesh(const char *path);

/// Loads a 3MF file via libslic3r's `load_3mf` and returns the number of
/// top-level model objects it contains, or -1 on failure.
/// Extracts the `unit` attribute from a 3MF file's `<model>` element.
/// Returns a newly allocated string (freed by `nsa1_free_string`);
char *nsa1_get_3mf_unit(const char *path);

/// Auto-orient: runs upstream orient() on a mesh, returns optimal rotation
/// matrix (column-major 4x4) that minimizes overhang area. Returns 0 on
/// success, -1 on failure.
int nsa1_auto_orient(const float *vertices, size_t vertex_count,
    const uint32_t *indices, size_t index_count, double *out_matrix16);

/// Connector type/style/shape enums match upstream `CutConnectorType`/
/// `CutConnectorStyle`/`CutConnectorShape` (Model.hpp) numeric order, so
/// Swift callers can pass raw ints without depending on C++ enum layout.
/// type: 0=Plug,1=Dowel,2=Snap,3=Thread. style: 0=Prizm,1=Frustum.
/// shape: 0=Triangle,1=Square,2=Hexagon,3=Circle.
///
/// Generates a connector solid via the real engine's
/// `ModelObject::get_connector_mesh` (P4-005), scaled to `radius`/`height`
/// (mm) exactly as upstream's `apply_cut_connectors` scales the unit mesh.
/// If `apply_hole_tolerance` is nonzero, additionally widens the XY scale
/// by `radius_tolerance` and the Z scale by `height_tolerance`, matching
/// upstream's `apply_tolerance` (CutUtils.cpp) used for the connector's
/// negative-volume "hole" side. Returns NULL for an invalid enum value or
/// on internal failure; free the result with `nsa1_free_mesh`.
NSA1Mesh *nsa1_make_connector_mesh(
    int32_t connector_type, int32_t connector_style, int32_t connector_shape,
    float radius, float height,
    float radius_tolerance, float height_tolerance,
    uint8_t apply_hole_tolerance);

/// Loads a 3MF file and returns the first volume's mesh of the model
/// object at `object_index`, or NULL on failure/out-of-range index.
int64_t nsa1_3mf_object_count(const char *path);

NSA1Mesh *nsa1_load_3mf_mesh(const char *path, int64_t object_index);
/// Loads support-paint annotations saved in a 3MF object's first model
/// volume, serializing its real `FacetsAnnotation` into the same opaque
/// byte format as `nsa1_paint_serialize`. Returns NULL/size=0 for an
/// unpainted object or on failure; free non-NULL output with
/// `nsa1_paint_data_free`.
uint8_t *nsa1_load_3mf_paint(const char *path, int64_t object_index, size_t *out_size);

/// `object_index` into `out_matrix16` (column-major 4x4, i.e. `v' = M*v`
/// for column vectors — the same convention as Swift's `simd_float4x4`).
/// Returns 0 on success, -1 on failure/out-of-range index.
int nsa1_3mf_object_matrix(const char *path, int64_t object_index, double *out_matrix16);

/// One Z-height band with an overridden layer height (P4-014), matching
/// upstream's `t_layer_height_range` key (`[z_min, z_max)` in mm, object
/// local Z) and the "layer_height" key of its paired `ModelConfig` value.
typedef struct {
    double z_min;
    double z_max;
    double layer_height;
} NSA1LayerHeightRange;

/// One placed object to write into a 3MF project file: its mesh plus a
/// column-major 4x4 placement matrix (16 doubles, same convention as
/// `nsa1_3mf_object_matrix`/`simd_float4x4`).
typedef struct {
    const float *vertices;
    size_t vertex_count;
    const uint32_t *indices;
    size_t index_count;
    const double *matrix16;
    /// P3-005 support-paint data from `nsa1_paint_serialize`, or NULL if
    /// this object has no painted enforcer/blocker regions.
    const uint8_t *paint_data;
    size_t paint_data_size;
    /// P4-014 variable layer height Z-ranges, or NULL for the default
    /// uniform layer height throughout the object.
    const NSA1LayerHeightRange *layer_height_ranges;
    size_t layer_height_range_count;
} NSA1SceneObject;

/// Result of auto-arranging one object (P4-011): translation in mm to
/// apply on top of the object's existing XY placement, rotation in
/// radians, and the logical bed index (0 = the physical bed; the real
/// engine's `arrange()` assigns >0 only if objects don't fit together).
typedef struct {
    double x;
    double y;
    double rotation;
    int32_t bed_index;
} NSA1ArrangeResult;

/// Auto-arranges `object_count` objects on a `bed_width_mm` x
/// `bed_height_mm` rectangular bed via the real engine's libnest2d-backed
/// `Slic3r::arrange()`, using each object's real 2D convex hull (not a
/// bounding-box approximation) as its packing silhouette. `clearance_mm`
/// is the minimum required gap between any two objects. `out_results`
/// must point to caller-allocated storage for `object_count` entries.
/// Returns 0 on success, -1 on failure.
int nsa1_auto_arrange(
    const NSA1SceneObject *objects, size_t object_count,
    double bed_width_mm, double bed_height_mm, double clearance_mm,
    NSA1ArrangeResult *out_results);

/// Opaque handle to an in-progress support-paint editing session for one
/// mesh (P3-005), wrapping the real engine's `Slic3r::TriangleSelector`.
typedef struct NSA1PaintState NSA1PaintState;

/// Creates a paint-editing session for one mesh. `vertices`/`indices`
/// must be the object's local (un-instance-transformed) geometry, same
/// convention as `LoadedMesh`. The mesh data is copied; the returned
/// handle owns it. Free with `nsa1_paint_free`.
NSA1PaintState *nsa1_paint_create(
    const float *vertices, size_t vertex_count,
    const uint32_t *indices, size_t index_count);

/// Paints a spherical brush stroke at `(center_x, center_y, center_z)`
/// (local mesh coordinates) with the given `radius` (mm), subdividing
/// triangles as needed for a precise boundary (matches upstream's
/// `TriangleSelector::select_patch` with a `Sphere` cursor).
/// `enforcer_blocker` is 0 = erase (NONE), 1 = ENFORCER, 2 = BLOCKER.
void nsa1_paint_sphere(
    NSA1PaintState *state,
    double center_x, double center_y, double center_z, double radius,
    int enforcer_blocker);

/// Serializes the current paint state to an opaque byte buffer (the
/// real engine's own `TriangleSelector::serialize()` format, flattened).
/// `*out_data` is newly allocated; free with `nsa1_paint_data_free`.
void nsa1_paint_serialize(NSA1PaintState *state, uint8_t **out_data, size_t *out_size);
/// Replaces `state`'s paint contents with bytes returned by
/// `nsa1_paint_serialize` (or loaded from a 3MF via
/// `nsa1_load_3mf_paint`). Returns 0 on success, -1 for malformed data.
int nsa1_paint_deserialize(NSA1PaintState *state, const uint8_t *data, size_t size);


/// Releases a buffer returned by `nsa1_paint_serialize`.
void nsa1_paint_data_free(uint8_t *data);

/// Releases a handle returned by `nsa1_paint_create`.
void nsa1_paint_free(NSA1PaintState *state);

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
typedef struct {
    float start_x;
    float start_y;
    float start_z;
    float end_x;
    float end_y;
    float end_z;
    float feedrate;
    float temperature;
    float layer_duration;
    float extruder_id;
    float extrusion_role;
    float width;
    float height;
    uint8_t is_travel;
} NSA1ToolpathSegment;

typedef struct {
    const NSA1ToolpathSegment *segments;
    size_t segment_count;
} NSA1Toolpath;

/// Estimated print statistics from the engine's GCodeProcessor (P1-011).
typedef struct {
    double normal_time;            // total print time (seconds)
    double normal_prepare_time;    // pre-print setup time (seconds)
    double stealth_time;           // silent mode print time (seconds)
    double stealth_prepare_time;   // silent mode setup time (seconds)
    double total_filament_load_time;
    double total_filament_unload_time;
    double total_tool_change_time;
    double total_travel_distance;
    int total_filament_changes;
    int total_flush_filament_changes;
    int total_extruder_changes;
    int total_travel_moves;
    double total_seam_gap_distance;
    double total_seam_scarf_distance;
    // Per-extruder filament volume (mm3) — extruder_id maps to index.
    size_t extruder_count;
    const double *extruder_volumes_mm3;
    // Per-role filament: (length_mm, volume_mm3) pairs.
    size_t role_count;
    const double *role_lengths_mm;
    const double *role_volumes_mm3;
} NSA1EstimatedStatistics;

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

/// Same as `nsa1_slice_to_gcode` but also returns estimated print
/// statistics via `out_statistics` (P1-011). Returns 0 on success, -1 on
/// failure. On failure, `*out_error` is set to a newly allocated
/// human-readable message (free with `nsa1_free_string`); on success
/// `*out_error` is set to NULL. On success, if `out_statistics` is
/// non-NULL, it's set to a newly allocated `NSA1EstimatedStatistics`
/// (free with `nsa1_free_estimated_statistics`). Set to NULL on failure
/// or if `out_statistics` was itself NULL.
int nsa1_slice_to_gcode_with_statistics(
    const NSA1SceneObject *objects, size_t object_count,
    const NSA1ConfigEntry *config_entries, size_t config_entry_count,
    const char *out_gcode_path,
    NSA1Toolpath **out_toolpath,
    NSA1EstimatedStatistics **out_statistics,
    char **out_error);

void nsa1_free_estimated_statistics(NSA1EstimatedStatistics *stats);

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
/// Cuts a model object along a user-specified plane (P4-004).
/// `plane_points` is 4 Vec3d points defining the cut plane.
/// `cut_mode` determines which parts are kept: 0=both halves, 1=lower,
/// 2=upper. Returns a new NSA1SceneObject** array of the resulting
/// objects (0, 1, or 2), plus the count. On failure `*out_error` is a
/// newly allocated message freed by `nsa1_free_string`.
typedef struct {
    double x, y, z;
} NSA1Vec3d;

/// One pending P4-006 cut connector. Position and normal are WORLD-space
/// (same convention as `NSA1CutRequest::plane_points`); type/style/shape
/// follow `CutConnectorType`/`Style`/`Shape` numeric order documented by
/// `nsa1_make_connector_mesh`. Radius/height/tolerances are mm and match
/// `CutConnector`/`CutUtils.cpp` semantics.
typedef struct {
    NSA1Vec3d position;
    NSA1Vec3d normal;
    int32_t type;
    int32_t style;
    int32_t shape;
    float radius;
    float height;
    float radius_tolerance;
    float height_tolerance;
} NSA1CutConnector;

typedef struct {
    NSA1Vec3d plane_points[4];
    int cut_mode;  // 0=both, 1=lower, 2=upper
    const NSA1CutConnector *connectors; // optional; NULL if connector_count=0
    size_t connector_count;
} NSA1CutRequest;

int nsa1_cut_model(
    const NSA1SceneObject *scene_objects, size_t object_count,
    const NSA1CutRequest *cut_request,
    NSA1SceneObject ***out_objects, size_t *out_object_count,
    char **out_error);

/// Releases an `out_objects` array returned by `nsa1_cut_model` (every
/// entry's mesh/matrix buffers, the entries themselves, and the array).
/// Safe to call with NULL.
void nsa1_free_cut_results(NSA1SceneObject **objects, size_t count);


#ifdef __cplusplus
}
#endif

#endif
