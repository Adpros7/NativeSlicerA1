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
