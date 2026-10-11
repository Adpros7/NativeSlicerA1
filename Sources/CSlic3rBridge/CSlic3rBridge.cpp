#include "CSlic3rBridge.h"

// NSVGUtils.cpp inside libslic3r.a calls nsvgParse/nsvgDelete/nsvgParseFromFile
// but only BambuStudio's GUI layer (Utils/BitmapCache.cpp) provides the
// NANOSVG_IMPLEMENTATION translation unit. Providing it here keeps the
// dependency satisfied without pulling in the GUI. Must come before any
// libslic3r header that might transitively include nanosvg.h undefined,
// since its include guard would otherwise block our definition.
#define NANOSVG_IMPLEMENTATION
#include "nanosvg.h"

#include "libslic3r/TriangleMesh.hpp"
#include "libslic3r/Model.hpp"
#include "libslic3r/Format/3mf.hpp"
#include "libslic3r/Calib.hpp"
#include "libslic3r/Print.hpp"
#include "libslic3r/PrintConfig.hpp"
#include "libslic3r/miniz_extension.hpp"
#include "libslic3r/Format/STEP.hpp"
#include "libslic3r/Orient.hpp"
#include <cstring>
#include <array>
#include <filesystem>
#include <memory>
namespace {
NSA1Mesh *copy_mesh(const Slic3r::TriangleMesh &mesh) {
    const auto &its = mesh.its;
    auto *vertices = new float[its.vertices.size() * 3];
    for (size_t i = 0; i < its.vertices.size(); ++i) {
        vertices[i * 3 + 0] = its.vertices[i].x();
        vertices[i * 3 + 1] = its.vertices[i].y();
        vertices[i * 3 + 2] = its.vertices[i].z();
    }
    auto *indices = new uint32_t[its.indices.size() * 3];
    for (size_t i = 0; i < its.indices.size(); ++i) {
        indices[i * 3 + 0] = static_cast<uint32_t>(its.indices[i].x());
        indices[i * 3 + 1] = static_cast<uint32_t>(its.indices[i].y());
        indices[i * 3 + 2] = static_cast<uint32_t>(its.indices[i].z());
    }
    auto *out = new NSA1Mesh();
    out->vertices = vertices;
    out->vertex_count = its.vertices.size();
    out->indices = indices;
    out->index_count = its.indices.size() * 3;
    return out;
}
} // namespace

extern "C" int64_t nsa1_stl_triangle_count(const char *path) {
    Slic3r::TriangleMesh mesh;
    if (!mesh.ReadSTLFile(path, /*repair=*/false)) {
        return -1;
    }
    return static_cast<int64_t>(mesh.facets_count());
}

extern "C" NSA1Mesh *nsa1_load_stl_mesh(const char *path) {
    Slic3r::TriangleMesh mesh;
    if (!mesh.ReadSTLFile(path, /*repair=*/false)) {
        return nullptr;
    }
    return copy_mesh(mesh);
}

extern "C" void nsa1_free_mesh(NSA1Mesh *mesh) {
    if (!mesh) return;
    delete[] mesh->vertices;
    delete[] mesh->indices;
    delete mesh;
}

extern "C" int nsa1_store_stl(const char *path, const NSA1Mesh *mesh, char **out_error) {
    std::vector<Slic3r::Vec3f> vertices(mesh->vertex_count);
    std::vector<Slic3r::Vec3i> faces(mesh->index_count / 3);
    for (size_t i = 0; i < mesh->vertex_count; ++i) {
        vertices[i] = Slic3r::Vec3f(mesh->vertices[i * 3], mesh->vertices[i * 3 + 1], mesh->vertices[i * 3 + 2]);
    }
    for (size_t i = 0; i < mesh->index_count / 3; ++i) {
        faces[i] = Slic3r::Vec3i(mesh->indices[i * 3], mesh->indices[i * 3 + 1], mesh->indices[i * 3 + 2]);
    }
    Slic3r::TriangleMesh m(vertices, faces);
    try {
        m.write_binary(path);
        return 0;
    } catch (const std::exception &e) {
        if (out_error) *out_error = strdup(e.what());
        return -1;
    }
}

extern "C" NSA1Mesh *nsa1_load_stl_mesh_binary(const char *path) {
    Slic3r::TriangleMesh m;
    try {
        // `ReadSTLFile` handles both binary and ASCII STL files.
        if (!m.ReadSTLFile(path, /*repair=*/false)) return nullptr;
        return copy_mesh(m);
    } catch (const std::exception &) {
        return nullptr;
    }
}

extern "C" int nsa1_store_obj(const char *path, const NSA1Mesh *mesh, char **out_error) {
    std::vector<Slic3r::Vec3f> vertices(mesh->vertex_count);
    std::vector<Slic3r::Vec3i> faces(mesh->index_count / 3);
    for (size_t i = 0; i < mesh->vertex_count; ++i) {
        vertices[i] = Slic3r::Vec3f(mesh->vertices[i * 3], mesh->vertices[i * 3 + 1], mesh->vertices[i * 3 + 2]);
    }
    for (size_t i = 0; i < mesh->index_count / 3; ++i) {
        faces[i] = Slic3r::Vec3i(mesh->indices[i * 3], mesh->indices[i * 3 + 1], mesh->indices[i * 3 + 2]);
    }
    Slic3r::TriangleMesh m(vertices, faces);
    try {
        m.WriteOBJFile(path);
        return 0;
    } catch (const std::exception &e) {
        if (out_error) *out_error = strdup(e.what());
        return -1;
    }
}

extern "C" NSA1Mesh *nsa1_load_obj_mesh(const char *path) {
    try {
        Slic3r::TriangleMesh m;
        Slic3r::ObjInfo obj_info;
        std::string message;
        if (!Slic3r::load_obj(path, &m, obj_info, message)) return nullptr;
        return copy_mesh(m);
    } catch (const std::exception &) {
        return nullptr;
    }
}

