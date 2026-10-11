#!/bin/bash
# Builds the real BambuStudio libslic3r slicing engine as a set of static
# libraries this project links against (see ARCHITECTURE.md, RESEARCH.md
# P0-001..P0-004). Output lands in vendor/bambustudio-build/ (gitignored) -
# Package.swift's CSlic3rBridge target expects it there.
#
# One-time setup cost: clones BambuStudio (AGPLv3), builds ~25 third-party
# C++ dependencies from source (Boost, CGAL, OpenCV, OCCT, Assimp, TBB,
# wxWidgets, FFmpeg, etc. - wxWidgets/FFmpeg aren't needed by libslic3r
# itself but are built as part of BambuStudio's single `deps` CMake
# target; splitting them out is tracked as a follow-up, not required for
# correctness), then builds libslic3r + bridges 2 BambuStudio
# architecture-leak files (see note below).
#
# Usage: Scripts/build-libslic3r.sh
# Idempotent: skips steps whose output already exists.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/vendor"
BAMBU="$VENDOR/BambuStudio"
DEPLOYMENT_TARGET="14.0"   # must match Package.swift's .macOS(.v14)
ARCH="arm64"

mkdir -p "$VENDOR"

if [ ! -d "$BAMBU" ]; then
    echo "==> Cloning BambuStudio (AGPLv3)..."
    git clone --depth 1 https://github.com/bambulab/BambuStudio.git "$BAMBU"
fi

# Upstream's deps/CMakeLists.txt FORCEs CMAKE_OSX_DEPLOYMENT_TARGET to
# 10.15, which current Xcode/libc++ rejects ("no longer supported by
# libc++"). Patch it to match our own deployment target.
if ! grep -q "\"$DEPLOYMENT_TARGET\" CACHE STRING \"Minimum OS X deployment version\" FORCE" "$BAMBU/deps/CMakeLists.txt"; then
    echo "==> Patching deps/CMakeLists.txt deployment target -> $DEPLOYMENT_TARGET"
    sed -i '' "s/set(CMAKE_OSX_DEPLOYMENT_TARGET \"[0-9.]*\" CACHE STRING \"Minimum OS X deployment version\" FORCE)/set(CMAKE_OSX_DEPLOYMENT_TARGET \"$DEPLOYMENT_TARGET\" CACHE STRING \"Minimum OS X deployment version\" FORCE)/" "$BAMBU/deps/CMakeLists.txt"
fi

# zstd: the one dependency this project doesn't build from source. Boost's
# `iostreams` component and Blosc (an OpenVDB codec dependency) both
# optionally link zstd if CMake finds it at configure time; until now that
# meant whatever's in /opt/homebrew, a machine-specific dylib that tracks
# the host's own macOS SDK rather than our $DEPLOYMENT_TARGET - the source
# of "building for macOS-14.0, but linking with dylib ... built for newer
# version 26.0". Build it the same way as the other ~25 deps instead, so
# it's reproducible and matches our deployment target. (Upstream's own
# deps/CMakeLists.txt doesn't vendor zstd either - its comment at
# CMakeLists.txt:525-527 says "on Windows/macOS zstd comes from the
# prebuilt deps / vcpkg", i.e. a separately-fetched official deps bundle
# this from-source build doesn't use.)
ZSTD_DIR="$BAMBU/deps/ZSTD"
mkdir -p "$ZSTD_DIR"
cat > "$ZSTD_DIR/ZSTD.cmake" <<'EOF'
bambustudio_add_cmake_project(ZSTD
    URL https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz
    URL_HASH SHA256=eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3
    SOURCE_SUBDIR build/cmake
    CMAKE_ARGS
        -DZSTD_BUILD_SHARED:BOOL=OFF
        -DZSTD_BUILD_STATIC:BOOL=ON
        -DZSTD_BUILD_PROGRAMS:BOOL=OFF
        -DZSTD_BUILD_TESTS:BOOL=OFF
)
EOF

if ! grep -q "include(ZSTD/ZSTD.cmake)" "$BAMBU/deps/CMakeLists.txt"; then
    echo "==> Wiring project-local ZSTD dependency into deps/CMakeLists.txt"
    sed -i '' '/^set(DEP_Boost_COMPONENTS /i\
set(ZSTD_PKG "")\
include(ZSTD/ZSTD.cmake)\
set(ZSTD_PKG dep_ZSTD)
' "$BAMBU/deps/CMakeLists.txt"
fi

if ! grep -q 'DEPENDS ${ZSTD_PKG}' "$BAMBU/deps/Boost/Boost.cmake"; then
    echo "==> Making Boost depend on project-local ZSTD"
    sed -i '' '/^bambustudio_add_cmake_project(Boost$/a\
    DEPENDS ${ZSTD_PKG}
