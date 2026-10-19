# Testing and validation

Run checks from the repository root. Prefer tests that reproduce a failure at
its real boundary; avoid tests that only restate implementation. Documentation
changes need link, command, export, and checksum checks, not a fresh game install.
Test counts below describe the October 20, 2026 source snapshot

## World geometry and menu fidelity in 0.11

The 0.11 candidate corrects the native alpha handling that discarded Enderman
eye pixels and made Blazes translucent. Original rod animation constants,
standing head attachment and the copper golem’s separate eye layer are applied
Imported wheat/carrot rows, wall torches, bell supports, lantern UVs, farmland,
fluid levels and village foundations now use their appropriate geometry
Terrain domain edges, undersides and Nether ceilings are closed

Prepared native mesh queries reject resident paths through walls and generate
collision-checked camera/sky-resident routes. Flight uses short swept segments
and slides along obstacles. The asset queue commits new actions before handing
the graph to the presentation renderer; the regression requires at least four
village residents to move during twenty simulated seconds of idle hover
The stronghold descends over forty blocks. Portal surfaces cover departure,
then a matching colour transition joins a portal/platform arrival to the hover
Submerged lava uses dense orange fog instead of clear terrain visibility

Settings shares the title screen’s stone controls and includes master volume
Help stays in-app. Long biome names scroll while active and remain static with
Reduced Motion. The extruded Mac Edition face, overlapping installed splash,
advancement-style hint and full-bleed root retain the corner credit/version
Offscreen normal/narrow native layouts, models, fixtures, villages and portal
endpoints were inspected. Full-window footer removal, pointer capture,
VoiceOver, audible changes and complete real-time cycles remain manual checks
Computer Use denied preview access; no other desktop-control route was used

All 92 Python tests, native fixtures, the installed-art checks for 70 species,
40 areas and three passages, and all 125 reviewed source checks pass locally
Newer residents include camel husks, parched, nautiluses, zombie nautiluses and
happy ghasts; missing newer art is skipped on older owner installations
The renderer still does not implement every block state or the game’s full AI

The paired offscreen sample uses an M3 Pro / 36 GB, 1040 × 760, 4× MSAA,
ten warm-up and sixty measured command buffers for eight route/elevated views
Both builds flush pending graph actions before measurement. Chrome for Testing
remains open, and the two runs execute sequentially after other render work
Synthetic flight measures one hundred bounded 50 ms movement advances per view

| Metric | 0.10.1 baseline | 0.11 candidate |
| --- | ---: | ---: |
| Highest GPU p95 | 11.65 ms | 11.26 ms |
| Highest render wall p95 | 13.84 ms | 13.73 ms |
| Highest movement-input p95 | <0.01 ms, without collision | 4.86 ms, with collision |
| Scene construction range | 41–178 ms | 158–561 ms |

Rendering stays inside the existing 50 ms budget. Geometry preparation and
collision routing add background construction work; these samples do not
establish a speedup or measure game FPS, Windows performance or long-session RAM

The separate 0.11 full app and isolated preview pass deep/strict signature
checks. All 1,051 baseline resources and 21 runtime symlinks remain unchanged,
including helper, worker, runtime, bundled font and approved poster. Native
machine code matches the source build; minimum packaged macOS remains 27
The local LZFSE DMG verifies and is 127,982,563 bytes, with SHA-256:

```text
2802e655ce318e1e079489da51f7128cbb7ba8b5b2ae26c64db4c5c0f961261f
```

No installed app, game, account or saved world was replaced. No binary release
was published; Developer ID signing, notarisation and clean-Mac installation
remain separate release checks

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

The Python suite currently has 92 tests. Coverage includes source isolation,
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
  src/launcher/BedrockLauncher.swift src/launcher/Music.swift src/launcher/Adventure.swift src/launcher/Terrain.swift src/launcher/Landscape.swift src/launcher/Biome.swift src/launcher/Mobs.swift src/launcher/Structures.swift src/launcher/Journey.swift src/launcher/Assets.swift src/launcher/NBT.swift tests/launcher.swift -o build/launcher-checks
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

This read-only integration constructs all 65 resident types, the dragon, 40
independent habitats and three passages. It checks distinct Blaze rods, Breeze
wind layers, mirrored dragon bounds, mob placement away from void, node/triangle
budgets, sampled camera ground/headroom, swimming placement, original fluid atlas
frames, reconstructed window panes, camera-action replacement and portal endpoints. It does not launch Minecraft

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

### Material, hover and input fidelity in 0.10.1

The October 19, 2026 native fixtures cover alpha-preserving RGB tinting, matching
warm/cold geometry, river water versus land travel, the twelve-second hover loop,
Control sprint, twenty-minute daylight endpoints and bounded classic chances
Installed-art integration builds all 65 species, four supported base-pack classic
variants, warm/cold variants, 40 habitats and three passages. It verifies installed
plains/river water colours, fluid alpha/lighting, day/night sky visibility and the
existing scene/camera budgets. All 92 Python tests also pass locally