extern "C" NSA1Mesh *nsa1_load_step_mesh(const char *path) {
    try {
        // `Step` class takes a path string; `load()` returns Step::Step_Status
        // (no arguments); `mesh(Model*, bool&, bool)` does the actual
        Slic3r::Step step{std::string(path)};
        bool cancelled = false;
        Slic3r::Step::Step_Status status = step.load();
        if (status != Slic3r::Step::Step_Status::LOAD_SUCCESS) return nullptr;
        Slic3r::Model model;
        status = step.mesh(&model, cancelled, /*isSplitCompound=*/false);
        if (status != Slic3r::Step::Step_Status::MESH_SUCCESS || model.objects.empty()) {
            return nullptr;
        }
        // Model::mesh() merges all objects/volumes into one transformed
        // TriangleMesh (exactly how upstream STL export works).
        Slic3r::TriangleMesh mesh = model.mesh();
        return copy_mesh(mesh);
    } catch (const std::exception &) {
        return nullptr;
    }
}
namespace {

bool load_3mf_model(const char *path, Slic3r::Model &model) {
    Slic3r::DynamicPrintConfig config;
    Slic3r::ConfigSubstitutionContext substitutions(Slic3r::ForwardCompatibilitySubstitutionRule::Disable);
    return Slic3r::load_3mf(path, config, substitutions, &model, /*check_version=*/false);
}
} // namespace

extern "C" int64_t nsa1_3mf_object_count(const char *path) {
    Slic3r::Model model;
    if (!load_3mf_model(path, model)) {
        return -1;
    }
    return static_cast<int64_t>(model.objects.size());
}
// Extract the `unit` attribute from a 3MF file's `<model>` element.
// Returns "millimeter" (the 3MF spec default) if not found.
extern "C" char *nsa1_get_3mf_unit(const char *path) {
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) return strdup("millimeter");
    std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    size_t modelPos = content.find("<model");
    if (modelPos == std::string::npos) return strdup("millimeter");
    size_t modelEnd = content.find(">", modelPos);
    if (modelEnd == std::string::npos) return strdup("millimeter");
    std::string modelTag = content.substr(modelPos, modelEnd - modelPos);
    size_t unitPos = modelTag.find("unit=");
    if (unitPos == std::string::npos) return strdup("millimeter");
    size_t quoteStart = modelTag.find('"', unitPos + 5);
    if (quoteStart == std::string::npos) return strdup("millimeter");
    size_t quoteEnd = modelTag.find('"', quoteStart + 1);
    if (quoteEnd == std::string::npos) return strdup("millimeter");
    std::string unit = modelTag.substr(quoteStart + 1, quoteEnd - quoteStart - 1);
    return strdup(unit.c_str());
}
// Auto-orient: runs upstream orient() on a mesh and returns the optimal
// transformation (rotation matrix + translation) that minimizes overhang.
// Returns 0 on success, -1 on failure.
extern "C" int nsa1_auto_orient(
    const float *vertices, size_t vertex_count,
    const uint32_t *indices, size_t index_count,
    double *out_matrix16) {
    try {
        std::vector<Slic3r::Vec3f> verts(vertex_count);
        for (size_t i = 0; i < vertex_count; ++i) {
            verts[i] = Slic3r::Vec3f(vertices[i * 3 + 0], vertices[i * 3 + 1], vertices[i * 3 + 2]);
        }
        std::vector<Slic3r::Vec3i> faces(index_count / 3);
        for (size_t i = 0; i < faces.size(); ++i) {
            faces[i] = Slic3r::Vec3i(
                static_cast<int>(indices[i * 3 + 0]),
                static_cast<int>(indices[i * 3 + 1]),
                static_cast<int>(indices[i * 3 + 2]));
        }
        Slic3r::TriangleMesh mesh(verts, faces);

        Slic3r::orientation::OrientMesh orientMesh;
        orientMesh.mesh = std::move(mesh);

        // Run upstream orient with default params (minimize support area)
        Slic3r::orientation::OrientMeshs items;
        items.push_back(std::move(orientMesh));
        Slic3r::orientation::OrientMeshs excludes;
        Slic3r::orientation::OrientParams params;
        Slic3r::orientation::orient(items, excludes, params);

        if (items.empty()) return -1;

        // Extract the transformation matrix (column-major 4x4)
        const auto &mat = items.front().rotation_matrix;
        for (int i = 0; i < 16; ++i) {
            out_matrix16[i] = mat.data()[i];
        }
        return 0;
    } catch (...) {
        return -1;
    }
}

extern "C" NSA1Mesh *nsa1_load_3mf_mesh(const char *path, int64_t object_index) {
    Slic3r::Model model;
    if (!load_3mf_model(path, model)) {
        return nullptr;
    }
    if (object_index < 0 || static_cast<size_t>(object_index) >= model.objects.size()) {
        return nullptr;
    }
    const Slic3r::ModelObject *object = model.objects[static_cast<size_t>(object_index)];
    if (object->volumes.empty()) {
        return nullptr;
    }
    // `load_3mf` centers a volume's mesh and keeps the compensating local
    // placement on ModelVolume. Apply it to this exported copy so Swift
    // receives object-local geometry; the separately exported instance
    // matrix then remains the complete scene-object placement.
    Slic3r::TriangleMesh mesh = object->volumes.front()->mesh();
    mesh.transform(object->volumes.front()->get_transformation().get_matrix(), /*fix_left_handed=*/false);
    return copy_mesh(mesh);
}

