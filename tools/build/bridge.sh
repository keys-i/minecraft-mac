#!/bin/sh
# Rebuild DXMT's Cocoa/Metal bridge for display lifetime and launcher handoff
# Does not install into a runtime. The C++ finish-thread patch is not built here.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OUTPUT="$ROOT/build/dxmt-memory-unix"
SOURCE="$ROOT/sources/dxmt"
WINE_RUNTIME="${STANDALONE_WINE_RUNTIME:-$ROOT/runtime/standalone/wine}"
export LC_ALL=en_US.UTF-8
case "${1:-}" in
  --stage-existing-runtime)
    [ "$#" -eq 2 ] || { printf 'Expected target Wine runtime\n' >&2; exit 2; }
    exec "$ROOT/minecraft" graphics stage "$2" ;;
  --validate-runtime)
    [ "$#" -eq 2 ] || { printf 'Expected isolated test Wine runtime\n' >&2; exit 2; }
    exec "$ROOT/minecraft" graphics validate "$2" ;;
  --validate)
    [ "$#" -eq 1 ] || exit 2
    exec "$ROOT/minecraft" graphics validate-clone "$WINE_RUNTIME" ;;
  '') [ "$#" -eq 0 ] || exit 2 ;;
  *) printf 'Usage: %s [--validate | --validate-runtime TEST_RUNTIME | --stage-existing-runtime TARGET_RUNTIME]\n' "$0" >&2; exit 2 ;;
esac
mkdir -p "$OUTPUT"
"$ROOT/minecraft" graphics prepare "$WINE_RUNTIME"
/usr/bin/clang -arch x86_64 -mmacosx-version-min=15.0 -std=gnu2x -fno-objc-arc -O2 -ObjC \
  -I "$SOURCE/include" -I "$SOURCE/src/winemetal/unix" \
  -I "$SOURCE/src/winemetal" -I "$SOURCE/src/airconv" \
  -c "$OUTPUT/source/src/winemetal/unix/winemetal_unix.c" -o "$OUTPUT/winemetal_unix_patched.o"
/usr/bin/clang -arch x86_64 -mmacosx-version-min=15.0 -std=c11 -O2 -Wall -Wextra \
  -c "$ROOT/tools/probes/standalone-dxmt-display-trace.c" -o "$OUTPUT/display-trace.o"
/usr/bin/clang -arch x86_64 -mmacosx-version-min=15.0 -dynamiclib \
  "$OUTPUT/winemetal_unix_patched.o" "$OUTPUT/display-trace.o" "$OUTPUT/winemetal-upstream.so" \
  "$WINE_RUNTIME/lib/wine/x86_64-unix/ntdll.so" "$WINE_RUNTIME/lib/wine/x86_64-unix/winemac.so" \
  -framework Cocoa -framework Metal -framework MetalFX -framework ColorSync -framework QuartzCore \
  -Wl,-install_name,@rpath/winemetal-memory.so -Wl,-rpath,@loader_path -o "$OUTPUT/winemetal.so"
/usr/bin/install_name_tool -change @rpath/winemetal.so @loader_path/winemetal-upstream.so \
  -id @rpath/winemetal.so "$OUTPUT/winemetal.so"
/usr/bin/codesign --force --sign - "$OUTPUT/winemetal.so" >/dev/null 2>&1
/usr/bin/clang -arch x86_64 -mmacosx-version-min=15.0 -std=gnu2x -fno-objc-arc -O2 -Wall -Wextra \
  -I "$SOURCE/src/winemetal" "$ROOT/tools/probes/standalone-dxmt-display-probe.m" \
  -framework Foundation -framework CoreGraphics -Wl,-rpath,@loader_path \
  -o "$OUTPUT/display-memory-probe"
"$ROOT/minecraft" graphics manifest
printf 'Built isolated Unix bridge: %s\n' "$OUTPUT"
printf 'Enable optional scalar counters with BEDROCK_DXMT_DISPLAY_TRACE=1.\n'