Source-generated layouts include native offscreen host renders of the developer
Link and long errors. Narrow/normal/wide views verify the splash over the title,
pixel actions/glyphs, lower-left developer, lower-right version, advancement hint
and removal of the scenery Play/pause button and extra hotbar backing
Day, dusk and night views were generated for meadow, river and reef, alongside
Nether and End views. Isolated before/after fluids reproduce the grey-water fault
and verify the blue biome tint and removal of doubled lava brightness

The existing M3 Pro / 36 GB probe compares four route views with four elevated
flight views at 1040 × 760, 4× MSAA, ten warm-up and sixty measured frames
Chrome for Testing stays open; other render probes finish first

| Area | Route GPU p95 | Flight GPU p95 | Flight wall p95 |
| --- | --- | --- | --- |
| Meadow village | 8.69 ms | 10.05 ms | 14.21 ms |
| Jungle temple | 9.96 ms | 10.60 ms | 14.56 ms |
| Crimson Forest / bastion | 9.09 ms | 8.80 ms | 12.13 ms |
| End City / ship | 9.52 ms | 9.10 ms | 10.76 ms |

The highest GPU p95 rises from 8.66 ms in the 0.10 eight-view sample to 10.60 ms
The highest wall p95 rises from 11.95 to 14.56 ms. All sampled views remain inside
the unchanged 50 ms budget; no speedup is claimed. Overworld daylight adds four
nodes and 1,156 logical triangles per scene. The complete area integration stays
within the existing 1,200-node / 350,000-triangle ceilings

The renderer still does not implement every Minecraft block/state or the full
Molang, navigation, combat, breeding, village-job or spawning systems. Classic
appearances use retained base-pack art at a launcher-only 10–15% chance, chosen
when an area is built. They are not an authentic modern-Minecraft spawning rule
Full-window mouse capture/release, developer-link activation, VoiceOver, a complete
real-time twenty-minute cycle and long-session memory remain manual checks
No desktop capture or substitute UI automation bypassed the earlier access denial

### Spectator flight, title artwork and music in 0.10

On October 19, 2026, the native synthetic and installed-art checks pass, alongside
all 92 Python tests. New regressions cover the 60/70-second hint deadlines,
refocus, dismissal, flight direction, diagonal normalisation, delta caps,
vertical movement, arrow aiming, boundary debounce, safe arrivals across all
areas, Escape/disposal, biome wrapping and all four audio pause gates
Synthetic silent audio checks native playback, pause/resume, stop and cancelled
loads without audible output. Installed-art integration checks the original
hotbar/title, subtitle font, splash pool, menu/Sweden paths and native Ogg decoding
This verifies decoding/preparation, not an audible listening session

Source-generated layouts cover normal, narrow, long biome, portal, first-run,
progress, error, long scroll-backed detail, playing, spectator, hidden-hint and
missing-art states. The title/splash/hint overlap was corrected before packaging
The real preview window, physical flight input, timed focus transitions,
VoiceOver, audible transitions and long-session memory remain manual checks

The same M3 Pro / 36 GB Metal method compares the current route with an elevated
flight viewpoint (12, 72, 24), looking at (0, 4, −30). Each of eight views uses ten
warm-up and sixty measured frames at 1040 × 760 with 4× MSAA. Chrome for Testing
stays running; other render probes finish before measurement

| Area | Route GPU p95 | Flight GPU p95 | Flight wall p95 |
| --- | --- | --- | --- |
| Meadow village | 7.27 ms | 7.64 ms | 10.88 ms |
| Jungle temple | 7.39 ms | 8.14 ms | 11.46 ms |
| Crimson Forest / bastion | 8.66 ms | 8.51 ms | 11.95 ms |
| End City / ship | 7.31 ms | 7.51 ms | 9.10 ms |

These views retain the same 264–557 nodes and 103,064–264,190 logical triangles
Route and flight remain inside the existing 50 ms scenery budget. This is a
sample of elevated views, not exhaustive flight coverage or game FPS evidence
The flight timer runs only while keys are held; scenery remains capped at 20 fps
Music retains one player and one pending load, with source bytes bounded to
32 MiB and track duration to twenty minutes. No memory reduction is claimed

### Gameplay-reference composition in 0.9

