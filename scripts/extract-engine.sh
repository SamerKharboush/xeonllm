#!/bin/bash
# Extract the engine binaries from a no-AVX2 DMG read-only and record their identity.
# usage: scripts/extract-engine.sh <dmg> [out-root]
# The DMG is never written; the app bundle is copied out of the read-only mount.
set -u

DMG="${1:-}"
ROOT="${2:-.scratch/xeonllm-0-2/engines}"
[ -n "$DMG" ] || { echo "usage: $0 <dmg> [out-root]" >&2; exit 2; }
[ -f "$DMG" ] || { echo "no such DMG: $DMG" >&2; exit 2; }

HERE="$(cd "$(dirname "$0")/.." && pwd)"
DMG="$(cd "$(dirname "$DMG")" && pwd)/$(basename "$DMG")"
case "$ROOT" in /*) ;; *) ROOT="$HERE/$ROOT" ;; esac
STEM="$(basename "$DMG" .dmg)"
DEST="$ROOT/$STEM/bin"
mkdir -p "$ROOT" "$DEST"
MP="$(mktemp -d "${TMPDIR:-/tmp}/xeon-engine-mount.XXXXXX")"
DETACHED=0
detach() {
    if [ "$DETACHED" = 0 ]; then
        hdiutil detach "$MP" >/dev/null 2>&1 || true
        DETACHED=1
    fi
}
trap detach EXIT

if ! hdiutil attach -readonly -nobrowse -mountpoint "$MP" "$DMG" >/dev/null 2>&1; then
    echo "hdiutil attach failed: $DMG" >&2
    exit 3
fi
APP=""
for name in XeonLLM.app ToshLLM.app; do
    if [ -d "$MP/$name/Contents/Resources/bin" ]; then APP="$MP/$name"; break; fi
done
if [ -z "$APP" ]; then
    echo "no XeonLLM.app/ToshLLM.app bin directory on $DMG" >&2
    exit 4
fi
cp -R "$APP/Contents/Resources/bin/." "$DEST/"
detach

SHA256=$(shasum -a 256 "$DMG" | awk '{print $1}')
BENCH_SHA=$(shasum -a 256 "$DEST/llama-bench" | awk '{print $1}')
SERVER_SHA=$(shasum -a 256 "$DEST/llama-server" | awk '{print $1}')
BANNER=$("$DEST/llama-bench" --version 2>&1 | tr '\t\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
SBANNER=$("$DEST/llama-server" --version 2>&1 | tr '\t\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
META="$ROOT/$STEM/engine.meta.tsv"
{
    printf 'stem\t%s\n' "$STEM"
    printf 'dmg_sha256\t%s\n' "$SHA256"
    printf 'app_bundle\t%s\n' "$(basename "$APP")"
    printf 'bench_sha256\t%s\n' "$BENCH_SHA"
    printf 'server_sha256\t%s\n' "$SERVER_SHA"
    printf 'bench_sha16\t%s\n' "${BENCH_SHA:0:16}"
    printf 'server_sha16\t%s\n' "${SERVER_SHA:0:16}"
    printf 'bench_banner\t%s\n' "$BANNER"
    printf 'server_banner\t%s\n' "$SBANNER"
} > "$META"
echo "engine: $STEM  sha16 ${BENCH_SHA:0:16}  dmg ${SHA256:0:16}  $BANNER"