' "$BAMBU/deps/Boost/Boost.cmake"
fi

if ! grep -q 'DEPENDS ${ZLIB_PKG} ${ZSTD_PKG}' "$BAMBU/deps/Blosc/Blosc.cmake"; then
    echo "==> Making Blosc depend on project-local ZSTD"
    sed -i '' 's/^    DEPENDS \${ZLIB_PKG}$/    DEPENDS ${ZLIB_PKG} ${ZSTD_PKG}/' "$BAMBU/deps/Blosc/Blosc.cmake"
fi

command -v ninja >/dev/null || { echo "Install ninja: brew install ninja"; exit 1; }

DEPS_BUILD="$BAMBU/deps/build/$ARCH"
DEPS_INSTALL="$DEPS_BUILD/BambuStudio_deps"

if [ ! -d "$DEPS_INSTALL/usr/local/lib" ]; then
    echo "==> Building third-party dependencies (this takes a while)..."
    mkdir -p "$DEPS_INSTALL"
    (cd "$DEPS_BUILD" && cmake "$BAMBU/deps" \
        -G Ninja \
        -DDESTDIR="$DEPS_INSTALL" \
        -DOPENSSL_ARCH="darwin64-$ARCH-cc" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET")
    (cd "$DEPS_BUILD" && cmake --build . --parallel --config Release --target deps)
fi

# Migration path for checkouts where deps were already built before the
# ZSTD wiring above existed: force just Boost and Blosc to reconfigure and
# relink against the new project-local zstd (their cached CMakeCache.txt
# would otherwise keep resolving Homebrew's copy). Leaves the other ~23
# already-built deps untouched.
if [ ! -f "$DEPS_INSTALL/usr/local/lib/libzstd.a" ]; then
    echo "==> Rebuilding Boost/Blosc against project-local ZSTD..."
    rm -rf "$DEPS_BUILD/dep_Boost-prefix" "$DEPS_BUILD/dep_Blosc-prefix"
    (cd "$DEPS_BUILD" && cmake --build . --config Release --target dep_ZSTD dep_Boost dep_Blosc)
fi

ENGINE_BUILD="$BAMBU/build/$ARCH"
mkdir -p "$ENGINE_BUILD"

# Thin CMake shim: links only `libslic3r` (not the wxWidgets GUI or the
# BambuStudio.app executable) plus two small upstream files that
# libslic3r's LogSink.cpp calls into but that actually live in the GUI
# layer (src/slic3r/Utils/{Http,BBLUtil}.cpp) - an upstream architecture
# leak, not something we introduced. See RESEARCH.md P1-003 notes.
BRIDGE_DIR="$BAMBU/nsa1_bridge"
mkdir -p "$BRIDGE_DIR"
cat > "$BRIDGE_DIR/CMakeLists.txt" <<'EOF'
find_package(OpenSSL REQUIRED)
find_package(CURL REQUIRED)
add_library(nsa1_libslic3r_leak_shim STATIC
    ${CMAKE_SOURCE_DIR}/src/slic3r/Utils/Http.cpp
    ${CMAKE_SOURCE_DIR}/src/slic3r/Utils/BBLUtil.cpp
)
target_include_directories(nsa1_libslic3r_leak_shim PRIVATE ${CMAKE_SOURCE_DIR}/src/slic3r)
target_link_libraries(nsa1_libslic3r_leak_shim PUBLIC libslic3r OpenSSL::Crypto OpenSSL::SSL CURL::libcurl)
EOF
if ! grep -q "nsa1_bridge" "$BAMBU/CMakeLists.txt"; then
    # Insert right after `add_subdirectory(src)` so the libslic3r target exists first.
    sed -i '' '/^add_subdirectory(src)$/a\
add_subdirectory(nsa1_bridge)
' "$BAMBU/CMakeLists.txt"
fi

echo "==> Configuring libslic3r..."
(cd "$ENGINE_BUILD" && cmake "$BAMBU" \
    -G Ninja \
    -DBBL_RELEASE_TO_PUBLIC=1 \
    -DBBL_INTERNAL_TESTING=0 \
    -DCMAKE_PREFIX_PATH="$DEPS_INSTALL/usr/local" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET")

echo "==> Building libslic3r + leak shim..."
(cd "$ENGINE_BUILD" && cmake --build . --config Release --target libslic3r nsa1_libslic3r_leak_shim)

echo "==> Done. Static libs under:"
echo "    $ENGINE_BUILD/src/libslic3r/"
echo "    $DEPS_INSTALL/usr/local/lib/"
