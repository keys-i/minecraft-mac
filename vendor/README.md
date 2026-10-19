# Licensing and upstream work

This project is derived from
[1JRobertson/bedrock-mac](https://github.com/1JRobertson/bedrock-mac), with upstream
history retained

The original scripts, documentation, probes, and Xodus helper additions in this
source package are offered under GNU GPL version 3; see [LICENSE](../LICENSE).
The WineGDK patches are covered by GNU LGPL version 2.1 or later, preserving their
upstream terms. Existing per-file notices continue to apply. This is a collection
of compatibility work, not an independently implemented Windows or Xbox runtime.

| Component | Source revision | License and attribution |
| --- | --- | --- |
| Xodus | [xodus-gaming/xodus](https://github.com/xodus-gaming/xodus/tree/0670e25aeb0e0e9f800f8f2f4968ae3b681842a7) | GPLv3; Xodus contributors. The root [LICENSE](../LICENSE) is an unchanged copy of this revision's license. |
| WineGDK and Wine | [Sightem/WineGDK](https://github.com/Sightem/WineGDK/tree/b5d23b074cfd5e28e79acceaaefaf41a26ce6272) | LGPL 2.1 or later; Wine project authors and WineGDK contributors. Upstream XUser identifies Olivia Ryan. See the unchanged [notice](licenses/Wine-NOTICE.txt), [license](licenses/Wine-LGPL-2.1-or-later.txt), and upstream AUTHORS/per-file notices. |
| macOS Store/runtime integration | [wtfsayo/cricket26-crossover](https://github.com/wtfsayo/cricket26-crossover/tree/81c7a2f80023a9f03fc42fbc16f491d97306c54b) | GPLv3 for original scripts and Xodus-derived work; its README expressly retains LGPL terms for Wine-derived patches. Credit belongs to that repository's contributors and the upstream authors identified there. |
| GameInput MSI/CAB reader | [Wyze3306/BedrockOnLinux](https://github.com/Wyze3306/BedrockOnLinux/tree/7a315c836b7ae8068042bc466b0540c16ffe3a5e) | MIT; BedrockOnLinux contributors. The adapted OLE/MSZIP reader in `src/standalone-gameinput.py` preserves the full upstream notice. Microsoft payloads are obtained from the owned game's installer and are not included here. |
| DXMT 0.80 | [3Shain/dxmt](https://github.com/3Shain/dxmt/tree/589adb780354b461645b29999cefaf533594ee99) | MIT at this revision; copyright 2023 Feifan He. The [license](licenses/dxmt-LICENSE.txt) is copied unchanged. Its vendored code carries additional [DXVK](licenses/dxmt-DXVK-LICENSE.txt), [LLVM](licenses/dxmt-LLVM-LICENSE.txt), and [MinGW](licenses/dxmt-MinGW-LICENSE.txt) notices. |

`vendor/patches/xodus-real-store-license.patch` and `vendor/patches/winegdk-macos-local.patch`
are unchanged copies from the reference revision above. The first is GPLv3;
the second is LGPL 2.1 or later. `vendor/patches/minecraft-store-callback.patch`
modifies the reference WineGDK implementation and retains LGPL 2.1 or later.
`vendor/patches/keychain-cache.patch`, `vendor/patches/unified-helper.patch`,
`tools/legacy/bedrock-helper.rs`, `src/standalone-helper.rs`, and `tools/legacy/prepare-owned-game.rs` extend
Xodus under GPLv3. `vendor/patches/standalone-wine-dxmt-abi.patch` changes Wine's macOS
driver, `vendor/patches/standalone-wine-idl-list.patch` fixes a duplicate install entry,
and `vendor/patches/standalone-wine-storage-linkage.patch` fixes C/C++ linkage in
the storage module. `vendor/patches/standalone-wine-user-privileges.patch` implements
account privilege and age-group checks using authenticated Xbox display claims.
`vendor/patches/standalone-wine-xuser-realms.patch` maps the exact Realms API hosts to
their original XSTS audience, cross-checked against BedrockOnLinux's runtime.
All five Wine patches retain LGPL 2.1 or later.
`vendor/patches/standalone-wine-xuser-token-refresh.patch` and
`vendor/patches/standalone-wine-xuser-z-device-auth.patch` also retain LGPL 2.1 or later;
they extend token renewal and device/title authentication in WineGDK.
Build scripts and the pinned Cargo lockfile use the same upstream dependencies;
each dependency retains its own license and notices.

`vendor/patches/standalone-signin-window.patch` changes the Xodus login window title to
“Microsoft sign-in” for the native launcher; it retains Xodus's GPLv3 license.
The native launcher and packaging scripts are original GPLv3 project code.
`vendor/patches/standalone-keychain-write.patch` adds a direct dependency on the already
pinned `security-framework` 3.7.0 crate for Keychain updates that do not reread
secrets. The patch retains GPLv3; security-framework retains its MIT/Apache-2.0
licensing.

The WineGDK startup fixes reuse its `windows.web`, `twinapi.appcore`,
`windows.ui.core.textinput`, and `wintypes` implementations. Their full source
and notices are in the pinned WineGDK tree fetched by
`python3 minecraft.py source fetch`

No license in this package grants rights to Minecraft, its assets or trademarks,
Microsoft's GDK/GameInput DLLs, CrossOver, D3DMetal, Apple SDKs, or Rosetta. These
items are not included in source exports. Users obtain their own legitimate
game and any separately required components. Microsoft account sign-in and
server-issued ownership licenses are still required by the existing preparation
path. This project is not affiliated with Microsoft, Mojang, CodeWeavers, or Apple.

The source exporter is not a binary redistribution tool. Before distributing a
compiled runtime, inventory every bundled dependency and include the applicable
notices and corresponding source/build materials for the exact binary versions.
Do not present a third-party runtime as wholly original project code.

## Standalone runtime dependency provenance

The standalone Wine build obtains x86-64 native dependencies, including GnuTLS and FreeType,
from [Gcenx's Wine 11.8 macOS archive](https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.8/wine-devel-11.8-osx64.tar.xz):

```text
SHA-256: 5c9f0984961ee6289f4f2c4fe751c27f02b6c28855154e3f99b7e2bd8108b620
```

The Wine runtime itself is built from the pinned WineGDK sources. Extracting these
native dependencies locally does not make them original project code or establish
their binary redistribution status. Their component-specific licenses, notices,
and source requirements still need inventory before any binary bundle is shipped.
The archive, extracted libraries, and compiled Wine are excluded from this source
release.

`tools/build/graphics.sh` retrieves a pinned official DXMT 0.80 binary release
for local use, verifies its SHA-256, and saves the source revision and notices.
This is an open-source dependency built by upstream, not a DXMT build performed by
this project. The source export contains only the retrieval script, probe source,
and unchanged license texts; it does not contain the downloaded graphics binaries.
Additional [embedded upstream notices](licenses/DXMT-embedded-NOTICES.txt) identify
the Microsoft DXBC parser and utilities credited to Philip Rebohle and Alexander
Bessonov. This collection preserves known attribution; it is not a completed
license audit of a future binary bundle.

## Artwork and screenshots

The README poster and earlier Overworld/Nether/End/Sift panoramas are original
AI-generated project artwork. Version 0.4 uses authored procedural terrain,
plants, structures and creatures in the native renderer; the earlier panoramas
remain source references and are not bundled. Mob proportions and features use
the official references listed in [asset notes](../assets/README.md), with
authored pixel maps rather than copied game models or textures
The scenery is not gameplay footage
The Sift scene is an artistic interpretation, not a claim about the installed
game's features. The launcher image
is an unaltered screenshot of the locally running native launcher, captured on
October 19, 2026. The [artwork prompt and screenshot sources](../assets/README.md)
are recorded separately
