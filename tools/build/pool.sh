#!/bin/sh
# Build an isolated diagnostic adapter. Staging is explicit and uses tested bytes.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OUTPUT="$ROOT/build/dxmt-autorelease-shim"
UPSTREAM="$ROOT/runtime/standalone/dxmt/x86_64-unix/winemetal.so"
export LC_ALL=en_US.UTF-8
if [ "${1:-}" = "--stage-existing-runtime" ] && [ "$#" -eq 2 ]; then
  "$ROOT/minecraft" graphics pool-stage "$2"
  exit 0
fi
if [ "$#" -ne 0 ]; then
  printf 'Usage: %s [--stage-existing-runtime WINE_RUNTIME]\n' "$0" >&2
  printf 'Build with no arguments, validate it, then stage while the target runtime is stopped.\n' >&2
  exit 2
fi
mkdir -p "$OUTPUT"
"$ROOT/minecraft" graphics pool-prepare
/usr/bin/clang -arch x86_64 -mmacosx-version-min=15.0 -fno-objc-arc \
  -fvisibility=hidden -O2 -Wall -Wextra -dynamiclib \
  "$ROOT/tools/probes/standalone-dxmt-autorelease-shim.m" -framework Foundation \
  -Wl,-install_name,@rpath/winemetal.so -Wl,-rpath,@loader_path \
  -o "$OUTPUT/winemetal.so"
/usr/bin/codesign --force --sign - "$OUTPUT/winemetal.so" >/dev/null 2>&1
"$ROOT/minecraft" graphics pool-manifest
printf 'Built isolated diagnostic adapter: %s\n' "$OUTPUT"
