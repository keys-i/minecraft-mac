# Testing and validation

Run checks from the repository root. Prefer tests that reproduce a failure at
its real boundary; avoid tests that only restate implementation. Documentation
changes need link, command, export, and checksum checks, not a fresh game install.
Test counts below describe the October 19, 2026 source snapshot

## Choose the relevant checks

| Change | Validation |
| --- | --- |
| Worker/session behavior | Python suite; targeted cancellation/helper-lifetime regression; local app check when UI behavior changes |
| Helper/account/download behavior | Python orchestration suite and Rust helper tests; deliberate live check only when required |
| Swift launcher | Native build plus visible local checks for affected states |
| Wine account/Realms patches | Pinned-source checks, rebuilt runtime, XUser tests, and relevant probe/game test |
| Graphics/runtime assembly | Build and overlay verification, graphics probe, game launch on the target Mac |
| Packaging | Python packaging tests, signature/resource/DMG verification, Applications launch with existing data |
| Documentation/export list | Relative links and examples, source-export tests/check, regenerated source inventory |

## Offline source checks

These checks do not use the user's account, Keychain, or game data:

```sh
python3 -m unittest discover -s tests -p 'test_*.py'
python3 minecraft.py source check
shasum -a 256 -c tools/SOURCE-SHA256.txt
git diff --check
```

The Python suite currently has 91 tests. Coverage includes source isolation,
one helper across download/preparation/launch, safe account error messages,
process cancellation, setup-marker corruption, runtime relinking, reduced
download verification, and packaged minimum OS detection. The count is a dated
snapshot, not a requirement to keep it fixed.

After fetching upstream sources, verify their pinned patched state:

```sh
python3 minecraft.py source verify
```

