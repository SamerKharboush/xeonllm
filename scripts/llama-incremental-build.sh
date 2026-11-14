#!/bin/zsh
# Incremental rebuild of the llama engine. The version stamp is re-read from VERSION on every
# run: CMake keeps -DXEON_VERSION in its cache, so a bump with no configure used to rebuild
# every object with the old version (beta.5 shipped reporting beta.4 this way).
set -e
cd "$(dirname "$0")/../vendor/llama.cpp"

XEON_VERSION="$(tr -d '[:space:]' < ../../VERSION)"
cache=build-static/CMakeCache.txt
if [ -f "$cache" ]; then
    cur=$(sed -n 's/^CMAKE_CXX_FLAGS:STRING=//p' "$cache")
    if [ "$cur" != "-DXEON_VERSION=$XEON_VERSION" ]; then
        echo "version stamp stale ('$cur' -> '-DXEON_VERSION=$XEON_VERSION'); reconfiguring"
        cmake -B build-static -DCMAKE_CXX_FLAGS="-DXEON_VERSION=$XEON_VERSION" >/dev/null
    fi
fi

cmake --build build-static --config Release -j"$(sysctl -n hw.ncpu)" -t llama-server

if ! strings build-static/bin/llama-server | grep -Fqx "$XEON_VERSION"; then
    echo "BUILD CHECK FAILED: llama-server does not carry '$XEON_VERSION' from VERSION" >&2
    exit 1
fi
