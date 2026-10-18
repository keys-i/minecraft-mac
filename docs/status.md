# Release status

This is a source preview with an ad-hoc signed local DMG. Developer ID signing,
notarization and clean-Mac installation have not been verified. Apple Developer
membership is not required to publish source or build a local preview

Status snapshot: October 19, 2026. The earlier native launcher source was merged in
[PR #1](https://github.com/1JRobertson/bedrock-mac/pull/1), merge commit `0205d2a`.
That merge did not publish a binary. Use [Testing](test.md) for the manual
test matrix and artifact checks; use [Source releases](build.md#preparing-a-source-release) for source
inventories and exports

## October 19 interface update

Current source uses **Minecraft for MacOS** branding and a poster-led native
installer with block-style controls, visible progress and a resizable window
The earlier data directory, bundle identifier and account helper are retained

The native launcher compiles locally and its ad-hoc signature verifies. The
90-test Python suite includes the artwork and installation-identity packaging
contract. The README was checked with GitHub's Markdown renderer, including its
centred title, workflow badges, links, callouts and expandable sections

Computer Use denied access to the disposable interface preview. Visual,
keyboard and VoiceOver checks remain outstanding; the installed app, existing
DMG and live game were not replaced or retested by this interface update

## October 19 candidate

The `minecraft-mac` candidate includes the open-source runtime and preserves
the existing account helper bytes. The app is 355,041,701 bytes in regular
files; its LZFSE DMG is 127,182,005 bytes. It contains no game, account or world

The Python suite passes 80 tests. The image was verified, mounted read-only,
and checked against all 1,047 resource hashes and the complete app signature.
Relocation and graphics mismatch tests cover the shared graphics libraries;
see [Performance](status.md#performance) for the method and measured handoff results

The image checksum is

```text
6fb9c63cd79347b363361e69d37a76b9fa3d7d991cb5fff09681e3c3bbe88835
```

The candidate was installed over the existing local app and launched with the
existing account and game. On October 19, the user confirmed that Marketplace
and skin changes both opened quickly. This is a single-session functional
check; controlled loading and gameplay performance comparisons remain unverified

## Verified behavior

- Owned Windows package downloaded and prepared on the development Mac.
- Native launcher started Minecraft; the user confirmed **Sign in now** worked
  with the existing Microsoft session on October 2, 2026.
- Earlier standalone runtime testing reached local gameplay, a featured-server
  lobby, and the joined-Realm list. Xbox multiplayer and PS5 friend-world entry were confirmed on the September 30
  stability build; see [the dated evidence](status.md#stability-fixes-and-earlier-gameplay-evidence). Entry into an active
  Realm and gameplay with the combined native-launcher build remain unverified.
- Live retest on October 2: **Allow** produced one prompt on the next launch.
  The user then chose **Always Allow**, quit Minecraft, and launched the unchanged
  build again: **no Keychain prompt**. This verifies remembered access for this
  build, not authorization across a changed helper signature.
- The final local app was installed in Applications. Play started Minecraft
  using the existing game and saved account; the launcher reached its running
  state. This was an existing installation on the development Mac, not a clean
  account or downloaded-app Gatekeeper test.
- Offline tests cover one account helper across download and launch, failed
  setup cleanup, cancellation with a real child process, bounded sign-in waits,
  damaged setup records, progress parsing, and source export boundaries.
- Helper tests cover the single credential read, denied reads, failed writes,
  account switching, package path validation, and CDN URL policy.

Automated tests use fixtures; they do not prove a clean-machine sign-in or a
particular number of macOS security prompts.

## Current support limits

| Area | Status |
| --- | --- |
| Local packaged app | Apple Silicon, Rosetta, macOS 27 minimum for the assembled components |
| Swift / pinned DXMT targets | macOS 15; this does not establish support for the complete bundle |
| Game version observed | Windows Bedrock 1.26.5203.0; Microsoft's catalog selects the version for a new download |
| Distribution | GitHub source repository; local ad-hoc signed app/DMG; no public notarised installer |
| Updates | Manual app replacement; existing game reused; no automatic game updater |
| Offline launch / native market selector | Not implemented; native setup uses `CA`, CLI accepts a market argument |
| Gameplay evidence | Local gameplay, featured-server lobby, joined-Realm listing observed; active Realm entry and PS5 friend sessions unverified |
| Saves | Existing data preserved by installation/update paths; clean-Mac world save/reopen and restore scenarios remain to be verified |

Earlier graphics notes record a different historical host/OS. They do not lower
the current bundle's inspected macOS requirement. No Intel-Mac, older-macOS,
all-game-versions, Marketplace-completeness, or zero-prompt-update support claim
is made.

## Before publishing a binary preview

- Inventory the bundled Python/PyInstaller, Rust, Wine dependency, and graphics
  components. Include their notices and matching source/build materials.
  The existing Wine dependency archive has not had a complete redistribution
  inventory; see [THIRD_PARTY.md](../vendor/README.md).
- Complete authentication/integrity verification for all game package sections.
  The current catalog may return Microsoft's HTTP CDN endpoints; existing
  segment checks do not authenticate every unencrypted section. Account and
  license requests use certificate-verified HTTPS.
- Test a clean Mac: downloaded DMG, Applications install, Rosetta absent/present,
  fresh owner sign-in, declined Keychain access, cancellation, retry, successful
  launch, world save/reopen, sign-out, and replacement with an updated app.
- Record the actual minimum macOS version of **all** bundled Mach-O binaries.
  Current locally built Wine/Python components require macOS 27. Changing the
  front end's deployment target or just swapping Python is insufficient
- Verify quit/reopen and upgrade Keychain behavior. Ad-hoc rebuilds can change the
  helper's signing identity; no zero-prompt update claim is made.
- Include checksums and tested limitations in release notes. Use a GitHub
  prerelease for unsigned previews; signing/notarization is a separate step
  toward a normal public Mac distribution.

## Local validation

See [Testing](test.md) for prerequisites and live-test boundaries. Close
the game/helper before rebuilding source components. After bootstrap and
preparing the current helper example, the core checks are:

```sh
python3 -m unittest discover -s tests -p 'test_*.py'
python3 minecraft.py source verify
python3 minecraft.py source check
python3 minecraft.py build launcher
cargo +1.98.0 test --release --locked --manifest-path sources/xodus/Cargo.toml \
  -p xodus-cli --example standalone_helper
bash tests/run-xuser-tests.sh
```

`tools/build.py app` verifies the final bundle signature and records SHA-256
hashes of bundled resource files. `tools/build.py dmg` verifies the image after creating
it. These integrity checks do not replace notarization or gameplay testing.

---

## Stability fixes and earlier gameplay evidence

The September 30 stability branch is integrated with the native launcher.
The native app keeps its single account helper, progress reporting, cancellation,
structured errors, and one Keychain read per process. The additional fixes cover:

- Expired or incomplete Microsoft sign-in tokens are rejected. Device tokens are
  refreshed using the saved device identity; denied credential reads fail without
  replacing credentials.
- WineGDK renews Xbox tokens and forwards device authentication, obtains Xbox
  device/title tokens, and includes them in signed XSTS requests for friend joining.
- The launcher can remove a private, non-listening socket only when its recorded
  owner is dead. Unknown or active endpoints remain untouched.
- Completed downloads and prepared source trees are promoted without replacing
  a destination created concurrently. Existing full GDK downloads remain reusable;
  new component downloads retain the native launcher's verified 197 MB range path.
- Optional DXMT display-query and ColorSync lifetime fixes remain available as
  a separately built, verified Unix bridge.

### Graphics and packaging

Follow [the graphics notes](architecture.md#standalone-graphics) to build, probe,
and explicitly stage the optional bridge into an idle runtime. The default
[development build](build.md) still stages upstream DXMT. The memory fix
is not enabled merely by merging source or rebuilding the Swift interface.

When packaging a runtime with a bridge, the packager validates the original
libraries and source hashes, includes its patch/trace provenance, and records
new library hashes after ad-hoc signing. The launcher checks those packaged
bytes against the manifest. This preserves validation despite signature changes;
it does not establish a new graphics or gameplay test result.

### Local networking check, October 19, 2026

The standalone Wine patch `standalone-wine-ipv6.patch` populates the IPv6
interface index returned by `GetAdaptersAddresses`, using the same native
interface index as the other Wine network APIs

On the M3 Pro test Mac, all 11 active IPv6 adapters previously returned index
zero; the rebuilt DLL returned a nonzero index for all 11, and the isolated
zero-byte and one-byte loopback send/receive checks passed

This API correction alone does not establish that Minecraft's synchronous
loopback-send hang or Marketplace responsiveness is fixed

### Earlier gameplay results

These observations belong to the September 30, 2026 standalone development build
on an M4 Pro Mac mini with 24 GB RAM, macOS 15.3.1, WineGDK 11.8, DXMT v0.80,
and Minecraft 1.26.52. They do not establish the native package's minimum OS or
prove gameplay with the newly combined source.

| Scenario | Recorded result |
| --- | --- |
| Xbox multiplayer | User-confirmed cross-play; 1 hour 51 minutes monitored; normal exit |
| Xbox session memory | 4.18–5.15 GiB game footprint; normal system memory pressure throughout |
| PS5 friend world | User-confirmed entry after the device/title authentication fix, a retry, and a resource-pack download |
| PS5 session monitoring | 97 minutes; 3.39–5.10 GiB footprint; no detected crash, confirmed hang, or reported repeat join failure; subsequent normal exit |
| Local play | World rendering, saving, reopening, movement, fullscreen switching, and normal exit verified |
| Online services | Featured-server lobby entry and joined-Realm listing verified; active Realm entry untested |

An earlier overnight session froze after about nine hours with roughly 20 GB of
native small-object allocations. After the DXMT lifetime fixes, a five-minute
comparison measured about 0.36 MB of small-allocation growth versus 7.4 MB before.
The short comparisons and later multiplayer sessions do not prove overnight
stability. The transient Guardian error before successful PS5 entry was not
fully explained, and a disconnect/rejoin cycle remains unverified.

### Optional local monitoring and diagnostics

The monitor runs only when explicitly started; it does not upload diagnostics:

```sh
python3 minecraft.py monitor --help
python3 minecraft.py runtime launch --network-diagnostics
```

The second command launches the game and enables HTTP host/status diagnostics;
it is not an offline test. Do not start it alongside a running game/helper.
Use `python3 minecraft.py monitor mark` and `python3 minecraft.py monitor stop` for an existing monitor
session. Raw captures stay private in `logs/standalone/monitor/` and are excluded
from source exports. Review excerpts before sharing them.

`tools/bootstrap.sh` and `tools/setup.py` retain the older source-building setup path for
development. They reuse a completed installation, but do not update an installed
game or runtime. The native app remains the documented player entry point.

### Integration validation, October 5, 2026

The combined source passed Python regression checks, Rust helper tests using
fixture credentials. A local native launcher build was blocked by duplicate
`SwiftBridging` module definitions in this Mac's Apple Command Line Tools; the
Swift sources are unchanged and the PR also requires the native CI build.
The merged Wine patches apply
in sequence and reproduce the existing runtime build source; that runtime passed
31 account-claim, 19 Realms-routing, and 18 token-refresh checks in a separate test
prefix. No existing game installation, saved world, or account was replaced.
A complete packaged build, fresh sign-in, gameplay, and overnight testing of the
combined version remain separate validation work.

---

## Performance

Measurements below were recorded on October 19, 2026 on an M3 Pro with 36 GB
RAM and macOS 27.0.1. They compare the existing local build with this candidate
using the same runtime and graphics settings

| Operation | Before | Candidate | Method |
| --- | ---: | ---: | --- |
| Account helper handoff, median | 259.215 ms | 164.186 ms | Seven local fixture runs per variant, in sequence |
| Process identity lookups before handoff | 4 | 2 | Same fixture; newly created children use their owned process handle |
| App regular-file payload | 395,693,537 bytes | 355,041,701 bytes | Sum regular files, excluding symlinks |
| Compressed DMG | 155,683,292 bytes | 127,182,005 bytes | Full runtime included; image checksum verified |

The fixture models a helper that binds its private socket after an 80 ms delay
and interpreter startup. It performs no Microsoft, Keychain or game operation
and does not measure the full sign-in or game-loading time

### Launch handoff

The session now checks the child process it started while waiting for the
account socket, avoiding repeated external process discovery. It checks every
50 ms rather than every 250 ms. Adopting an existing helper still verifies its
PID and executable; socket type, ownership and permissions remain mandatory

Reproduce the comparison from this repository, which retains upstream history

```sh
mkdir -p work
git show 99fc9aa:src/standalone.py > work/before.py
python3 -B tests/benchmark.py work/before.py
python3 -B tests/benchmark.py
```

The fixture removes its child, socket and temporary directory after each run
Run variants in sequence without compiling or profiling concurrently

### Included runtime

The game uses x86-64 WineGDK 11.8 through Rosetta and DXMT v0.80 for Direct3D 11
on Metal. DXMT's shader caches remain enabled by default. No image-quality
reduction, frame cap, unsafe compiler flag or altered game file is used to
produce the results above

The package retains the verified display/ColorSync lifetime correction and
IPv6 adapter index correction. The display-query probe previously measured
784,384 retained bytes upstream and 16,384 bytes with the correction after
2,000 queries; see [the graphics evidence](architecture.md#standalone-graphics)

Menu window checks observed 20 responses over 45 seconds with a maximum
response time of 13 ms after restarting the earlier blocked session. This
measures Windows message handling. After installing this candidate on October
19, the user confirmed that Marketplace and skin changes both opened quickly.
This verifies the reported menu behaviour in that session; it does not measure
transaction latency or gameplay frame times

### Packaging

DXMT reference paths now point to the matching Wine overlay libraries through
relative links contained inside the app. The packager rejects mismatched
libraries before replacing a reference. The app is 40,651,836 bytes smaller
while keeping the bridge's source provenance and hash verification

The DMG uses macOS's LZFSE compression, `ULFO`. Comparing compression alone on
the same full app produced 155,683,292 bytes with `UDZO` and 142,044,820 bytes
with `ULFO`; creation took 9.058 and 9.121 seconds respectively. The small
timing difference does not establish a build-speed improvement

With an identical app and Applications shortcut in `work/stage`, compare codecs

```sh
hdiutil create -srcfolder work/stage -volname 'Bedrock for Mac' -format UDZO work/UDZO.dmg
hdiutil create -srcfolder work/stage -volname 'Bedrock for Mac' -format ULFO work/ULFO.dmg
hdiutil verify work/UDZO.dmg
hdiutil verify work/ULFO.dmg
```

The final image was mounted read-only and all 1,047 recorded resource hashes
and the complete app signature were checked. The helper's bytes are unchanged

### Comparison limits

No Windows or native Java Edition baseline was measured. Faster-than-Windows,
native Bedrock performance and universal FPS improvements are not established
by these results. A gameplay comparison needs the same Bedrock world, camera,
resolution, render distance and warm shader caches on the reference systems

The current candidate requires macOS 27 and Rosetta. It is an ad-hoc signed
local preview; notarization, dependency redistribution review and clean-Mac
installation remain separate release work