extern "C" int nsa1_3mf_object_matrix(const char *path, int64_t object_index, double *out_matrix16) {
    Slic3r::Model model;
    if (!load_3mf_model(path, model)) {
        return -1;
    }
    if (object_index < 0 || static_cast<size_t>(object_index) >= model.objects.size()) {
        return -1;
    }
    const Slic3r::ModelObject *object = model.objects[static_cast<size_t>(object_index)];
    if (object->instances.empty()) {
        return -1;
    }
    const Slic3r::Transform3d &matrix = object->instances.front()->get_transformation().get_matrix();
    // Eigen stores column-major by default, matching simd_float4x4's layout.
    std::memcpy(out_matrix16, matrix.data(), 16 * sizeof(double));
    return 0;
}
namespace {


void cut_model_at_height(Slic3r::Model &model, double height, Slic3r::ModelObjectCutAttribute attribute) {
    if (model.objects.empty()) return;
    const auto box = model.objects.front()->bounding_box();
    const std::array<Slic3r::Vec3d, 4> plane{
        Slic3r::Vec3d(box.min(0), box.min(1), height),
        Slic3r::Vec3d(box.max(0), box.min(1), height),
        Slic3r::Vec3d(box.max(0), box.max(1), height),
        Slic3r::Vec3d(box.min(0), box.max(1), height)
    };
    const auto new_objects = model.objects.front()->cut(0, plane, attribute);
    model.delete_object(static_cast<size_t>(0));
    for (auto *part : new_objects) {
        auto *object = model.add_object(*part);
        object->sort_volumes(true);
        object->ensure_on_bed();
    }
}
// Forward declaration (defined later in this file).
Slic3r::Model build_model_from_objects(const NSA1SceneObject *objects, size_t object_count);
// Helper: converts a Slic3r::ModelObject to an NSA1SceneObject.
// The mesh is already transformed, so no matrix is needed.
NSA1SceneObject *scene_object_from_model_object(const Slic3r::ModelObject &obj) {
    Slic3r::TriangleMesh mesh = obj.mesh();
    NSA1Mesh *mesh_data = copy_mesh(mesh);

    auto *scene_obj = static_cast<NSA1SceneObject *>(
        malloc(sizeof(NSA1SceneObject)));
    scene_obj->vertices = mesh_data->vertices;
    scene_obj->vertex_count = mesh_data->vertex_count;
    scene_obj->indices = mesh_data->indices;
    scene_obj->index_count = mesh_data->index_count;
    scene_obj->matrix16 = nullptr;

    nsa1_free_mesh(mesh_data);
    return scene_obj;
}

extern "C" int nsa1_cut_model(
    const NSA1SceneObject *scene_objects, size_t object_count,
    const NSA1CutRequest *cut_request,
    NSA1SceneObject ***out_objects, size_t *out_object_count,
    char **out_error) {
    try {
        if (object_count == 0) {
            *out_objects = nullptr;
            *out_object_count = 0;
            return 0;
        }

        // Build a model from the scene objects
        Slic3r::Model model = build_model_from_objects(scene_objects, object_count);
        if (model.objects.empty()) {
            *out_objects = nullptr;
            *out_object_count = 0;
            return 0;
        }

        // Convert the cut plane from the request
        std::array<Slic3r::Vec3d, 4> plane;
        for (int i = 0; i < 4; ++i) {
            plane[i] = Slic3r::Vec3d(
                cut_request->plane_points[i].x,
                cut_request->plane_points[i].y,
                cut_request->plane_points[i].z);
        }

        // Collect cut results: for cut_mode 0 (both), we need both halves
        std::vector<Slic3r::ModelObject *> all_parts;
        if (cut_request->cut_mode == 0) {
            // Cut twice: once for lower, once for upper
            auto lower = model.objects.front()->cut(0, plane, Slic3r::ModelObjectCutAttribute::KeepLower);
            auto upper = model.objects.front()->cut(0, plane, Slic3r::ModelObjectCutAttribute::KeepUpper);
            for (auto *part : lower) all_parts.push_back(part);
            for (auto *part : upper) all_parts.push_back(part);
        } else {
            Slic3r::ModelObjectCutAttribute attribute = Slic3r::ModelObjectCutAttribute::KeepLower;
            if (cut_request->cut_mode == 2) attribute = Slic3r::ModelObjectCutAttribute::KeepUpper;
            auto parts = model.objects.front()->cut(0, plane, attribute);
            for (auto *part : parts) all_parts.push_back(part);
        }

        // Convert result to NSA1SceneObject array
        *out_object_count = all_parts.size();
        if (*out_object_count == 0) {
            *out_objects = nullptr;
            return 0;
        }

        *out_objects = static_cast<NSA1SceneObject **>(
            malloc(sizeof(NSA1SceneObject *) * *out_object_count));
        for (size_t i = 0; i < *out_object_count; ++i) {
            (*out_objects)[i] = scene_object_from_model_object(*all_parts[i]);
        }

        return 0;
    } catch (const std::exception &e) {
        *out_error = strdup(e.what());
        *out_objects = nullptr;
        *out_object_count = 0;
        return -1;
    } catch (...) {
        *out_error = strdup("unknown cut error");
        *out_objects = nullptr;
        *out_object_count = 0;
        return -1;
    }
}
Slic3r::Model build_model_from_objects(const NSA1SceneObject *objects, size_t object_count) {
    Slic3r::Model model;
    for (size_t i = 0; i < object_count; ++i) {
        const NSA1SceneObject &obj = objects[i];
        std::vector<Slic3r::Vec3f> vertices(obj.vertex_count);
        for (size_t v = 0; v < obj.vertex_count; ++v) {
            vertices[v] = Slic3r::Vec3f(obj.vertices[v * 3 + 0], obj.vertices[v * 3 + 1], obj.vertices[v * 3 + 2]);
        }
        std::vector<Slic3r::Vec3i> faces(obj.index_count / 3);
        for (size_t f = 0; f < faces.size(); ++f) {
            faces[f] = Slic3r::Vec3i(
                static_cast<int>(obj.indices[f * 3 + 0]),
                static_cast<int>(obj.indices[f * 3 + 1]),
                static_cast<int>(obj.indices[f * 3 + 2]));
        }
        Slic3r::TriangleMesh mesh(vertices, faces);

        Slic3r::ModelObject *model_object = model.add_object();
        model_object->add_volume(std::move(mesh), Slic3r::ModelVolumeType::MODEL_PART, /*modify_to_center_geometry=*/false);
        Slic3r::ModelInstance *instance = model_object->add_instance();
        Slic3r::Transform3d trafo;
        trafo.matrix() = Eigen::Map<const Eigen::Matrix4d>(obj.matrix16);
        instance->set_transformation(Slic3r::Geometry::Transformation(trafo));
    }
    return model;
}

char *copy_c_string(const std::string &s) {
    char *out = new char[s.size() + 1];
    std::memcpy(out, s.c_str(), s.size() + 1);
    return out;
}

// Upstream bug workaround: `FullPrintConfig::defaults()` clones each
// option's raw `ConfigOptionDef::default_value`, but for `coEnum`/
// `coEnums` options that default value was constructed without its
// `keys_map` (only `ConfigOptionDef::create_default_option()` wires that
// up). Any such option — most of `full_print_config()`'s seeded set — has
// a null `keys_map` and segfaults the moment anything calls
// `deserialize()`/`serialize()` on it. Repair every such option in place.
// Shared by every path that seeds a config via `full_print_config()`
// (`build_full_config`) or hands one back out via `serialize()`
// (`nsa1_load_3mf_config`, defensively).
void repair_enum_keys_map(Slic3r::DynamicPrintConfig &config) {
    for (const std::string &key : config.keys()) {
        const Slic3r::ConfigOptionDef *optdef = config.def()->get(key);
        if (optdef == nullptr || optdef->enum_keys_map == nullptr) {
            continue;
        }
        Slic3r::ConfigOption *opt = config.option(key);
        if (auto *e = dynamic_cast<Slic3r::ConfigOptionEnumGeneric *>(opt)) {
            if (e->keys_map == nullptr) e->keys_map = optdef->enum_keys_map;
        } else if (auto *es = dynamic_cast<Slic3r::ConfigOptionEnumsGeneric *>(opt)) {
            if (es->keys_map == nullptr) es->keys_map = optdef->enum_keys_map;
        } else if (auto *esn = dynamic_cast<Slic3r::ConfigOptionEnumsGenericNullable *>(opt)) {
            if (esn->keys_map == nullptr) esn->keys_map = optdef->enum_keys_map;
        }
    }
}

// Seeds every `FullPrintConfig` default (nozzle/bed/process/filament
// option definitions), repairs the null-`keys_map` bug above, then
// overlays `config_entries` on top — the same shape `BambuProfileLoader`
// resolves (SPEC.md A1-only scope) plus any P3-003 UI overrides, reusing
// libslic3r's own config system rather than reimplementing option typing/
// validation. Shared by `nsa1_slice_to_gcode` (slicing) and
// `nsa1_store_3mf` (P3-003 settings persistence) so both seed/repair/
// overlay identically.
Slic3r::DynamicPrintConfig build_full_config(const NSA1ConfigEntry *config_entries, size_t config_entry_count) {
    Slic3r::DynamicPrintConfig config = Slic3r::DynamicPrintConfig::full_print_config();
    repair_enum_keys_map(config);

    Slic3r::ConfigSubstitutionContext substitutions(Slic3r::ForwardCompatibilitySubstitutionRule::Disable);
    for (size_t i = 0; i < config_entry_count; ++i) {
        const std::string key = config_entries[i].key;
        if (config.def()->get(key) == nullptr) {
            continue; // profile metadata (name/inherits/setting_id/…), not a real engine option
        }
        config.set_deserialize(key, config_entries[i].value, substitutions);
    }
    config.normalize_fdm();
    return config;
}
} // namespace