That check is offline; the initial `tools/source.py` fetch is not. If an
exported source file changed, first regenerate `tools/SOURCE-SHA256.txt` following
[Source releases](build.md#update-the-source-inventory).

## Native app and helper

Compile the interface on a Mac with Command Line Tools:

```sh
python3 minecraft.py build launcher
xcrun swiftc -parse-as-library -D LAUNCHER_TEST -module-cache-path build/swift-module-cache \
  src/launcher/BedrockLauncher.swift src/launcher/Adventure.swift src/launcher/Landscape.swift tests/launcher.swift -o build/launcher-checks
build/launcher-checks
```

The native checks cover progress bounds, stage transitions, all six motion
stop conditions, release URL/installer filtering and bounded scene graphs for
all four worlds without opening a window. Texture checks enforce shared 16 × 16
maps, sharp filtering, cubic Ghast bodies and attached, varied tentacles
The Python preview test verifies an
isolated bundle identity, internal fixture root, status output and cancellation

Use `python3 minecraft.py build preview` to inspect first-run, progress,
cancellation, retry and running-game states without touching a real account
Its fixtures stay in ignored build output. A fixture proves UI behavior only. The worker
protocol and ownership model are in [Architecture](architecture.md).

For the redesigned window, also check narrow and wide sizes, long errors,
Return/Escape, visible keyboard focus, scene selection, pause/resume,
Reduced Motion, Reduce Transparency and Low Power Mode
with the [accessibility checklist](accessibility.md#manual-checks-still-needed)
The October 19 interface build compiled locally, but Computer Use denied access
to its disposable preview, so these visible checks remain unverified

The live scenery renderer is capped at 20 fps. SwiftUI launch controls have no
per-frame timeline, and the earlier 24 MiB of panorama image data is no longer
loaded. World graphs use shared pixel textures and a single batched terrain mesh
The current Overworld/Nether/End/Sift graphs have 200/162/152/179 nodes,
42,756/39,234/8,548/43,052 triangles and 29/17/17/22 materials respectively
Native checks enforce budgets, multiple residents, three camera areas per realm,
bounded area selection and cancellation of superseded camera journeys

All twelve area views were rendered offscreen for inspection. Pausing both the
scene and renderer produces identical frames; exposure adaptation is disabled
so a still scene does not keep changing its brightness

An optimised M3 Pro/36 GB probe rendered 1040 × 760 with 4× MSAA into reused Metal
textures, warmed ten frames, then sampled 60 frames for each of the twelve areas
GPU timestamps exclude image readback; wall times include submission and waiting
The actor baseline renders the preceding mob study without the environment

| Realm | Actor baseline median GPU | Full-world median GPU range | Highest full-world GPU p95 | Highest wall p95 |
| --- | --- | --- | --- | --- |
| Overworld | 0.60 ms | 4.58–5.24 ms | 10.88 ms | 12.09 ms |
| Nether | 0.51 ms | 4.30–4.77 ms | 9.19 ms | 10.39 ms |
| End | 0.63 ms | 4.15–4.98 ms | 9.82 ms | 10.95 ms |
| Sift | 0.61 ms | 4.46–5.11 ms | 10.14 ms | 11.55 ms |

The full worlds do more work than isolated mobs and fit the 50 ms GPU budget
for 20 fps in this probe. Warm full-graph construction measured 2.52–9.48 ms;
this excludes framework/renderer startup and does not establish launch speed
The unoptimised native check constructed the actor studies and four landscapes
in 226 ms including framework initialisation on one run

These checks cover authored scenery, not application menus, focus or the complete
SwiftUI/SceneKit composition. Actual foreground CPU/GPU use, background wakeups,
energy use, long-session memory and keyboard/VoiceOver workflows still need
measurement on the running app. No launcher or game speedup is claimed

Prepare the current standalone helper example and run its tests after quitting
Minecraft and letting its helper stop. The builder rejects any active
`standalone_helper`, including one in a packaged app:

```sh
python3 src/standalone-setup.py --build-helper
cargo +1.98.0 test --release --locked --manifest-path sources/xodus/Cargo.toml \
  -p xodus-cli --example standalone_helper
```

There are currently 12 default helper tests and two ignored live fixtures.
Default tests use fake/in-memory token storage and check cache reads, denied
reads, failed writes, sign-out, package paths, and URL policy. Do not add
`--include-ignored` to routine tests: the ignored Keychain fixture creates its
own random entry, and the ignored CDN fixture makes a live request. Neither
proves the prompt behavior of a user's saved account.

## Wine and graphics

After building standalone Wine, run:

```sh
bash tests/run-xuser-tests.sh
```

This compiles against the actual patched headers and runs 31 claim checks and
19 Realms-routing and 18 token-refresh checks using synthetic data. It uses the separate
`runtime/standalone-wine-prefix` and writes `build/standalone-wine/xuser-*-test.log`.
It does not access Microsoft. See [tests/XUSER.md](../tests/XUSER.md).

The graphics probe requires the owned game/runtime prerequisites and prepares
the standalone game prefix; it is not a pure source test:

```sh
./tools/build/probes.sh
python3 minecraft.py runtime probe graphics
```

Expected graphics evidence includes successful HRESULTs and
`RedPixel=0xFF0000FF`. Account, Store, and privilege probes can prompt and contact
Microsoft. Never run those under the assumption that all probes are offline.

## Verify a packaged artifact

`minecraft.py build app` verifies the final bundle signature and records hashes of
regular resource files in `Contents/Resources/payload-sha256.json`.
`minecraft.py build dmg` verifies the DMG. To check an existing default artifact:

```sh
codesign --verify --deep --strict 'build/packaged/Minecraft for MacOS.app'
hdiutil verify 'build/Minecraft-for-MacOS-preview.dmg'
shasum -a 256 'build/Minecraft-for-MacOS-preview.dmg'
python3 - <<'PY'
from pathlib import Path
import hashlib, json, plistlib
app = Path('build/packaged/Minecraft for MacOS.app')
resources = app / 'Contents/Resources'
inventory = json.loads((resources / 'payload-sha256.json').read_text())
for name, expected in inventory.items():
    actual = hashlib.sha256((resources / name).read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit('Resource differs: ' + name)
with (app / 'Contents/Info.plist').open('rb') as file:
    print('Minimum macOS:', plistlib.load(file)['LSMinimumSystemVersion'])
print('Verified resource files:', len(inventory))
PY
```

Adjust paths for a separately named build. These checks detect changes relative
to the recorded artifact; they do not authenticate game downloads or establish
notarization. Opening an app assembled on the developer's Mac does not reproduce
Gatekeeper's handling of a downloaded app on another Mac.

## Manual test record

Use a separate macOS account or test Mac for clean-state tests; do not erase the
owner's worlds or Keychain to simulate a new user. The person testing enters
their own credentials and handles security prompts. Record one row per scenario
with date, app commit/artifact checksum, macOS/chip, game version, initial data
state, action, observed result, and any reviewed diagnostic excerpt.

| Scenario | Expected result |
| --- | --- |
| DMG → Applications | App opens from Applications; all runtime components come from that bundle |
| Missing Rosetta or unsupported OS | Clear prerequisite message before account setup |
| Fresh owner sign-in | One helper owns sign-in, download, setup, and play; correct gamertag is confirmed in game |
| Cancel, close sign-in, deny Keychain, interrupt network | Actionable state, owned processes cleaned up, safe retry, existing data preserved |
| Repeat launch, unchanged helper | After the tester chooses Always Allow, measure whether saved access is remembered; record the exact number of prompts |
| Quit/reopen launcher window | Session remains alive while Minecraft runs; window can be reopened |
| Quit/relaunch game | Returns to Play and launches successfully again |
| Save and reopen a world | A disposable test world survives normal quit and relaunch |
| Sign out and switch owner account | Game/worlds retained; new account ownership checked; no old user session restored |
| App replacement | Existing game/worlds retained; new bundle links used; prompt count recorded rather than assumed |
| Multiplayer | Separately record server entry, Realm listing, active Realm entry, and friend-session joining |

These are acceptance criteria, not claims that each row has passed. Put observed
results in [Release status](status.md), including failures and untested cases.

## Continuous integration

[`.github/workflows/checks.yml`](../.github/workflows/checks.yml) runs Python
3.12/3.14 source tests, allowlist and inventory checks on Linux, plus the Python suite, native
Swift build/policy checks, and pinned Rust helper tests on macOS 15. Native process metrics
and exclusive-rename tests run on macOS and are skipped on Linux. Actions and the Rust
toolchain are pinned. CI does not package Wine, run Minecraft, access Keychain,
or certify that the full app supports macOS 15. Confirm checks belong to the
exact PR commit before merging.

The [security workflow](../.github/workflows/security.yml) analyses Python with
CodeQL on pushes, pull requests and weekly. Native Swift compilation is covered
above; Swift CodeQL tracing did not complete during validation and remains
unverified. CodeQL does not analyse Rust or upstream native sources

The [source-release workflow](../.github/workflows/release.yml) reuses all source
checks at the same commit before creating the allowlisted archive. A manual run exercises
packaging without a GitHub release; a `v*` tag additionally publishes a source
prerelease. Neither path builds or publishes a runtime DMG
