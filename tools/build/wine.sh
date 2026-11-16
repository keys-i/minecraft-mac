#!/bin/sh
# Compile the patched WineGDK source without any CrossOver binaries.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
BUILD="$ROOT/build/standalone-wine"
PREFIX="$ROOT/runtime/standalone/wine"
JOBS=${STANDALONE_JOBS:-3}
SOURCE="$BUILD/source"
# Refuse runtime mutation while a prefix is using these installed Unix libraries.
if [ -f "$PREFIX/lib/wine/x86_64-unix/ntdll.so" ] &&
   /usr/sbin/lsof -t "$PREFIX/lib/wine/x86_64-unix/ntdll.so" 2>/dev/null | read -r runtime_pid; then
  printf 'Close standalone Wine applications before rebuilding this runtime.\n' >&2
  exit 1
fi
mkdir -p "$BUILD/toolbin" "$BUILD/downloads" "$PREFIX/lib"
export LC_ALL=en_US.UTF-8
DEPS="$BUILD/downloads/wine-devel-11.8-osx64.tar.xz"
if [ ! -f "$DEPS" ]; then
  curl -fL --retry 3 "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.8/wine-devel-11.8-osx64.tar.xz" -o "$DEPS"
fi
"$ROOT/minecraft" wine dependencies "$DEPS" "$PREFIX/lib" "$BUILD/dependency-unused"
# Build tools link FreeType directly; a bare dylib install name fails after
# macOS strips DYLD environment variables when executing system shells.
install_name_tool -id '@rpath/libfreetype.6.dylib' "$PREFIX/lib/libfreetype.6.dylib"
codesign --force --sign - "$PREFIX/lib/libfreetype.6.dylib" >/dev/null 2>&1
if [ ! -d "$SOURCE" ]; then
  cp -cRp "$ROOT/sources/winegdk" "$SOURCE"
fi
for PATCH in "$ROOT"/vendor/patches/standalone-wine-*.patch; do
  if ! git -C "$SOURCE" apply --reverse --check "$PATCH" 2>/dev/null; then
    git -C "$SOURCE" apply --check "$PATCH"
    git -C "$SOURCE" apply "$PATCH"
  fi
done
RUST_TOOLCHAIN=$(rustup run 1.98.0 rustc --print sysroot)
SDK=$(xcrun --show-sdk-path)
cat > "$BUILD/toolbin/lld-link" <<EOF
#!/bin/sh
export DYLD_LIBRARY_PATH='$RUST_TOOLCHAIN/lib'
exec '$RUST_TOOLCHAIN/lib/rustlib/aarch64-apple-darwin/bin/rust-lld' -flavor link "\$@"
EOF
chmod +x "$BUILD/toolbin/lld-link"
export PATH="$BUILD/toolbin:/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/bison/bin:/usr/bin:/bin:/opt/homebrew/bin:$PATH"
export CC="$(xcrun --find clang) -arch x86_64 -isysroot $SDK"
export CXX="$(xcrun --find clang++) -arch x86_64 -isysroot $SDK"
export OBJC="$CC"
export CFLAGS='-O2'
export CXXFLAGS='-O2'
export OBJCFLAGS='-O2'
export CROSSCFLAGS='-O2'
export LC_ALL=en_US.UTF-8
# The installed Homebrew packages provide architecture-independent headers only.
# All linked third-party libraries come from the pinned x86_64 dependency archive.
export GNUTLS_CFLAGS="-I/opt/homebrew/opt/gnutls/include"
export GNUTLS_LIBS="-L$PREFIX/lib -lgnutls"
export FREETYPE_CFLAGS="-I/opt/homebrew/opt/freetype/include/freetype2"
export FREETYPE_LIBS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib -lfreetype"
export DYLD_FALLBACK_LIBRARY_PATH="$PREFIX/lib:/usr/lib"
# Portable install names avoid configure misparsing dylibs with bare Mach-O IDs.
export ac_cv_lib_soname_gnutls='@loader_path/../../libgnutls.30.dylib'
export ac_cv_lib_soname_freetype='@loader_path/../../libfreetype.6.dylib'
cd "$BUILD"
"$SOURCE/configure" --host=x86_64-apple-darwin24 \
  --prefix="$PREFIX" --enable-win64 \
  --with-mingw=/opt/homebrew/opt/llvm/bin/clang --disable-tests \
  --without-x --with-freetype --with-gnutls --without-vulkan \
  --without-gstreamer --without-ffmpeg > "$BUILD/configure.log" 2>&1
make -j"$JOBS" > "$BUILD/build.log" 2>&1
make install > "$BUILD/install.log" 2>&1
"$ROOT/minecraft" wine manifest "$PREFIX" "$SOURCE"
printf 'Built standalone Wine: %s\n' "$PREFIX/bin/wine"