extern "C" int nsa1_store_3mf(
    const char *path, const NSA1SceneObject *objects, size_t object_count,
    const NSA1ConfigEntry *config_entries, size_t config_entry_count) {
    Slic3r::Model model = build_model_from_objects(objects, object_count);
    Slic3r::DynamicPrintConfig config = build_full_config(config_entries, config_entry_count);
    return Slic3r::store_3mf(path, &model, &config, /*fullpath_sources=*/true) ? 0 : -1;
}

extern "C" NSA1ConfigEntry *nsa1_load_3mf_config(const char *path, size_t *out_count) {
    *out_count = 0;

    // `Slic3r::load_3mf`'s own `DynamicPrintConfig&` out-param is always
    // left empty: the archive-entry case that would populate it
    // (`PRINT_CONFIG_FILE`/"Metadata/Slic3r_PE.config", written by
    // `nsa1_store_3mf` via `store_3mf`'s `_add_print_config_file_to_archive`)
    // is inside a `/* ... */`-commented-out block in `3mf.cpp`'s importer
    // — upstream write path is live, the matching read path isn't (BambuStudio's
    // own GUI apparently restores project settings through its separate
    // `src/slic3r/GUI` preset-bundle layer instead, which isn't vendored
    // here — ARCHITECTURE.md P0-005). So this bridge reads the same
    // archive entry directly via the same `miniz_extension.hpp` helpers
    // `3mf.cpp` itself uses, then parses it with the real engine's own
    // `ConfigBase::load_from_gcode_string_legacy` (the format
    // `_add_print_config_file_to_archive` writes — semicolon-commented
    // `key = value` lines — is the same one that parser is built to read,
    // not a new format invented here).
    mz_zip_archive archive;
    mz_zip_zero_struct(&archive);
    if (!Slic3r::open_zip_reader(&archive, path)) {
        return nullptr;
    }
    int file_index = mz_zip_reader_locate_file(&archive, "Metadata/Slic3r_PE.config", nullptr, 0);
    if (file_index < 0) {
        Slic3r::close_zip_reader(&archive);
        return nullptr; // no embedded config (e.g. a pre-P3-003 project)
    }
    mz_zip_archive_file_stat stat;
    if (!mz_zip_reader_file_stat(&archive, file_index, &stat)) {
        Slic3r::close_zip_reader(&archive);
        return nullptr;
    }
    std::string buffer(static_cast<size_t>(stat.m_uncomp_size), '\0');
    mz_bool extracted = mz_zip_reader_extract_file_to_mem(&archive, stat.m_filename, buffer.data(), buffer.size(), 0);
    Slic3r::close_zip_reader(&archive);
    if (!extracted) {
        return nullptr;
    }

    Slic3r::DynamicPrintConfig config;
    Slic3r::ConfigSubstitutionContext substitutions(Slic3r::ForwardCompatibilitySubstitutionRule::Disable);
    Slic3r::ConfigBase::load_from_gcode_string_legacy(config, buffer.c_str(), substitutions);
    repair_enum_keys_map(config); // defensive: see repair_enum_keys_map's comment

    std::vector<std::string> keys = config.keys();
    if (keys.empty()) {
        return nullptr;
    }
    auto *entries = new NSA1ConfigEntry[keys.size()];
    size_t n = 0;
    for (const std::string &key : keys) {
        const Slic3r::ConfigOption *opt = config.option(key);
        if (opt == nullptr) {
            continue;
        }
        entries[n].key = copy_c_string(key);
        entries[n].value = copy_c_string(opt->serialize());
        ++n;
    }
    *out_count = n;
    return entries;
}

extern "C" void nsa1_free_config_entries(NSA1ConfigEntry *entries, size_t count) {
    if (!entries) return;
    for (size_t i = 0; i < count; ++i) {
        delete[] entries[i].key;
        delete[] entries[i].value;
    }
    delete[] entries;
}

