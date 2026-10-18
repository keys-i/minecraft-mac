# Preparing a source release

The source repository is [keys-i/minecraft-mac](https://github.com/keys-i/minecraft-mac).
Its upstream source is
[1JRobertson/bedrock-mac](https://github.com/1JRobertson/bedrock-mac). The commands
below prepare and verify source locally; they do not push or create a release
Export only reviewed client source, not this entire development directory or
any adjacent server repository. Read [THIRD_PARTY.md](../vendor/README.md) for
component notices and [RELEASE.md](RELEASE.md) for binary release gates.

## Update the source inventory

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

## Validate and export

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

## Reproduce source preparation

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

## Release status and remaining setup

The verified gameplay configuration and its remaining limits are recorded in
[stability notes](STABILITY.md). Source export does not establish that a clean Mac can
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

## Review and publish source

1. Run the relevant [checks](TESTING.md), regenerate the inventory, and export to
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
   [RELEASE.md](RELEASE.md) are satisfied. Once a binary preview is ready, label
   its signing/notarization status and tested platforms explicitly.

## GitHub automation

[Source checks](../.github/workflows/checks.yml) runs on pushes to `main`, pull
requests and manual dispatch. It checks the supported Python source versions,
the native launcher and the pinned account helper without using a real account

[Source release](../.github/workflows/release.yml) calls the same complete checks
at the release commit before packaging an archive and SHA-256 checksums.
Running it manually on `main` creates a downloadable Actions artifact without
creating a release. Pushing a reviewed `v*` tag publishes the same files as a
GitHub prerelease; it does not build or publish the DMG

[Security](../.github/workflows/security.yml) runs CodeQL for Python and a real
Swift launcher build on pushes, pull requests and a weekly schedule. Analysis
has only repository-read and security-event upload permissions; it does not
fetch the game or access a Microsoft account. CodeQL does not cover the Rust
helper or patched Wine/DXMT sources

[Dependabot](../.github/dependabot.yml) checks GitHub Actions and Python
packaging dependencies weekly. Review each update and regenerate
`tools/SOURCE-SHA256.txt` on its branch before merging, as required for any exported
file change. The checksum check intentionally rejects a stale inventory.
Pinned Wine, DXMT and Xodus revisions and the patched Cargo lockfile require
manual review and runtime validation
