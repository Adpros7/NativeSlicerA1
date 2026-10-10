#ifndef CSLIC3R_BRIDGE_H
#define CSLIC3R_BRIDGE_H

#include <stdint.h>

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

#ifdef __cplusplus
}
#endif

#endif