extern "C" int nsa1_slice_to_gcode(
    const NSA1SceneObject *objects, size_t object_count,
    const NSA1ConfigEntry *config_entries, size_t config_entry_count,
    const char *out_gcode_path,
    NSA1Toolpath **out_toolpath,
    char **out_error) {
    *out_error = nullptr;
    if (out_toolpath != nullptr) {
        *out_toolpath = nullptr;
    }
    try {
        if (object_count == 0) {
            *out_error = copy_c_string("no objects to slice");
            return -1;
        }
        Slic3r::Model model = build_model_from_objects(objects, object_count);
        Slic3r::DynamicPrintConfig config = build_full_config(config_entries, config_entry_count);

        Slic3r::Print print;
        print.apply(model, config);
        Slic3r::StringObjectException err = print.validate();
        if (!err.string.empty()) {
            *out_error = copy_c_string(err.string);
            return -1;
        }
        print.process();
        Slic3r::GCodeProcessorResult result;
        print.export_gcode(out_gcode_path, &result);

        if (out_toolpath != nullptr) {
            // `result.moves` is the engine's own per-move toolpath data
            // (P1-009) — the same data BambuStudio's own G-code preview
            // consumes. Each `Extrude`/`Travel` move's `position` is that
            // move's *end* point; the segment's start is the previous
            // move's end point (consecutive-vertex polyline, matching
            // upstream's own preview generator convention).
            std::vector<NSA1ToolpathSegment> segments;
            segments.reserve(result.moves.size());
            bool have_prev = false;
            Slic3r::Vec3f prev{0, 0, 0};
            for (const auto &move : result.moves) {
                const bool is_extrude = move.type == Slic3r::EMoveType::Extrude;
                const bool is_travel = move.type == Slic3r::EMoveType::Travel;
                if (!is_extrude && !is_travel) {
                    have_prev = false; // break the polyline on non-move events (retract/seam/tool change/…)
                    continue;
                }
                if (have_prev) {
                    NSA1ToolpathSegment seg{};
                    seg.start_x = prev.x();
                    seg.start_y = prev.y();
                    seg.start_z = prev.z();
                    seg.end_x = move.position.x();
                    seg.end_y = move.position.y();
                    seg.end_z = move.position.z();
                    seg.width = move.width;
                    seg.height = move.height;
                    seg.feedrate = move.feedrate;
                    seg.temperature = move.temperature;
                    seg.layer_duration = move.layer_duration;
                    seg.extruder_id = move.extruder_id;
                    seg.extrusion_role = static_cast<float>(move.extrusion_role);
                    seg.is_travel = is_travel ? 1 : 0;
                    segments.push_back(seg);
                }
                prev = move.position;
                have_prev = true;
            }
            auto *out = new NSA1ToolpathSegment[segments.size()];
            std::copy(segments.begin(), segments.end(), out);
            auto *toolpath = new NSA1Toolpath();
            toolpath->segments = out;
            toolpath->segment_count = segments.size();
            *out_toolpath = toolpath;
        }
        return 0;
    } catch (const std::exception &e) {
        *out_error = copy_c_string(e.what());
        return -1;
    }
}

extern "C" int nsa1_slice_to_gcode_with_statistics(
    const NSA1SceneObject *objects, size_t object_count,
    const NSA1ConfigEntry *config_entries, size_t config_entry_count,
    const char *out_gcode_path,
    NSA1Toolpath **out_toolpath,
    NSA1EstimatedStatistics **out_statistics,
    char **out_error) {
    *out_error = nullptr;
    if (out_toolpath != nullptr) {
        *out_toolpath = nullptr;
    }
    if (out_statistics != nullptr) {
        *out_statistics = nullptr;
    }
    try {
        if (object_count == 0) {
            *out_error = copy_c_string("no objects to slice");
            return -1;
        }
        Slic3r::Model model = build_model_from_objects(objects, object_count);
        Slic3r::DynamicPrintConfig config = build_full_config(config_entries, config_entry_count);

        Slic3r::Print print;
        print.apply(model, config);
        Slic3r::StringObjectException err = print.validate();
        if (!err.string.empty()) {
            *out_error = copy_c_string(err.string);
            return -1;
        }
        print.process();
        Slic3r::GCodeProcessorResult result;
        print.export_gcode(out_gcode_path, &result);

        if (out_toolpath != nullptr) {
            std::vector<NSA1ToolpathSegment> segments;
            segments.reserve(result.moves.size());
            bool have_prev = false;
            Slic3r::Vec3f prev{0, 0, 0};
            for (const auto &move : result.moves) {
                const bool is_extrude = move.type == Slic3r::EMoveType::Extrude;
                const bool is_travel = move.type == Slic3r::EMoveType::Travel;
                if (!is_extrude && !is_travel) {
                    have_prev = false;
                    continue;
                }
                if (have_prev) {
                    NSA1ToolpathSegment seg{};
                    seg.start_x = prev.x();
                    seg.start_y = prev.y();
                    seg.start_z = prev.z();
                    seg.end_x = move.position.x();
                    seg.end_y = move.position.y();
                    seg.end_z = move.position.z();
                    seg.width = move.width;
                    seg.height = move.height;
                    seg.is_travel = is_travel ? 1 : 0;
                    segments.push_back(seg);
                }
                prev = move.position;
                have_prev = true;
            }
            auto *out = new NSA1ToolpathSegment[segments.size()];
            std::copy(segments.begin(), segments.end(), out);
            // P1-011: surface the engine's own estimated print statistics.
            if (out_statistics != nullptr) {
                const auto &stats = result.print_statistics;
                auto *out = new NSA1EstimatedStatistics();
                out->normal_time = (double)stats.modes[0].time;
                out->normal_prepare_time = (double)stats.modes[0].prepare_time;
                out->stealth_time = (double)stats.modes[1].time;
                out->stealth_prepare_time = (double)stats.modes[1].prepare_time;
                out->total_filament_load_time = 0.0;
                out->total_filament_unload_time = 0.0;
                out->total_tool_change_time = 0.0;
                out->total_travel_distance = 0.0;
                out->total_filament_changes = (int)stats.total_filament_changes;
                out->total_flush_filament_changes = (int)stats.total_flush_filament_changes;
                out->total_extruder_changes = 0;
                out->total_travel_moves = 0;
                out->total_seam_gap_distance = 0.0;
                out->total_seam_scarf_distance = 0.0;
                out->extruder_count = stats.total_volumes_per_extruder.size();
                if (!out->extruder_count) {
                    out->extruder_volumes_mm3 = nullptr;
                } else {
                    auto *ev = new double[out->extruder_count];
                    size_t i = 0;
                    for (const auto &kv : stats.total_volumes_per_extruder) {
                        ev[i++] = kv.second;
                    }
                    out->extruder_volumes_mm3 = ev;
                }
                out->role_count = stats.used_filaments_per_role.size();
                if (!out->role_count) {
                    out->role_lengths_mm = nullptr;
                    out->role_volumes_mm3 = nullptr;
                } else {
                    auto *rl = new double[out->role_count];
                    auto *rv = new double[out->role_count];
                    size_t i = 0;
                    for (const auto &kv : stats.used_filaments_per_role) {
                        rl[i] = kv.second.first;
                        rv[i] = kv.second.second;
                        i++;
                    }
                    out->role_lengths_mm = rl;
                    out->role_volumes_mm3 = rv;
                }
                *out_statistics = out;
            }
        }
    } catch (const std::exception &e) {
        *out_error = copy_c_string(e.what());
        return -1;
    }
}

