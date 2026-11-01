#!/bin/zsh
# Incremental rebuild of the llama engine. The version stamp is re-read from VERSION on every
# run: CMake keeps -DTOSH_VERSION in its cache, so a bump with no configure used to rebuild
# every object with the old version (beta.5 shipped reporting beta.4 this way).
set -e
cd "$(dirname "$0")/../vendor/llama.cpp"

TOSH_VERSION="$(tr -d '[:space:]' < ../../VERSION)"
cache=build-static/CMakeCache.txt
if [ -f "$cache" ]; then
    cur=$(sed -n 's/^CMAKE_CXX_FLAGS:STRING=//p' "$cache")
    if [ "$cur" != "-DTOSH_VERSION=$TOSH_VERSION" ]; then
        echo "version stamp stale ('$cur' -> '-DTOSH_VERSION=$TOSH_VERSION'); reconfiguring"
        cmake -B build-static -DCMAKE_CXX_FLAGS="-DTOSH_VERSION=$TOSH_VERSION" >/dev/null
    fi
fi

cmake --build build-static --config Release -j"$(sysctl -n hw.ncpu)" -t llama-server

if ! strings build-static/bin/llama-server | grep -Fqx "$TOSH_VERSION"; then
    echo "BUILD CHECK FAILED: llama-server does not carry '$TOSH_VERSION' from VERSION" >&2
    exit 1
fi
