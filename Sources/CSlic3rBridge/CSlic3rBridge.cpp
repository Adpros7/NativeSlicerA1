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
#include <cstring>

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

extern "C" int nsa1_store_3mf(const char *path, const NSA1SceneObject *objects, size_t object_count) {
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
    Slic3r::DynamicPrintConfig config;
    return Slic3r::store_3mf(path, &model, &config, /*fullpath_sources=*/true) ? 0 : -1;
}