extern "C" void nsa1_free_toolpath(NSA1Toolpath *toolpath) {
    if (!toolpath) return;
    delete[] toolpath->segments;
    delete toolpath;
}

extern "C" void nsa1_free_estimated_statistics(NSA1EstimatedStatistics *stats) {
    if (!stats) return;
    if (stats->extruder_volumes_mm3) delete[] stats->extruder_volumes_mm3;
    if (stats->role_lengths_mm) delete[] stats->role_lengths_mm;
    if (stats->role_volumes_mm3) delete[] stats->role_volumes_mm3;
    delete stats;
}

extern "C" int nsa1_generate_calibration_gcode(
    const NSA1CalibrationRequest *request,
    const char *out_gcode_path,
    NSA1CalibrationResult **out_result,
    char **out_error) {
    if (out_result) *out_result = nullptr;
    if (out_error) *out_error = nullptr;
    auto fail = [&](const std::string &message) {
        if (out_error) *out_error = copy_c_string(message);
        return -1;
    };
    if (!request || !out_gcode_path || !out_result || !out_error)
        return fail("invalid calibration request");
    const bool pressure_advance = request->workflow == NSA1_CALIBRATION_PRESSURE_ADVANCE;
    const bool temperature = request->workflow == NSA1_CALIBRATION_TEMPERATURE;
    const bool retraction = request->workflow == NSA1_CALIBRATION_RETRACTION;
    const bool max_volumetric_speed = request->workflow == NSA1_CALIBRATION_MAX_VOLUMETRIC_SPEED;
    if (!pressure_advance && !temperature && !retraction && !max_volumetric_speed &&
        request->workflow != NSA1_CALIBRATION_FLOW_RATE)
        return fail("unsupported calibration workflow");
    if (!request->resource_path)
        return fail("missing calibration resource path");
    std::error_code error;
    if (!std::filesystem::is_regular_file(request->resource_path, error))
        return fail("missing calibration resource");

    const size_t block_count = request->step > 0 && std::isfinite(request->step)
        ? static_cast<size_t>(std::floor(std::abs(request->end - request->start) / request->step + 1e-9)) + 1
        : 0;
    if (pressure_advance || temperature || retraction || max_volumetric_speed) {
        if (!std::isfinite(request->start) || !std::isfinite(request->end) ||
            !std::isfinite(request->step) || request->step <= 0 ||
            block_count == 0 || block_count > 200)
            return fail("invalid calibration range");
    }

    // Pass 1 is the fixed upstream resource: flow ratios 0.80 through 1.20.
    constexpr double first_ratio = 0.8;
    constexpr double last_ratio = 1.2;
    constexpr double ratio_step = 0.05;
    if (!pressure_advance && !temperature && !retraction && !max_volumetric_speed && (request->step <= 0 || request->start < first_ratio - 1e-6 ||
        request->end > last_ratio + 1e-6 ||
        std::abs(request->start - first_ratio) > 1e-6 ||
        std::abs(request->end - last_ratio) > 1e-6 ||
        std::abs(request->step - ratio_step) > 1e-6))
        return fail("unsupported flow-rate calibration range");

    try {
        Slic3r::Model model;
        if (pressure_advance || temperature || retraction) {
            Slic3r::TriangleMesh mesh;
            if (!mesh.ReadSTLFile(request->resource_path, /*repair=*/false))
                return fail("failed to load calibration resource");
            Slic3r::ModelObject *object = model.add_object();
            object->add_volume(std::move(mesh), Slic3r::ModelVolumeType::MODEL_PART, /*modify_to_center_geometry=*/false);
            object->add_instance();
        } else if (max_volumetric_speed) {
            bool cancelled = false;
            Slic3r::Step step(std::string(request->resource_path));
            if (step.load() != Slic3r::Step::Step_Status::LOAD_SUCCESS ||
                step.mesh(&model, cancelled, false) != Slic3r::Step::Step_Status::MESH_SUCCESS ||
                cancelled || model.objects.empty())
                return fail("failed to load volumetric-speed calibration resource");
        } else if (!load_3mf_model(request->resource_path, model)) {
            return fail("failed to load calibration resource");
        }
        if (temperature && !model.objects.empty()) {
            const auto cut_upper_count = std::lround((350.0 - request->start) / 5.0 + 1.0);
            if (cut_upper_count > 0) {
                const double height = cut_upper_count * 10.0 + EPSILON;
                if (height < model.objects.front()->bounding_box().size().z())
                    cut_model_at_height(model, height, Slic3r::ModelObjectCutAttribute::KeepLower);
            }
            if (!model.objects.empty()) {
                const auto cut_bottom_count = std::lround((350.0 - request->end) / 5.0);
                if (cut_bottom_count > 0) {
                    const double height = cut_bottom_count * 10.0 + EPSILON;
                    if (height < model.objects.front()->bounding_box().size().z())
                        cut_model_at_height(model, height, Slic3r::ModelObjectCutAttribute::KeepUpper);
                }
            }
        }
        Slic3r::DynamicPrintConfig config =
            build_full_config(request->config_entries, request->config_entry_count);

        const auto *nozzle = config.option<Slic3r::ConfigOptionFloatsNullable>("nozzle_diameter");
        const float nozzle_diameter = nozzle && !nozzle->values.empty() ? nozzle->values[0] : 0.4f;
        const double layer_height = nozzle_diameter / 2.0;
        const auto *initial = config.option<Slic3r::ConfigOptionFloat>("initial_layer_print_height");
        const double first_layer_height = std::max(initial ? initial->value : layer_height, layer_height);
        const double zscale = (first_layer_height + 6.0 * layer_height) / 1.4;
        const float xy_scale = nozzle_diameter / 0.6f;
        for (auto *object : model.objects) {
            if (object->instances.empty())
                object->add_instance();
        }
        double max_vol_speed_mm3_per_mm = 1.0;
        if (max_volumetric_speed) {
            // Upstream Plater::calib_max_vol_speed fits the STEP tower to
            // the bed width only (X axis) — a different rule from the
            // flow-rate tower's XY+Z scale above, which targets a
            // different model entirely and would distort this one.
            Slic3r::ModelObject *object = model.objects.empty() ? nullptr : model.objects.front();
            if (object == nullptr) return fail("volumetric-speed calibration resource has no objects");
            const auto *bed_shape = config.option<Slic3r::ConfigOptionPoints>("printable_area");
            if (bed_shape && !bed_shape->values.empty()) {
                Slic3r::BoundingBoxf bed_ext;
                for (const auto &pt : bed_shape->values) bed_ext.merge(pt);
                const double obj_x = object->bounding_box().size().x();
                if (obj_x > 0.0) {
                    const double scale_obj = (bed_ext.size().x() - 10.0) / obj_x;
                    if (scale_obj > 0.0 && scale_obj < 1.0) object->scale(scale_obj, 1.0, 1.0);
                }
            }
            object->ensure_on_bed();
            // Matches upstream's own calibration-tower settings exactly:
            // single wall, no infill/top shell, spiral vase — every move in
            // the resulting G-code is the calibrated speed, not diluted by
            // infill/solid-fill moves running at unrelated speeds.
            object->config.set_key_value("wall_loops", new Slic3r::ConfigOptionInt(1));
            object->config.set_key_value("top_shell_layers", new Slic3r::ConfigOptionInt(0));
            object->config.set_key_value("bottom_shell_layers", new Slic3r::ConfigOptionInt(1));
            object->config.set_key_value("sparse_infill_density", new Slic3r::ConfigOptionPercent(0));
            object->config.set_key_value("brim_type", new Slic3r::ConfigOptionEnum<Slic3r::BrimType>(Slic3r::BrimType::btOuterAndInner));
            object->config.set_key_value("brim_width", new Slic3r::ConfigOptionFloat(3.0));
            object->config.set_key_value("brim_object_gap", new Slic3r::ConfigOptionFloat(0.0));

            // These exact values (not the generic layer_height above) are
            // what the requested mm3/s values are converted against below
            // — they must be the values actually applied to the print, or
            // the emitted speed will not match what was requested.
            const double line_width = nozzle_diameter * 1.75;
            const double tower_layer_height = nozzle_diameter * 0.8;
            config.set_key_value("outer_wall_line_width", new Slic3r::ConfigOptionFloat(line_width));
            config.set_key_value("layer_height", new Slic3r::ConfigOptionFloat(tower_layer_height));
            config.set_key_value("initial_layer_print_height", new Slic3r::ConfigOptionFloat(tower_layer_height));
            // `spiral_mode` only exists on the global print config (not
            // PrintObjectConfig/PrintRegionConfig) — `print.apply()` would
            // silently discard it from `object->config`.
            config.set_key_value("spiral_mode", new Slic3r::ConfigOptionBool(true));
            // Disable the two heuristics that would otherwise auto-reduce
            // speed (overhang/height slowdown, cooling slowdown) and
            // un-clamp the filament's own max-volumetric-speed cap — any
            // of these left in place would silently cap the emitted speed
            // below the requested calibration value.
            config.set_key_value("enable_overhang_speed", new Slic3r::ConfigOptionBoolsNullable(1, false));
            config.set_key_value("enable_height_slowdown", new Slic3r::ConfigOptionBoolsNullable(1, false));
            config.set_key_value("filament_max_volumetric_speed", new Slic3r::ConfigOptionFloatsNullable(1, 200.0));
            config.set_key_value("slow_down_layer_time", new Slic3r::ConfigOptionInts{0});

            // Matches upstream exactly (Plater.cpp calib_max_vol_speed):
            // the actual material volume per mm of travel is the geometric
            // cross-section times the filament's own flow ratio, not the
            // geometric cross-section alone.
            const auto *flow_ratio = config.option<Slic3r::ConfigOptionFloatsNullable>("filament_flow_ratio");
            const double flow_ratio_value = flow_ratio && !flow_ratio->values.empty() ? flow_ratio->get_at(0) : 1.0;
            max_vol_speed_mm3_per_mm =
                Slic3r::Flow(line_width, tower_layer_height, nozzle_diameter).mm3_per_mm() * flow_ratio_value;

            // Printer-safety: cut the tower close to the height the
            // requested mm3/s range needs (upstream's own formula,
            // including its deliberate +1 mm3/s of ramp slack above the
            // requested end value — Plater.cpp/CalibUtils.cpp both use it
            // unmodified), so the emitted G-code never travels anywhere
            // near the full height of the bundled STEP resource.
            const double requested_height = (request->end - request->start + 1.0) / request->step;
            if (requested_height > 0.0 && requested_height < object->bounding_box().size().z())
                cut_model_at_height(model, requested_height, Slic3r::ModelObjectCutAttribute::KeepLower);
        } else {
        for (auto *object : model.objects) {
            if (xy_scale > 1.2f) object->scale(xy_scale, xy_scale, zscale);
            else object->scale(1.0, 1.0, zscale);
            object->ensure_on_bed();
            object->config.set_key_value("wall_loops", new Slic3r::ConfigOptionInt(retraction ? 2 : 3));
            object->config.set_key_value("sparse_infill_density", new Slic3r::ConfigOptionPercent(retraction ? 0 : 35));
            object->config.set_key_value("bottom_shell_layers", new Slic3r::ConfigOptionInt(retraction ? 3 : 1));
            object->config.set_key_value("top_shell_layers", new Slic3r::ConfigOptionInt(retraction ? 0 : 5));
            object->config.set_key_value("detect_thin_wall", new Slic3r::ConfigOptionBool(!retraction));
            if (retraction) {
                object->config.set_key_value("initial_layer_print_height", new Slic3r::ConfigOptionFloat(0.2));
                object->config.set_key_value("layer_height", new Slic3r::ConfigOptionFloat(0.2));
            }
            if (temperature) {
                const int start_temperature = static_cast<int>(std::lround(request->start));
                config.set_key_value("nozzle_temperature_initial_layer", new Slic3r::ConfigOptionIntsNullable(1, start_temperature));
                config.set_key_value("nozzle_temperature", new Slic3r::ConfigOptionIntsNullable(1, start_temperature));
                object->config.set_key_value("brim_type", new Slic3r::ConfigOptionEnum<Slic3r::BrimType>(Slic3r::BrimType::btOuterOnly));
                object->config.set_key_value("brim_width", new Slic3r::ConfigOptionFloat(5.0));
                object->config.set_key_value("brim_object_gap", new Slic3r::ConfigOptionFloat(0.0));
            } else if (!pressure_advance && !retraction) {
                std::string name = object->name;
                if (name.rfind("flowrate_", 0) != 0) return fail("invalid flow-rate calibration resource");
                name.erase(0, 9);
                if (!name.empty() && name[0] == 'm') name[0] = '-';
                const double ratio = 1.0 + std::stod(name) / 100.0;
                object->config.set_key_value("print_flow_ratio", new Slic3r::ConfigOptionFloat(ratio));
            }
        }
        }
        if (pressure_advance) {
            Slic3r::Calib_Params params;
            params.start = request->start;
            params.end = request->end;
            params.step = request->step;
            params.mode = Slic3r::CalibMode::Calib_PA_Pattern;
            model.calib_pa_pattern = std::make_unique<Slic3r::CalibPressureAdvancePattern>(
                params, config, true, model, Slic3r::Vec3d::Zero());
            model.calib_pa_pattern->generate_custom_gcodes(config, true, model, Slic3r::Vec3d::Zero());
        }
        if (!max_volumetric_speed) {
            config.set_key_value("layer_height", new Slic3r::ConfigOptionFloat(layer_height));
            config.set_key_value("initial_layer_print_height", new Slic3r::ConfigOptionFloat(first_layer_height));
        }
        config.set_key_value("reduce_crossing_wall", new Slic3r::ConfigOptionBool(true));
        config.set_key_value("enable_wrapping_detection", new Slic3r::ConfigOptionBool(false));

        Slic3r::Print print;
        print.apply(model, config);
        if (retraction) {
            Slic3r::Calib_Params params;
            params.start = request->start;
            params.end = request->end;
            params.step = request->step;
            params.mode = Slic3r::CalibMode::Calib_Retraction_tower;
            print.set_calib_params(params);
        }
        if (temperature) {
            Slic3r::Calib_Params params;
            params.start = request->start;
            params.end = request->end;
            params.step = request->step;
            params.mode = Slic3r::CalibMode::Calib_Temp_Tower;
            print.set_calib_params(params);
        }
        if (max_volumetric_speed) {
            Slic3r::Calib_Params params;
            params.start = request->start / max_vol_speed_mm3_per_mm;
            params.end = request->end / max_vol_speed_mm3_per_mm;
            params.step = request->step / max_vol_speed_mm3_per_mm;
            params.mode = Slic3r::CalibMode::Calib_Vol_speed_Tower;
            print.set_calib_params(params);
        }
        Slic3r::StringObjectException validation = print.validate();
        if (!validation.string.empty()) return fail(validation.string);
        print.process();
        Slic3r::GCodeProcessorResult engine_result;
        print.export_gcode(out_gcode_path, &engine_result);

        std::vector<NSA1ToolpathSegment> segments;
        segments.reserve(engine_result.moves.size());
        bool have_prev = false;
        Slic3r::Vec3f prev{0, 0, 0};
        for (const auto &move : engine_result.moves) {
            const bool extrude = move.type == Slic3r::EMoveType::Extrude;
            const bool travel = move.type == Slic3r::EMoveType::Travel;
            if (!extrude && !travel) { have_prev = false; continue; }
            if (have_prev) {
                NSA1ToolpathSegment segment{};
                segment.start_x = prev.x(); segment.start_y = prev.y(); segment.start_z = prev.z();
                segment.end_x = move.position.x(); segment.end_y = move.position.y(); segment.end_z = move.position.z();
                segment.width = move.width; segment.height = move.height; segment.is_travel = travel ? 1 : 0;
                segments.push_back(segment);
            }
            prev = move.position; have_prev = true;
        }
        auto segment_buffer = std::make_unique<NSA1ToolpathSegment[]>(segments.size());
        std::copy(segments.begin(), segments.end(), segment_buffer.get());
        auto toolpath = std::make_unique<NSA1Toolpath>(
            NSA1Toolpath{segment_buffer.get(), segments.size()}
        );
        const size_t result_block_count = pressure_advance || temperature || retraction || max_volumetric_speed ? block_count : 9;
        auto blocks = std::make_unique<NSA1CalibrationBlock[]>(result_block_count);
        for (size_t i = 0; i < result_block_count; ++i) {
            const double value = temperature
                ? request->start + (request->end >= request->start ? 1.0 : -1.0) * static_cast<double>(i) * request->step
                : pressure_advance || retraction || max_volumetric_speed ? request->start + static_cast<double>(i) * request->step
                                   : (80.0 + 5.0 * i) / 100.0;
            blocks[i] = NSA1CalibrationBlock{
                i,
                value,
                temperature ? static_cast<double>(i) * 10.0 : 0,
                temperature ? static_cast<double>(i + 1) * 10.0 : 0
            };
        }
        auto result = std::make_unique<NSA1CalibrationResult>(
            NSA1CalibrationResult{toolpath.get(), blocks.get(), result_block_count}
        );
        segment_buffer.release();
        toolpath.release();
        blocks.release();
        *out_result = result.release();
        return 0;
    } catch (const std::exception &e) {
        return fail(e.what());
    }
}

extern "C" void nsa1_free_calibration_result(NSA1CalibrationResult *result) {
    if (!result) return;
    nsa1_free_toolpath(result->toolpath);
    delete[] result->blocks;
    delete result;
}


extern "C" void nsa1_free_string(char *s) {
    delete[] s;
}
