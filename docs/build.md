# Building and releasing

Start with [Architecture](architecture.md) for component ownership and
[CONTRIBUTING.md](../.github/CONTRIBUTING.md) for the review workflow. All commands here
run from the repository root on the local Mac. The standalone build does not
require CrossOver or an Apple Developer membership.

## Prerequisites

The documented build host is Apple Silicon. The currently tested complete bundle
requires macOS 27. Swift/DXMT target macOS 15, but the minimum OS of the assembled
app depends on every native binary, including Python and Wine dependencies

Install Apple's Command Line Tools and Rosetta, Git, a Python 3.12+ interpreter
for packaging, Rust/rustup, and Homebrew under `/opt/homebrew`. The source tools
otherwise support Python 3.9+; CI exercises 3.12 and 3.14. Homebrew's LLVM,
Bison, GnuTLS, FreeType, and Protocol Buffers are build dependencies. The scripts
use their `/opt/homebrew/opt/...` paths; an Intel Homebrew installation is not a
drop-in replacement.

If these tools are not installed yet, start with the official
[Homebrew installation guide](https://brew.sh/) and
[Rust/rustup installation guide](https://rust-lang.org/tools/install/). Reopen
Terminal after configuring their PATH entries. A Homebrew Python can provide
the packaging interpreter (`brew install python@3.14`); check which `python3`
your shell selects before creating the venv.

With Homebrew and rustup already installed:

```sh
xcode-select --install  # only if Command Line Tools are missing
brew install llvm bison gnutls freetype protobuf
rustup toolchain install 1.98.0 --profile minimal
```

Check the selected tools before a long build:

```sh
uname -m
sw_vers -productVersion
xcrun --find clang
xcrun --find swiftc
python3 --version
rustup run 1.98.0 rustc --version
protoc --version
/usr/bin/arch -x86_64 /usr/bin/true
```

The last command must exit successfully for the Intel runtime to work. If
Rosetta is missing, follow [Apple's instructions](https://support.apple.com/en-us/102527).
The launcher only checks for Rosetta; it does not install it for the user.

Building Wine and Rust uses much more storage than the player's 8 GB setup
check. Inspect `df -h .`, leave room for source, compiler output, archives, and
both app/DMG copies, and use a separate backup location for worlds. No measured
minimum build-space requirement or build-time guarantee is established.

## Build a complete local app

Clone the repository into a directory you control, then run:

```sh
git clone https://github.com/keys-i/minecraft-mac.git
cd minecraft-mac
python3 minecraft.py source fetch
STANDALONE_JOBS=3 ./tools/build/wine.sh
./tools/build/graphics.sh --wine-runtime "$PWD/runtime/standalone/wine"
python3 src/standalone-setup.py --build-helper --jobs 4
python3 -m venv build/packaging-env
build/packaging-env/bin/python -m pip install -r tools/requirements.txt
python3 minecraft.py build app
python3 minecraft.py build dmg
```

Use a Python 3.12+ `python3` when creating `build/packaging-env`. If the venv
already uses an older Python, preserve/move it and create a new one with the
intended interpreter. Installing a newer system Python does not upgrade an
existing venv.

| Step | Result and behavior |
| --- | --- |
| Bootstrap | Fetches pinned WineGDK and Xodus into `sources/`, applies tracked patches and Cargo lockfile; refuses an existing destination |
| Wine build | Compiles WineGDK in `build/standalone-wine`, installs to `runtime/standalone/wine`; downloads a pinned archive for portable dependency dylibs |
| Graphics staging | Downloads/verifies pinned DXMT, installs its Wine overlay, and records original DLL backups |
| Helper build | Copies `src/standalone-helper.rs` into Xodus and builds its release example with the locked dependencies |
| Package | Builds Swift/icon and frozen Python worker; copies runtime/helper, signs locally, records resource hashes and actual OS requirement |
| DMG | Creates `build/Minecraft-for-MacOS-preview.dmg` containing the app and an Applications shortcut; verifies the image |

The complete app is `build/packaged/Minecraft for MacOS.app`. It includes build
outputs for the open-source runtime but no game, Microsoft DLLs, Keychain data,
worlds, or development checkout. First Play obtains the required Microsoft
component and owned game. Build scripts never imply that a binary is cleared for
public redistribution; see [THIRD_PARTY.md](../vendor/README.md).

Do not run the Wine/graphics builds or replace an app while a game uses those
components. Quit Minecraft normally and let its account helper finish first.
The Wine and helper builders have active-process guards; still check which app
copy and runtime you are testing.

The optional memory-lifetime bridge can be built and validated following
[the graphics notes](architecture.md#standalone-graphics) before packaging. Packaging
retains and verifies its provenance; see [stability notes](status.md#stability-fixes-and-earlier-gameplay-evidence).

## Iterate without losing a working build

`python3 minecraft.py build launcher` creates `build/Minecraft for MacOS.app`, a development front end
that points at this checkout and uses `/usr/bin/python3`. It is useful for Swift
and worker changes after preparing the local runtime, but is not a portable app.
`python3 src/launcher/setup.py --status` inspects its installation without sign-in.

The packager refuses to overwrite an existing output. Use a new output name:

```sh
python3 minecraft.py build app --output 'build/iteration-2/Minecraft for MacOS.app'
python3 minecraft.py build dmg --app 'build/iteration-2/Minecraft for MacOS.app' \
  --output 'build/Minecraft for MacOS-iteration-2.dmg'
```

Choose a fresh suffix for each retained build. The packager rebuilds its
intermediate `build/frozen`, `build/pyinstaller`, and development launcher, so
do not run two packaging jobs concurrently. A packaged app copies its components;
subsequent edits in the checkout do not update that app. Repackage to test them.

After a Wine rebuild, rerun graphics staging with `--wine-runtime`: Wine's
installed D3D DLLs otherwise shadow DXMT. For helper source changes, use
`src/standalone-setup.py --build-helper`; `tools/legacy/build.sh helper` compiles the historical
`bedrock_helper`, not the native launcher's `standalone_helper`.

Rebuilding an ad-hoc helper can change Keychain authorization. To test remembered
access, launch the same helper bytes twice after the user authorizes it; do not
rebuild between attempts. Never change Keychain permissions just to force a pass.

## Command-line setup and diagnostics

The source CLI works in the checkout by default. Do not use it to infer the state
of a packaged app's separate data directory. To read that installation's status:

```sh
BEDROCK_HOME="$HOME/Library/Application Support/Bedrock for Mac" \
  python3 src/standalone-setup.py --check
```

`--check` is local and returns nonzero when installation is incomplete. It does
not access Microsoft or Keychain. `--dry-run` prints requested actions without
performing them. For a source installation, these are the actual setup stages:

```sh
python3 src/standalone-setup.py --threading
python3 src/standalone-setup.py --download-game --game-dir "$PWD/game" --market CA
python3 minecraft.py runtime prepare
python3 minecraft.py runtime launch --market CA
```

Download and launch can sign in and contact Microsoft; they are not offline
checks. The separate CLI invocations also use separate helper sessions. Use the
native launcher when testing its single-session onboarding UX. A custom
`--game-dir` must be supplied consistently to setup and runtime commands. A
different game directory cannot silently replace an existing `G:` drive mapping
in the same prepared prefix.

For optional probes, after installing the owned game and runtime:

```sh
./tools/build/probes.sh
python3 minecraft.py runtime probe graphics
```

The graphics probe exercises the local Wine prefix. The `account`, `store`, and
`privileges` probes also use the account helper and may prompt/contact Microsoft.
See [Account and game preparation](architecture.md#standalone-setup),
[graphics notes](architecture.md#standalone-graphics), and [testing](test.md).

## Build failures

| Failure | Check |
| --- | --- |
| Bootstrap destination exists | Run `python3 minecraft.py source verify`; preserve local changes before preparing a new source tree. Do not fetch a different branch into the pinned checkout to silence a mismatch. |
| Cargo lock or source patch mismatch | Compare tracked patches, `vendor/patches/Cargo.lock`, and the pinned source check. Keep `--locked`; update provenance and checksums intentionally. |
| `protoc` missing | Check the `protobuf` installation and PATH, or the intended `PROTOC` executable. |
| Wine configure/compile/install failure | Read `build/standalone-wine/configure.log`, `build.log`, or `install.log`; confirm the required Homebrew paths and Rust toolchain. |
| DXMT mismatch after runtime rebuild | Reapply the graphics overlay with `--wine-runtime` before preparing/launching. |
| Package dependency missing | Build Wine, stage DXMT, build the standalone helper, and install the packaging requirements into the expected venv. |
| Package/DMG destination exists | Choose a new output path; keep the running or last working copy. |
| New bundle needs a newer macOS | Inspect its `Contents/Info.plist` and native dependency targets. Lowering the plist alone does not make it compatible. |

Validate the appropriate boundaries in [Testing](test.md), then update the
[source inventory](build.md#update-the-source-inventory). A successful build
is not evidence of a fresh-account download, gameplay, or a clean-Mac install.

---

## Preparing a source release

The source repository is [keys-i/minecraft-mac](https://github.com/keys-i/minecraft-mac).
Its upstream source is
[1JRobertson/bedrock-mac](https://github.com/1JRobertson/bedrock-mac). The commands
below prepare and verify source locally; they do not push or create a release
Export only reviewed client source, not this entire development directory or
any adjacent server repository. Read [THIRD_PARTY.md](../vendor/README.md) for
component notices and [Release status](status.md) for binary release gates.

### Update the source inventory

Every new public file, including documentation and `AGENTS.md`, must be added
individually to `ALLOWED_FILES` in `tools/source.py`. Check its contents before
adding it. The tracked `tools/SOURCE-SHA256.txt` lists those files; it does not include
itself, generated output, or private data. CI verifies it, so regenerate it after
the last source/documentation edit:

```sh
python3 minecraft.py source inventory
shasum -a 256 -c tools/SOURCE-SHA256.txt
```

If `.new` already exists, inspect and preserve it before retrying. Do not use
recursive filesystem hashing: it can enumerate account data, worlds, binaries,
or ignored logs. `source check` validates source boundaries but does not refresh the
tracked inventory. An export generates its own inventory in the destination.

### Validate and export

From the client directory:

```sh
python3 -m unittest discover -s tests -p 'test_export_source.py'
python3 -m unittest discover -s tests -p 'test_bootstrap_sources.py'
python3 minecraft.py source check
python3 minecraft.py source list
shasum -a 256 -c tools/SOURCE-SHA256.txt
python3 minecraft.py source export ../minecraft-mac-source
```

The destination must not exist. The exporter creates an independent source-only
directory and a SHA-256 inventory. It reads individual paths from `ALLOWED_FILES`
in `tools/source.py`; it never traverses ignored directories. Symlinks, missing
files, and binary replacements in text entries are rejected. The individually
listed JPEG/WebP README images have container-header checks and a 2 MiB limit.
Review and add each new standalone script, patch, test, and notice to that
allowlist before exporting a later version. Do not replace it with a recursive
copy or an extension glob

The package omits game assets/executables, downloaded archives, source checkouts,
compiled binaries, Wine prefixes and worlds, Keychain data, helper session files,
logs, screenshots, CrossOver, D3DMetal, and Microsoft runtime DLLs. `.gitignore`
alone is not the release boundary. Review the exported source and the inventory
before publishing them to the intended repository.

### Reproduce source preparation

The exported directory includes the patches, exact Cargo lockfile, original
license texts, and a pinned source bootstrap:

```sh
python3 minecraft.py source fetch
python3 minecraft.py source verify
```

The first command fetches the exact Xodus, WineGDK, and DXMT commits listed in
`tools/source.py`, applies the reference patches before the Bedrock-specific
patches, and installs `vendor/patches/Cargo.lock` into Xodus. DXMT is kept unmodified for
the optional native graphics rebuild. It refuses to overwrite any existing
checkout. Use `--project xodus`, `--project winegdk`, or `--project dxmt` for one tree, or
`--destination /an/empty/source-directory` for a separate copy. Fetching needs Git
and network access; `source verify` is offline and does not modify the source trees.

The check rebuilds the expected patched files in a temporary directory and compares
them with the checkout. It verifies the pinned base, preserved patch contents,
and Xodus lockfile. It does not certify unrelated local edits, runtime binaries,
or the complete Cargo dependency cache. `src/standalone-setup.py --build-helper`
copies and builds the current standalone helper example with `--locked`.
`tools/legacy/build.sh helper` builds the earlier CrossOver helper instead. The obsolete separate
`prepare-game.rs` helper is intentionally not exported.

`tools/build/wine.sh` creates its own build copy of the prepared WineGDK tree
and applies `vendor/patches/standalone-wine-dxmt-abi.patch`,
`vendor/patches/standalone-wine-idl-list.patch`,
`vendor/patches/standalone-wine-storage-linkage.patch`, and
`vendor/patches/standalone-wine-user-privileges.patch`, followed by
`vendor/patches/standalone-wine-xuser-realms.patch` and
`vendor/patches/standalone-wine-xuser-token-refresh.patch` there. These additional patches
include `vendor/patches/standalone-wine-xuser-z-device-auth.patch` for PS5 friend joining and
are not applied to the shared baseline checkout by the source bootstrap.
The build also applies `vendor/patches/standalone-wine-ipv6.patch` to preserve adapter
indices for IPv6 discovery
`tools/build/graphics.sh` retrieves pinned upstream DXMT binaries and notices;
see [the dependency provenance](../vendor/README.md#standalone-runtime-dependency-provenance).

### Release status and remaining setup

The verified gameplay configuration and its remaining limits are recorded in
[stability notes](status.md#stability-fixes-and-earlier-gameplay-evidence). Source export does not establish that a clean Mac can
complete installation or that a replacement graphics/runtime build passes the
same gameplay checks. Publish those claims only after testing the corresponding
configuration.

The original CrossOver-based scripts assumed an already installed trial, a
configured bottle, the user's downloaded Windows game, and Microsoft's native
threading DLL. They are preserved for reproducibility of that implementation, not
as a claim of complete installation automation. New standalone setup/build paths
must document and verify their own prerequisites and official downloads. No game,
credentials, proprietary runtime, or current user's world is part of this release.

A source release does not grant permission to bundle third-party binaries. Any
future binary release needs its own dependency/notice inventory and matching
corresponding source for the exact components distributed.

### Review and publish source

1. Run the relevant [checks](test.md), regenerate the inventory, and export to
   a new directory whose parent exists. Verify the exported inventory there.
2. Inspect `git diff --check`, the diff, and `git status --short`. Stage only the
   intended source, docs, patches, and inventory; inspect `git diff --cached`
   before committing. Do not rely on `.gitignore` to review publication content.
3. Open a pull request and wait for checks on its final commit. Record live-test
   claims separately from compilation and fixture checks. Merge only within
   the maintainer's requested scope.
4. For a tagged source release, identify the exact commit, its source archive
   checksum, build prerequisites, and known limitations. A normal source PR
   does not require uploading any DMG or local runtime.
5. Do not upload the development DMG as a public installer until the gates in
   [Release status](status.md) are satisfied. Once a binary preview is ready, label
   its signing/notarization status and tested platforms explicitly.

### GitHub automation

[Source checks](../.github/workflows/checks.yml) runs on pushes to `main`, pull
requests and manual dispatch. It checks the supported Python source versions,
the native launcher and the pinned account helper without using a real account

[Source release](../.github/workflows/release.yml) calls the same complete checks
at the release commit before packaging an archive and SHA-256 checksums.
Running it manually on `main` creates a downloadable Actions artifact without
creating a release. Pushing a reviewed `v*` tag publishes the same files as a
GitHub prerelease; it does not build or publish the DMG

[Security](../.github/workflows/security.yml) runs Python CodeQL on pushes, pull
requests and a weekly schedule. Analysis has repository-read and security-event
upload permissions; it does not fetch the game or access a Microsoft account.
Native Swift compilation and Rust helper tests remain in source/release checks
The [security policy](../.github/SECURITY.md) records the analysis scope and gaps

[Dependabot](../.github/dependabot.yml) checks GitHub Actions and Python
packaging dependencies weekly. Review each update and regenerate
`tools/SOURCE-SHA256.txt` on its branch before merging, as required for any exported
file change. The checksum check intentionally rejects a stale inventory.
Pinned Wine, DXMT and Xodus revisions and the patched Cargo lockfile require
manual review and runtime validation
