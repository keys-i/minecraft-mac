#!/bin/sh
# Stage the pinned, verified upstream DXMT release
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec "$ROOT/minecraft" graphics acquire "$@"
