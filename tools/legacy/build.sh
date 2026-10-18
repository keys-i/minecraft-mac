#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

helper() {
EXAMPLES="$ROOT/sources/xodus/crates/xodus-cli/examples"
mkdir -p "$EXAMPLES/bedrock_helper_parts" "$ROOT/logs"
cp "$ROOT/tools/legacy/bedrock-helper.rs" "$EXAMPLES/bedrock_helper.rs"
cp "$ROOT/tools/legacy/prepare-owned-game.rs" "$EXAMPLES/bedrock_helper_parts/prepare_owned_game.rs"
cargo +1.98.0 build --manifest-path "$ROOT/sources/xodus/Cargo.toml" \
  --release --locked -j6 -p xodus-cli --example bedrock_helper \
  > "$ROOT/logs/unified-helper-build.log" 2>&1
}

runtime() {
BUILD="$ROOT/build/winegdk"
RUST_TOOLCHAIN=$(rustup run 1.98.0 rustc --print sysroot)
SDK=$(xcrun --show-sdk-path)
mkdir -p "$BUILD/toolbin" "$ROOT/logs"
cat > "$BUILD/toolbin/lld-link" <<EOF
#!/bin/sh
export DYLD_LIBRARY_PATH='$RUST_TOOLCHAIN/lib'
exec '$RUST_TOOLCHAIN/lib/rustlib/aarch64-apple-darwin/bin/rust-lld' -flavor link "\$@"
EOF
chmod +x "$BUILD/toolbin/lld-link"
export PATH="$BUILD/toolbin:/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/bison/bin:/usr/bin:/bin:/opt/homebrew/bin:$PATH"
export CC="$(xcrun --find clang) -arch x86_64 -isysroot $SDK"
export CXX="$(xcrun --find clang++) -arch x86_64 -isysroot $SDK"
export LC_ALL=en_US.UTF-8
cd "$BUILD"
"$ROOT/sources/winegdk/configure" --host=x86_64-apple-darwin24 \
  --enable-win64 --with-mingw=/opt/homebrew/opt/llvm/bin/clang \
  --disable-tests --without-x --without-freetype \
  --without-gnutls --without-opengl --without-vulkan --without-gstreamer \
  --without-ffmpeg > "$ROOT/logs/runtime-configure.log" 2>&1
make -j6 dlls/xgameruntime/all dlls/windows.web/all dlls/twinapi.appcore/all \
  dlls/windows.ui.core.textinput/all dlls/wintypes/all \
  > "$ROOT/logs/runtime-build.log" 2>&1
}

probes() {
cd "$ROOT/build/winegdk"
export PATH="$PWD/toolbin:/opt/homebrew/opt/llvm/bin:/usr/bin:/bin"
make -j6 include/d3d11.h include/dxgi.h include/dxgitype.h include/dxgiformat.h \
  include/dxgicommon.h include/d3dcommon.h include/d3d10_1.h include/d3d10.h \
  include/d3d10shader.h include/d3d10effect.h include/d3d10sdklayers.h
for PROBE in graphics-probe runtime-auth-probe store-callback-probe; do
  ./tools/winegcc/winegcc -o "$ROOT/runtime/$PROBE.exe" --wine-objdir . \
    --cc-cmd="/opt/homebrew/opt/llvm/bin/clang -D__STDC__" -b x86_64-windows \
    "$ROOT/tools/probes/$PROBE.c" -Iinclude -I"$ROOT/sources/winegdk/include" \
    -I"$ROOT/sources/winegdk/include/msvcrt" -D__WINESRC__ -nostdlib \
    -Wl,-entry:mainCRTStartup dlls/kernel32/x86_64-windows/libkernel32.a \
    dlls/ucrtbase/x86_64-windows/libucrtbase.a --no-default-config
done
# The GDK reads MicrosoftGame.Config beside the executable.
cp "$ROOT/runtime/runtime-auth-probe.exe" "$ROOT/game/runtime-auth-probe.exe"
cp "$ROOT/runtime/store-callback-probe.exe" "$ROOT/game/store-callback-probe.exe"
}

case "${1:-}" in
  helper) helper ;;
  runtime) runtime ;;
  probes) probes ;;
  *) printf "Usage: %s {helper|runtime|probes}\n" "$0" >&2; exit 2 ;;
esac
