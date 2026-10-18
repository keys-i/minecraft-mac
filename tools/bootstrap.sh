#!/bin/bash
# Bootstrap tools before the unified CLI is available
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
read_only=0
for argument in "$@"; do
  case "$argument" in --check|--help|-h) read_only=1 ;; esac
done
finish() {
  code=$?
  if [ "$code" -ne 0 ] && [ -t 0 ]; then
    printf '\nSetup stopped. Fix the issue above, then run bash tools/bootstrap.sh again.\n'
    read -r -p 'Press Return to close.' answer || true
  fi
}
trap finish EXIT
if [ "$(uname -s)" != Darwin ] || [ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" != 1 ]; then
  printf 'This launcher requires an Apple Silicon Mac.\n' >&2
  exit 1
fi
if [ "$(/usr/bin/sw_vers -productVersion | cut -d. -f1)" -lt 15 ]; then
  printf 'Update to macOS 15 or later, then run bash tools/bootstrap.sh again.\n' >&2
  exit 1
fi
if [ "$(uname -m)" != arm64 ]; then
  exec /usr/bin/arch -arm64 /bin/bash "$0" "$@"
fi
if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
  if [ "$read_only" -eq 1 ]; then
    printf 'Apple Command Line Tools are missing. Run bash tools/bootstrap.sh to install them.\n'
    exit 1
  fi
  printf 'Install Apple Command Line Tools in the window that opens.\n'
  /usr/bin/xcode-select --install || true
  read -r -p 'When installation finishes, press Return to continue.' answer
fi
/usr/bin/xcrun --find python3 >/dev/null
if [ "$read_only" -eq 0 ] && ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  printf 'Installing Rosetta. Follow Apple’s license prompt below.\n'
  /usr/sbin/softwareupdate --install-rosetta
fi
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:/opt/homebrew/opt/rustup/bin:/opt/homebrew/bin:/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/bison/bin:$PATH"
export STANDALONE_JOBS="${STANDALONE_JOBS:-2}"
/usr/bin/python3 "$ROOT/minecraft.py" play "$@"