The October 19, 2026 pass keeps the same 40 habitats and three passages, with
denser foreground placement, connected village plots/paths, shared cutout tree
canopies, patterned fish, coral fans and ceiling-attached cave vegetation
Actual gameplay images guided composition; [the reference sources](../assets/README.md#native-scenery)
are documented separately and their pixels are not shipped

All 92 Python tests, native synthetic fixtures and installed-art integration pass
New regressions cover village grading and clearings, shared canopy geometry,
fish pattern layers and the End cubemap. All 40 areas and 24 passage viewpoints
were rendered; all 40 paused comparisons remain within one channel step
Source-rendered first-run, ready, busy, error, long-detail and playing layouts
cover 760 × 620, 1040 × 760 and 1440 × 900 points

The same 49-view M3 Pro / 36 GB probe and method described below produced:

| Realm or passage | Views | GPU median range | Highest GPU p95 | Highest wall p95 |
| --- | --- | --- | --- | --- |
| Overworld | 23 | 4.27–7.38 ms | 12.00 ms | 14.71 ms |
| Nether | 5 | 5.84–6.77 ms | 11.00 ms | 13.55 ms |
| End | 6 | 3.28–5.37 ms | 7.01 ms | 8.35 ms |
| Sift interpretation | 6 | 4.12–6.88 ms | 11.39 ms | 14.12 ms |
| Mine crossing | 3 | 1.60–3.79 ms | 7.28 ms | 8.29 ms |
| Stronghold crossing | 3 | 3.33–4.69 ms | 6.96 ms | 7.47 ms |
| Rift crossing | 3 | 2.33–4.09 ms | 6.40 ms | 7.32 ms |

The testing browser stayed open and other scenery render tools had finished
Graphs contain 107–689 nodes and 24,046–303,452 logical triangles, inside the
unchanged 1,200-node/350,000-triangle limits. Construction measured 22.02–178.67 ms
Compared with 0.8, the added scenery raises the highest GPU p95 from 9.57 to
12.00 ms while remaining inside the 50 ms budget. No speedup is claimed
The final source stores village plots once instead of rebuilding their array
during height queries; the graph and rendering work remain the same

These are offscreen scenery measurements and source-generated layouts
Full-window interaction, VoiceOver, long-session memory and game performance
remain unverified. The 138-second tour shows authored scenery rather than gameplay

### Player-height worlds and launcher 0.8 measurements

On October 19, 2026, all 92 Python tests, native source fixtures and installed-art
integration passed. Integration builds 65 species, the hero actors, 40 habitats
and three passages. It samples camera ground/headroom every half-second and
checks swimming depth, original fluid atlases, connected mansion panes, shared
room geometry, cancellation and the existing motion gates

All 40 habitat renders and 24 passage viewpoints were reviewed offscreen
The paused graphs at scene times 4 and 8 stayed within one 8-bit channel step
Ready, first-run, download, error, long-detail and playing layouts were rendered
at 760 × 620, 1040 × 760 and 1440 × 900 points. SwiftUI ImageRenderer uses an
injected SceneKit snapshot; an offscreen NSHostingView verifies the scroll-backed
long detail that ImageRenderer omits. These are source-generated views, not a
desktop capture or an interactive window test

The M3 Pro / 36 GB Metal probe uses a 1040 × 760 render target, 4× MSAA, ten
warm-up frames and sixty measured command buffers per view. Scene time advances
in 1/20-second steps and command completion is awaited for GPU and wall timings
The testing browser remains running. The probe covers all habitats and three
viewpoints per passage, 49 views in total

| Realm or passage | Views | GPU median range | Highest GPU p95 | Highest wall p95 |
| --- | --- | --- | --- | --- |
| Overworld | 23 | 4.32–6.45 ms | 9.57 ms | 11.86 ms |
| Nether | 5 | 5.93–6.34 ms | 8.28 ms | 9.95 ms |
| End | 6 | 2.01–5.08 ms | 7.51 ms | 8.48 ms |
| Sift interpretation | 6 | 4.43–5.78 ms | 7.63 ms | 9.45 ms |
| Mine crossing | 3 | 1.86–3.48 ms | 6.76 ms | 7.46 ms |
| Stronghold crossing | 3 | 1.52–2.31 ms | 6.36 ms | 7.01 ms |
| Rift crossing | 3 | 2.25–2.41 ms | 5.89 ms | 6.49 ms |

The 50 ms frame budget and 1,200-node ceiling remain unchanged. The wider worlds
raise the logical-triangle ceiling to 350,000; observed graphs contain 107–717
nodes and 23,902–302,838 triangles. Mangrove is the largest mesh. Visible chunks
allow SceneKit to cull distant surfaces separately
Sequential graph construction measured 19.66–161.05 ms with a fresh Assets owner,
shared material/metadata caches between stops and archive release after each build
Construction remains on the existing serial background queue

These wider, denser scenes cost more than the 0.7 compositions. Different views
and normal background load prevent a controlled before/after FPS comparison
No gameplay, Windows-speed, input-latency, memory-reduction or long-session claim
follows from this scenery probe

The local 138-second tour shows all areas at 9× scenery speed and the 22-second
mine, 20-second stronghold and 16-second artistic rift in real time
Full-window gestures, keyboard focus, VoiceOver, accessibility preferences and
long-session growth still require manual checks

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
