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
#include "libslic3r/Print.hpp"
#include "libslic3r/PrintConfig.hpp"
#include <cstring>
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
} // namespace

extern "C" int nsa1_store_3mf(const char *path, const NSA1SceneObject *objects, size_t object_count) {
    Slic3r::Model model = build_model_from_objects(objects, object_count);
    Slic3r::DynamicPrintConfig config;
    return Slic3r::store_3mf(path, &model, &config, /*fullpath_sources=*/true) ? 0 : -1;
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

        // Seed every FullPrintConfig default (nozzle/bed/process/filament
        // option definitions), then overlay the resolved A1 profile fields
        // on top — the same shape BambuProfileLoader already resolves
        // (SPEC.md A1-only scope), reusing libslic3r's own config system
        // rather than reimplementing option typing/validation.
        Slic3r::DynamicPrintConfig config = Slic3r::DynamicPrintConfig::full_print_config();

        // Upstream bug workaround: `FullPrintConfig::defaults()` clones
        // each option's raw `ConfigOptionDef::default_value`, but for
        // `coEnum`/`coEnums` options that default value was constructed
        // without its `keys_map` (only `ConfigOptionDef::create_default_option()`
        // wires that up). Any such option — most of `full_print_config()`'s
        // seeded set — has a null `keys_map` and segfaults the moment
        // anything calls `deserialize()`/`serialize()` on it (overriding
        // it below, or the engine embedding it in the G-code header's
        // config block later). Repair every such option in place first.
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

        Slic3r::ConfigSubstitutionContext substitutions(Slic3r::ForwardCompatibilitySubstitutionRule::Disable);
        for (size_t i = 0; i < config_entry_count; ++i) {
            const std::string key = config_entries[i].key;
            if (config.def()->get(key) == nullptr) {
                continue; // profile metadata (name/inherits/setting_id/…), not a real engine option
            }
            config.set_deserialize(key, config_entries[i].value, substitutions);
        }

        config.normalize_fdm();

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

extern "C" void nsa1_free_toolpath(NSA1Toolpath *toolpath) {
    if (!toolpath) return;
    delete[] toolpath->segments;
    delete toolpath;
}


extern "C" void nsa1_free_string(char *s) {
    delete[] s;
}
