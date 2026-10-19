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
  src/launcher/BedrockLauncher.swift src/launcher/Adventure.swift src/launcher/Landscape.swift src/launcher/Biome.swift src/launcher/Mobs.swift src/launcher/Structures.swift src/launcher/Journey.swift src/launcher/Assets.swift src/launcher/NBT.swift tests/launcher.swift -o build/launcher-checks
build/launcher-checks
```

The native checks cover progress bounds, stage transitions, all six motion stop
conditions, release filtering, bounded selection and passage cancellation
Original synthetic fixtures exercise archive bounds and empty stubs, numeric
pack precedence, gzip/NBT decoding, UV orientation, legacy bind transforms,
case-insensitive parents, cycles, malformed model vectors, queued cancellation
and failure delivery on the main thread. CI needs no game art
The Python fixture checks the approved poster fallback, isolated preview identity,
simulated status output and cancellation

To check the art from your own installation as well:

```sh
BEDROCK_SCENERY_DATA="$HOME/Library/Application Support/Bedrock for Mac/game/data" build/launcher-checks
```

This read-only integration constructs all 62 resident types, the dragon, 37
independent habitats and three passages. It checks distinct Blaze rods, Breeze
wind layers, mirrored dragon bounds, mob placement away from void, node/triangle
budgets, camera-action replacement and portal endpoints. It does not launch Minecraft

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

The scenery renderer is capped at 20 fps, with no per-frame SwiftUI timeline

### Expanded habitat 0.7 measurements

On October 19, 2026, the installed-art check constructed 62 mob types, the dragon,
37 independent habitats and all three passages. All habitats stayed below the
existing 1,200-node / 150,000-triangle limits. The 18 repeated mansion rooms share
one geometry. The source-only fixtures and all 91 Python tests passed

All 37 area renders and 24 passage viewpoints were inspected offscreen
Paused comparisons at scene times 4 and 8 seconds allow at most one 8-bit channel
step for render rounding; the observed difference was one channel of one pixel
in the Pale Garden. They test the paused graph, not the application's full window

The M3 Pro / 36 GB Metal probe used the same 1040 × 760 render target and 4× MSAA
as the earlier probe, with ten warm-up frames and sixty measured command buffers
per view. Scene time advanced in 1/20-second steps; command completion was awaited
for both GPU timestamps and wall time. It covered every habitat plus three
viewpoints per passage, 46 views total

| Realm or passage | Views | GPU median range | Highest GPU p95 | Highest wall p95 |
| --- | --- | --- | --- | --- |
| Overworld | 20 | 0.61–1.79 ms | 4.77 ms | 5.94 ms |
| Nether | 5 | 1.17–1.43 ms | 4.15 ms | 5.38 ms |
| End | 6 | 0.53–1.04 ms | 2.53 ms | 3.62 ms |
| Sift interpretation | 6 | 0.64–0.84 ms | 1.16 ms | 2.00 ms |
| Mine crossing | 3 | 0.43–0.47 ms | 1.00 ms | 1.67 ms |
| Stronghold crossing | 3 | 0.32–0.49 ms | 0.84 ms | 1.42 ms |
| Rift crossing | 3 | 0.34–0.45 ms | 0.95 ms | 1.31 ms |

The 50 ms frame budget remains unchanged. Graphs contain 43–357 nodes and
3,126–118,664 logical triangles, including passage views
Sequential graph construction measured 5.47–101.03 ms with a fresh Assets instance,
shared material/metadata caches between stops and archive buffers released after
each build. Construction stays on the existing serial background queue

Before mesh reuse and palette classification, the same 0.7 probe measured
236.13 ms for the mansion and 1,023.81 ms for the bastion. These became 42.87 ms
and 101.03 ms respectively, with unchanged geometry counts. The earlier 0.6
composition's maximum build was 646.27 ms and its highest GPU/wall p95 was
11.45/13.45 ms. Background load and compositions differ between runs; these are
local scenery probes, not controlled app latency or Windows/gameplay benchmarks
No resident-memory reduction or long-session result is claimed

The local tour is 132 seconds: all 37 habitats at 9× scenery speed, with the
22-second mine, 20-second stronghold and 16-second rift shown in real time

### Original-asset 0.6 measurements

On October 19, 2026, all 31 area views and fifteen passage viewpoints rendered
successfully from the installed Minecraft art. Eleven paused-frame comparisons
were identical. The pages contain 97–286 nodes and 15,682–86,500 triangles
The 104-second local scenery video shows all areas at 9× tour speed and the
three passages in real time; it is not a recording of the app window or gameplay

The same M3 Pro/36 GB method below sampled forty views at 1040 × 760 with 4× MSAA,
ten warm-up frames and sixty measured frames per view. Snapshot and movie tools
had finished before measurement; unrelated user applications remained open

| Realm or passage | Views | Median GPU range | Highest GPU p95 | Highest wall p95 |
| --- | ---: | ---: | ---: | ---: |
| Overworld | 14 | 4.40–5.01 ms | 11.45 ms | 13.45 ms |
| Nether | 5 | 4.68–5.45 ms | 10.67 ms | 12.27 ms |
| End | 6 | 4.34–4.87 ms | 10.09 ms | 11.23 ms |
| Sift | 6 | 4.62–4.98 ms | 10.49 ms | 12.45 ms |
| Mine | 3 | 1.48–1.59 ms | 6.85 ms | 7.48 ms |
| Stronghold | 3 | 1.20–1.73 ms | 6.13 ms | 6.69 ms |
| Rift | 3 | 1.39–1.51 ms | 6.45 ms | 7.17 ms |

All measured views fit the 50 ms frame budget. This does not establish application
or game performance. Graph construction ranged from 4.57 to 646.27 ms, including
cold asset reads; it now runs on the serial asset queue. Enqueueing a cold real-art
scene returned in 0.03 ms in the native check and delivered the completed graph
on the main thread. That is an API measurement, not measured input latency

Compared with the earlier procedural preview below, original assets add cold
loading work while retaining a similar GPU budget. No speedup is claimed

### Earlier 0.5 measurements
The superseded 0.5 preview streamed three neighbouring areas into one graph instead of retaining
all 31 stops. Its eleven pages use 98–242 nodes, 8,138–38,848 triangles and 17–44
materials. Native checks enforce fewer than 250 nodes, 45,000 triangles and at
most 48 materials, plus at least six residents on each page

The native check covers the full 42-species catalogue, all area pages, camera
action replacement, pool placement, Creaking visibility only at dusk, bounded
selection, automatic timing, rapid passage replacement and skip behaviour
An optimised run constructed the actor studies, eleven pages and three passages
in 118 ms including framework initialisation

All 31 areas and fifteen passage viewpoints were rendered offscreen for inspection
All eleven pages produced identical frames with both scene and renderer paused
Exposure adaptation is disabled so a still scene does not change its brightness
A 104-second offscreen video shows every area at 9× tour speed and all three
14-second passages in real time. It records authored scenery, not the app window

The final M3 Pro/36 GB probe rendered 1040 × 760 with 4× MSAA into reused Metal
textures. Each view warmed ten frames, then sampled sixty frames at 20 fps scene
times. GPU timestamps exclude image readback; wall times include submission and
waiting. Our snapshot and movie renderers had finished before this measurement

| Realm or passage | Views | Median GPU range | Highest GPU p95 | Highest wall p95 |
| --- | ---: | ---: | ---: | ---: |
| Overworld | 14 | 3.72–6.12 ms | 11.67 ms | 13.70 ms |
| Nether | 5 | 4.51–4.65 ms | 11.08 ms | 12.71 ms |
| End | 6 | 4.27–4.88 ms | 10.40 ms | 12.26 ms |
| Sift | 6 | 4.57–5.37 ms | 10.88 ms | 12.56 ms |
| Mine crossing | 3 | 1.86–2.27 ms | 5.90 ms | 7.60 ms |
| Stronghold crossing | 3 | 1.70–1.91 ms | 5.66 ms | 7.31 ms |
| Rift crossing | 3 | 1.99–2.22 ms | 6.35 ms | 7.86 ms |

The earlier twelve-view 0.4 probe measured 4.15–5.24 ms median GPU, with a maximum
10.88 ms GPU p95. The expanded scenes add species and landmarks while remaining
inside the 50 ms budget for 20 fps in this probe; this is not a speedup claim
Warm construction measured 2.34–10.62 ms, with 13.85 ms for the first graph
This excludes framework/renderer startup and does not establish app launch speed

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
