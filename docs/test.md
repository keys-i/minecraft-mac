# Testing and validation

Run checks from the repository root. Prefer tests that reproduce a failure at
its real boundary; avoid tests that only restate implementation. Documentation
changes need link, command, export, and checksum checks, not a fresh game install.
Dated sections below retain evidence for their named builds; they do not describe the current worker language

## Build 36 Look around readiness

October 23, 2026, on Apple M3 Pro, 36 GB RAM and macOS 27.0.1
All 25 Rust unit checks and four integration checks pass, with rustfmt and Clippy warnings denied
The native synthetic suite checks that raw collision data alone cannot enable Look around and that readiness requires the nearest 25 rendered meshes plus a 49-chunk raw-data halo

The optional saved-world check reads the generated seed-10 village at chunk 13,12 and installs its scene at `216.5, 74.62, 200.5`
The first frame retains a 256-block horizon while outer chunks remain eligible for background streaming
The same process passes the installed-art sweep of 86 species, heroes, 43 areas and three passages in 9.798 seconds

The build 36 package verifies 1,583 resource digests and strict deep signatures with a measured minimum macOS version of 27.0
Its authorised helper is byte-identical to the installed build 32 helper
These checks establish the corrected readiness boundary and package integrity, not sustained interactive FPS, thermal behaviour or a complete 512-chunk preparation
Live keyboard, mouse, minimap, Escape and continued outer-ring streaming remain to be checked after the active older launcher and generator have been quit normally

## Build 35 loading, fluids and natural routes

October 23, 2026, on Apple M3 Pro, 36 GB RAM and macOS 27.0.1
All 25 Rust unit checks and four integration checks pass, with rustfmt and Clippy warnings denied
The final native synthetic suite and installed-art sweep pass 86 species, heroes, 43 areas and three legacy passages
The optional-world check installs all 1,089 core meshes from 1,225 cached chunks and captures the clear sixteen-chunk horizon

New regressions cover compact opaque/glass and mixed-fluid vertex buffers, gradient top UVs, shallow side UVs, native frozen-river/ocean colours and fog, and edited distant terrain
The live seed-10 scenery exposed valid secondary vegetation beneath snow, which the former water-only layer guard rejected
An independent read of its 387 cached nearby chunks identified snow with grass, ferns, bushes and flowers; the [Wiki snowlogging reference](https://minecraft.wiki/w/Snowlogging) corroborates that Bedrock mechanic
Secondary vegetation now uses a batched mesh with primary-block placement context, and complete-cell edits remove both layers
Rig checks cover bind-preserving gaze, horse neck yaw/pitch limits, parrot symmetry, turtle flipper axes, axolotl swim/floor tracks and matching cube size/collision
Route checks cover cancellation, deterministic reopening, raw-data ownership outside the mesh radius, and continuously swept portal entry
Adaptive-resolution checks cover its bounds, thermal reduction and recovery hysteresis

A matched, read-only CPU probe runs three passes over the same cached world, with no game or compiler active
Median 49-chunk horizon preparation changes from 4,565.38 to 197.37 ms, and decoding from 176.56 to 137.54 ms
Median construction and voxel lighting for the same 25 chunks changes from 1,694.06 to 1,599.61 ms
The complete probe's peak memory footprint changes from 249,758,560 to 237,617,992 bytes
Both probes use whole-module optimisation with `-O`; these are bounded construction measurements, not sustained interactive FPS, game speed or whole-launcher memory results

The native renderer now records submitted frame intervals; actual display presentation still requires separate live profiling
The corrected build 35 package verifies 1,583 resource digests and strict deep signatures, with the installed authorised helper unchanged
Computer Use inspects the normal and fullscreen menus, merged Keyboard & Mouse page and the 16-chunk setting on the user's saved seed 10
It then intermittently reports `noWindowsAvailable`, capture failures and a file-picker timeout; later candidate exits have macOS exit status 0
The live attempts have not reached a prepared Look around scene, so no interactive frame, ten-minute memory/thermal or Bedrock performance result is established
The installed build 32, player worlds, accounts and game graphics settings remain unchanged
Cube jump power/squish and parrot flap timing remain explicit scenery approximations where installed definitions depend on unavailable runtime state
Full game-AI parity, native ARM64 execution of the x64 game and a completed 512-chunk preparation remain unverified

## Build 34 shared rendering and rigs

October 21, 2026, on the same M3 Pro and macOS 27.0.1
All 25 Rust unit checks and four integration checks pass, with rustfmt and Clippy warnings denied
The native suite passes the installed-art sweep of 86 species, heroes, 43 authored areas and three legacy passages
Focused checks cover adult/cub polar bounds and scale, native rabbit tracks and swept hops, separate head attention, constant setup channels and preserved inverse binds
Wolf, parrot, guardian/elder, witch, evoker and turtle calm poses use the effective installed animation definitions

Rendering checks cover secondary water, complete-cell edits, fluid families, cutout occlusion, transparent depth groups, native seagrass/kelp states and cached flipbook timing
The portal overlays retain the same material clock, and the installed panorama supplies the cold scenery background
The broader village sweep caught floor-support logic incorrectly coupled to full-cube occlusion; path/farmland support is now shared independently
The existing composter-height, four-worker routine and reachable-interior checks pass with that correction
The rendered portal check caught the need for an opaque depth layer beneath its star atlas; all nine portal cells now have that backing in both generated and authored scenes
The final native sweep and rendered cave/portal/contact-sheet checks pass after that correction

In the same process, the 12-fixture terrain-band reference takes 211.07 ms versus 64.73 ms for section runs, with identical material/medium spans
The synthetic light field takes 10.04 ms, retains 812,544 bytes and uses 4,875,264 bytes for dense construction arrays
These are bounded fixture results, not game-startup, sustained FPS, thermal or whole-launcher memory measurements
The player game remains open during these checks

The isolated official-server request completes all 1,225 requested coordinates, including 686 not marked complete, using one lifecycle and bounded ticking-area windows
A later final-protocol request saves another chunk and exits through area cleanup, normal stop and `Quit correctly`, without the inappropriate live-backup `save resume` command
No player world, account helper or Keychain entry is used by these generator checks
The independent native reader reopens all 1,225 chunk records, constructs all 1,089 core meshes and installs the sixteen-chunk scene before enabling Look around
Its captured first frame keeps a 256-block clear horizon, without the nearby unfinished-chunk fog
That complete optional-world regression process takes 50.22 seconds and reports 5,537,873,920 maximum resident bytes and a 1,674,102,776-byte peak memory footprint
The process includes synthetic checks, the full initial scene, its captured frame and the later artwork sweep; those figures are not launcher startup or steady-state memory measurements

The final 25-chunk image probe includes voxel lighting, cached animated frames and no MSAA
Its ten post-warm-up 1280 × 900 snapshot samples have p95 wall times of 8.66 ms for the village, 10.15 ms for the buried ruins and 9.23 ms for the End portal room
Mesh/light construction takes 1.96, 3.30 and 2.99 seconds respectively
Minecraft and app compilation are running during this image check, so it is diagnostic evidence, not a controlled build-to-build comparison or sustained interactive FPS result
The final build 34 candidate passes strict deep signatures and all 1,583 resource digests, with a measured minimum macOS version of 27.0
Its authorised helper is byte-identical to the installed helper, SHA-256 `706bba4f8cb08d90b080b0949dfd133e0a47f1122ee90693a54b058a05a280d6`

Read-only REA inspection establishes the installed executable's PE layout, while the effective installed client, geometry, controller and animation assets provide the model references
Full native game decompilation and complete AI parity remain unverified

## Build 33 scenery and journeys

October 21, 2026, on the same M3 Pro and macOS 27.0.1
The Rust suite passes 23 unit checks and four integration checks, with rustfmt and Clippy warnings denied
The native fixtures pass layout persistence, continuously swept routes, fallback-house reachability, liquid/support separation, partial-block clearance, imported head pitch, gait phases and cancelled distant-page recovery
The installed-art sweep covers 86 species, heroes, 43 authored areas and three legacy passages, plus the new cave/stronghold meshes and original generated first-world installation

An isolated official-server request saves all 403 chunks used by the longer real-world route check
The independent LevelDB version-record inspection finds zero missing chunks
Both complete routes also pass body-clearance sampling against the decoded real world after all scenery edits, including a reachable house chest for the End approach
The initial real-world check caught a grass block between sparse route points; the final builder clears the entire swept camera envelope after furnishing
Village, irregular cavern/city ruins and the grand End room have been rendered with the installed artwork and visually inspected

The earlier paired 25-chunk meshing comparison measured village 1.4445 → 1.1590 seconds, the preceding Nether-route scene 1.5495 → 1.1957 seconds and End-route scene 1.4170 → 1.1526 seconds
Those route images precede the natural-layout rewrite, so their timings are not comparisons of the final journey geometry
The final no-compiler/no-generator 25-chunk sample takes 1.262 seconds for the village, 1.254 seconds for the new cavern and 1.226 seconds for the new End room
At 1280 × 900 with 4× MSAA, ten sampled frame snapshots have p95 wall times of 19.66, 23.93 and 25.29 ms respectively
The combined run peaks at 489,947,136 resident bytes; it includes 403 decoded source chunks and three sequential scenes, so it is not an apples-to-apples comparison with the earlier 100-chunk run
Short offscreen snapshots are diagnostics, not proof of sustained interactive 60 FPS

Behaviour references use effective installed Bedrock 1.26.52.3 entity and animation definitions, including bat/bee/ghast goals, cod's fish identifier, amphibious pose states and drowned's calm bottom walking
The read-only behaviour audit did not launch or decompile the full game
The [Minecraft Wiki chunk reference](https://minecraft.wiki/w/Chunk) corroborates 16 × 16 columns and separate simulation/rendering coverage; its [drowned reference](https://minecraft.wiki/w/Drowned#Swimming) distinguishes swimming pursuit from supported movement
Native steering, speed conversion, combat and complete game-AI parity remain unverified

A 512-chunk request is tested for bounded near/ring scheduling and LOD selection, not a completed million-chunk preparation or sustained maximum-distance memory benchmark
Final live keyboard/capture, portal-skip, achievement and cape checks require opening the completed candidate after the installed app has been quit normally

## Scenery loading correction in build 32

October 20, 2026, on the same M3 Pro and macOS 27.0.1
Live inspection of installed build 31 found a stale generator-lock error followed by large chunk batches that queued repeated console probes and failed to commit their manifest
Only the first nine chunks of each visited dimension were available, leaving exposed scenery edges
Computer Use could inspect the installed launcher; the preceding rejection applied to the separate isolated Preview app

The corrected worker completes a 330-new-chunk request against the isolated official Bedrock generator in 50.27 seconds, exits successfully and emits `world_ready` after the manifest is committed
That command ran alongside native compilation and the open launcher; it is a completion check, not a controlled speed comparison
The generator log ends with `Quit correctly` and its owned server exits
Regression checks cover bounded console batches, duplicate replies, unfinished-chunk retry, lock handover and cancellation
All 20 Rust unit tests and four integration tests pass, along with rustfmt and Clippy with warnings denied

The loading/error message now sits in a centred, responsive Minecraft-style panel
Common flowers use crossed cutouts and their original matching textures instead of solid cubes
The final native installed-art suite passes flower cutout geometry, all matching flower textures, nearest-chunk batching and a real first-world installation at 232.5, 64.62, 696.5
Its 86-species, 43-area and three-passage artwork sweep takes 12,137 ms; this is test execution time, not rendering FPS
Unfinished mesh boundaries limit the fog horizon and captured movement until neighbouring terrain is drawn
The first-frame fixture checks a nine-chunk scene inside a requested 289-chunk area with animation stopped; its screenshot was inspected
The build 32 candidate passes strict deep signatures and all 1,583 resource digests
Its authorised helper is byte-identical to build 31, with SHA-256 `706bba4f8cb08d90b080b0949dfd133e0a47f1122ee90693a54b058a05a280d6`
After the user's normal-quit confirmation, build 32 is installed and passes the same payload/signature checks
Build 31 is preserved in the build 32 output's recovery directory
Computer Use confirms the centred panel and visible terrain in both the menu and Look around; the map reports 207, 74, 763 after movement
The installed scenery manifest grows beyond the original nine chunks, reaching 99 during this check

## Rust and seeded expeditions in build 31

October 20, 2026, Apple M3 Pro with 36 GB RAM and macOS 27.0.1
All 18 Rust unit tests and four CLI/export integration tests pass, as do rustfmt and Clippy with warnings denied
The GameInput port also verified the four pinned payload hashes against the installed MSI without installing or changing it
Project-owned source, scripts and exported tests contain no Python files or embedded Python programs

The optimised native suite passes camera continuity, species attention, forward movement, bounded nearest-chunk batching, chain clearance, invalid map coordinates and continuously sampled cave/stronghold routes
Its installed-art sweep passes 86 species, heroes, 43 areas and three legacy passages in 10,091 ms, excluding preceding regressions
Every chunk of both new portal plans also builds with the installed original assets
That is suite execution time, not launcher startup or FPS

The isolated Rust generator produced 100 real Overworld chunks around seed 0's village at 232, 696
The generator is the pinned official Bedrock 1.26.52.3 server, running in its separate loopback-only scenery prefix
No account helper, player world or game save was used for generation
Private offscreen probes render the real village and both underground plans with original textures
The real-village approaches and every following cave/stronghold segment pass continuous collision sampling
The approach planner reads the completed cave edits, so its flight cannot use the space now occupied by a new roof
Look around can interrupt either native expedition without changing the current world or camera

The rendering probe builds 25 neighbouring chunks per scene and records ten 1280 × 900, 4× MSAA SceneKit snapshots after three warm-ups
Compilers, Minecraft and the launcher were stopped for this measurement; other desktop applications were left running

| Scene | Mesh construction | Snapshot wall median / p95 | 1,000 short collision sweeps | 128 × 128 minimap |
| --- | --- | --- | --- | --- |
| Real village | 1.388 s | 7.93 / 16.19 ms | 0.368 ms | 26.53 ms |
| Buried Nether-route city | 1.414 s | 8.06 / 15.76 ms | 0.440 ms | 65.60 ms |
| Stronghold portal hall | 1.350 s | 8.45 / 12.41 ms | 0.440 ms | 60.38 ms |

The ten-sample nearest-rank p95 is the largest recorded value
This short offscreen process peaked at 339,869,696 resident bytes and a 702,219,320-byte memory footprint according to macOS `time -l`
Those are probe-process measurements, not whole-launcher memory, sustained FPS, maximum-distance rendering, battery or thermal results
Minimap work runs off the interaction thread and is cancelled when superseded

Three read-only installed-status processes measured 150, 90 and 90 ms with the previous Python worker, versus 60, 60 and 60 ms with the Rust release worker
These are process wall times from the same installed data, not game-startup or rendering speedups
The separate seven-process empty-installation benchmark has a 4.19 ms median; its 3.74–5.62 ms range does not access an account or Keychain
The native network fixture confirms IPv4 and IPv6 wildcard bindings become loopback, and a non-loopback binding fails with EACCES

The final app passes strict deep signatures, all 1,583 resource digests and internal-link containment, with a measured macOS minimum of 27.0
Its worker is ARM64 and its resources contain no `.py` or libpython files
The authorised helper remains byte-identical with SHA-256 `706bba4f8cb08d90b080b0949dfd133e0a47f1122ee90693a54b058a05a280d6`
After normal-quit confirmation, the installed app passes the same inventory and signature checks, matches the candidate executable and reports build 31
The original build 30 app is preserved as recovery
The DMG checksum passes, and its read-only mounted copy passes payload/signature checks and matches the candidate executable and resource inventory
The image was detached after verification

Computer Use's automatic approval review rejected opening the isolated preview with “Computer Use was not approved to use Minecraft Launcher Preview”
No alternate UI automation was used to bypass that rejection
Normal/fullscreen interaction, live WASD movement, VoiceOver, the Play handoff and sustained thermal/frame-rate behaviour remain unverified for build 31

## Terrain and controls in 0.17

The final build 30 source passes all 107 Python checks and both native suites
The installed-art sweep covers 86 species, 43 areas and three passages in
12,198 ms; that is sweep execution time, excluding its preceding input,
geometry and guided-flight regressions, rather than app startup time

Build 30 retains the four-boundary camera fixture before guided flight
Its regression also starts beneath a streamed terrain surface with a low roof
and with a wall containing the camera, requiring both structures to remain solid
Private source-backed probes check 384-block spacing, signed seed extremes,
repeatable terrain, eight village schedules and a completed village-to-forest route
The normal route caps movement at 0.40002 blocks and turning at 1.502° per
30 Hz update, with navigation activity ending exactly once on arrival

Original-art checks cover shared model rotations, mirrored UV faces, equine ears,
spider grounding, adult/baby villagers, dragon symmetry, attached torches, textured
chest bounds, bed faces, brewing arms and connected iron bars
The dragon's reflected branches share one local wing track; a source-backed
17-phase corner probe reports zero mirrored-coordinate error throughout the flap
Key-binding checks cover persisted-data validation, conflict swaps, reserved keys,
modifier-only bindings, reversed chord order and remapped arrow movement
Skin import checks reject invalid PNGs and unbounded file/pixel dimensions
Legacy avatar checks distinguish opaque padding from a transparent hat layer
Splash checks cover the original per-letter colour sequence, gold, reset and
literal preservation of unknown or incomplete formatting codes
Streamed water lighting is checked on both retained and newly attached chunks

The final habitat-budget probe passes all 43 areas without changing the limits
Badlands falls from 364,232 to 260,706 logical triangles with the same 380 nodes
Its 214,591 material/unit-face patches are identical to the preceding builder,
with matching tiled UV density and 22 collision-family checks
Forest and Meadow keep identical coverage and triangle counts
The largest final habitat is Mangrove at 321,110 triangles; Meadow has the most
nodes at 1,107, below the respective 350,000 and 1,200 limits

The final build 30 forest sample uses the same M3 Pro and macOS 27.0.1, with
Chrome for Testing open and no game, launcher or compiler running
Each fresh process records sixty frames after ten warm-ups and waits for GPU
completion; streamed maps finish loading before the sample

| Size and MSAA | Map | GPU median / p95 | Wall median / p95 |
| --- | --- | --- | --- |
| 1040 × 760, 4× | Default, 289 chunks | 4.04 / 4.46 ms | 7.86 / 8.50 ms |
| 1040 × 760, 4× | Maximum, 1,089 chunks | 2.35 / 4.94 ms | 8.23 / 10.53 ms |
| 2080 × 1520, 4× | Default, 289 chunks | 5.24 / 7.28 ms | 8.37 / 10.48 ms |
| 2080 × 1520, 4× | Maximum, 1,089 chunks | 6.07 / 7.94 ms | 11.78 / 13.52 ms |
| 2080 × 1520, 2× | Default, 289 chunks | 3.96 / 7.25 ms | 8.03 / 10.23 ms |
| 2080 × 1520, 2× | Maximum, 1,089 chunks | 4.45 / 8.41 ms | 10.35 / 14.29 ms |

All streamed samples retain five landmarks; default and maximum graphs have
2,772 / 4,404 nodes and 576,832 / 1,372,972 logical triangles respectively
The Retina 4× and 2× images were inspected; 4× remains the app default because
the paired wall-time p95 does not show a clear benefit from reducing quality
The Retina probe processes peak at 268,550,144 and 268,861,440 resident bytes
These are short offscreen samples, not sustained app/game FPS, input latency,
whole-app memory, battery or thermal measurements; file-cache state was uncontrolled

Computer Use inspected the installed build 30 in normal and fullscreen layouts
Settings and Help open inside the window with matching pixel type and working
close/Escape controls; key recording changed W → Up → W and Escape cancelled
recording without closing Settings
M hid and restored the left minimap, captured exploration hid pointer controls,
and Escape returned to the menu without starting the game
The final player marker and Notch face were inspected after the legacy-hat fix
Held movement did not produce reliable coordinate changes through computer-use
automation, so no live WASD/Space movement pass is recorded
Native movement/chord tests pass; game handoff, VoiceOver, sustained use and
larger-fullscreen performance were not exercised in this pass

The candidate, installed app and read-only DMG copy match the final packaged
executable, all 1,054 resource hashes and 21 internal links
The graphics bridge, authorised helper digest and strict deep signatures pass
The local DMG is 127,564,044 bytes, SHA-256
`ca7e2aa63aff71c6c41cda3dcfe9de493efe280ca77c0c558931740a607ad9eb`
Its mount was detached after verification

### Preceding build 29

Build 29 corrects gravel placement and glass after the first local build
The full [Gravel](https://minecraft.wiki/w/Gravel), [River](https://minecraft.wiki/w/River),
[Glass](https://minecraft.wiki/w/Glass) and [Glass Pane](https://minecraft.wiki/w/Glass_Pane)
Wiki articles were read through the public parse API, alongside
[World generation](https://minecraft.wiki/w/World_generation)
An installed-art probe checks 22,082 dry grassland samples without gravel
Its waterbeds contain 625 gravel, 782 sand, 522 dirt and 292 clay columns
The original mansion window and village house have 144 and 36 checked glass
triangles respectively, with UV widths matching their actual block-space widths
Clear, white and red panes load distinct original face/edge textures
Their 960 × 700 offscreen renders were inspected

The 0.17.0/build 29 source passes 107 Python tests and both native suites
The installed-art sweep covers 86 species, 43 areas and three passages in
16,194 ms, which is test execution time rather than app startup time
The focused geography probe checks original/regenerated chunk equality, the
first 25 destination coordinates, Sulfur Caves, five cave layers, open shafts and
closed roofs, exact foundation masks, real guided descent, cache bounds and cancellation
Across 1,066 sampled outskirts cells, 148 have landmarks, 544 neighbouring
pairs repeat their biome and 19 surface climates appear. Missing landmarks leave
no orphan plots, paths or village residents. A sampled boundary has seven heights
and a maximum adjacent step of one block; 2,221 sampled columns contain water
Sand/gravel banks are present. Ten 33 × 33 sampler grids took 6.79 ms total

The original fountain has 77 foundation cells, including six restored path
connectors. Hiding its fluid geometry changes 13,368 pixels in the same 960 × 700
offscreen render. Imported fluids remain visible and outside collision category 2
The native suite samples both guided portal routes every 50 ms, alongside
traversable junctions, solid end walls and iron bars
Both complete guided camera routes pass the collision sweep

Native checks cover wheel accumulation/debounce, invalid map coordinates,
spider eye emission and opaque skin, baby-villager arms, original bat flight,
and spectator map reports while ambient actions are paused. Inactive spectator
windows stop map reporting without enabling continuous rendering
Merging same-height ceiling runs reduces Lush Caves from 374,340 to 321,120
logical triangles, retaining the existing 350,000-per-habitat budget

The preceding build 29 renderer was sampled on an M3 Pro, macOS 27.0.1, with no
game or compiler running and Chrome for Testing left open. Each 1040 × 760,
4× MSAA sample uses ten warm-up frames and sixty recorded frames, waiting for
GPU completion. Both streamed samples finish loading before measurement

| Forest view | Chunks / landmarks | GPU median / p95 | Wall median / p95 |
| --- | --- | --- | --- |
| Single habitat | Authored tile | 3.07 / 5.42 ms | 7.12 / 8.88 ms |
| Default 8-chunk radius | 289 / 5 | 3.37 / 5.79 ms | 8.19 / 12.14 ms |
| Maximum 16-chunk radius | 1,089 / 5 | 4.02 / 6.03 ms | 17.37 / 23.84 ms |

The default graph has 2,669 nodes and 696,926 logical triangles; the maximum
has 4,749 and 1,388,874. The maximum-distance wall p95 exceeds the 16.7 ms
spectator target. The preceding build's smaller default graph measured 7.67 ms
wall p95, so these samples do not establish an overall speedup
They are short offscreen launcher measurements, not game FPS, startup time or
sustained thermal, battery and memory-growth tests

## Map, resident and presentation checks in build 27

The 0.16.0/build 27 source passes 107 Python tests and both native suites
The installed-art sweep covers 75 species, 42 areas and three passages in
35,833 ms, which is test execution time rather than app startup time

New checks exercise four-direction map crossings and bounded scene retention,
Escape position/direction preservation, guided travel, faster flight controls,
native baby models, adult cat scale, original herd declarations, horse heading
and diagonal gait, continuous bat flight, crystal levitation and dragon beams
Bat flight is sampled for a full minute so several random route segments run
Habitat minimums allow solitary native spawns rather than requiring two of every mob
Ground-clearance samples now run without installed art as well as in the scene sweep
Every species is checked against its visible presentation heading while moving
Horse, bat, dragon and outward/returning villager routes also have focused checks

A focused streaming probe checks signed chunk coordinates, 144 authored terrain
sections, complete 81-chunk loading at radius 4, the 1,089-chunk maximum,
distance changes, cancellation, pause/resume and disposal
It also checks both-axis crossings, guided travel, negative outskirts, floating
origin, historical Far Lands arrival/return and no late attachments after disposal

The final optimised renderer was sampled locally on an M3 Pro, macOS 27.0.1,
with Minecraft and compilers stopped and Chrome for Testing left running
Each 1040 × 760, 4× MSAA view used ten warm-up frames and sixty recorded frames,
waiting for GPU completion each time. The connected sample fully loaded all
289 default-radius chunks and five landmark graphs before recording

| Sample | GPU median / p95 | Wall median / p95 |
| --- | --- | --- |
| Single forest | 2.74 / 3.97 ms | 4.38 / 5.87 ms |
| Streamed forest | 4.55 / 5.10 ms | 6.68 / 7.67 ms |

The connected graph contained 2,562 nodes and 609,844 logical triangles
This is a short offscreen launcher-rendering sample, not game FPS, startup time,
a maximum-distance benchmark or a sustained thermal/battery measurement
The direct clear-sweep path took 7.30 ms for 100 calls versus 61.51 ms for the
retained axis-step comparison in the same graph

Runtime regressions cover inherited override filtering, helper environment
isolation, private atomic script updates, stale symlinks and failed-write cleanup
The native worker boundary preserves session/presentation keys while rejecting
inherited `CX_`, `WINE` and `DYLD_` keys
The packager signs and verifies bare Wine executables before bundle signing
All ten packaging checks pass after this change
The frozen worker's Python runtime disables bytecode writes, and a post-launch
resource check found no changed or extra bundle files

All four adult meadow villagers have reachable work, gathering and distinct bed
routes, including the temple altar stair. Checks cover committed collision-mask
restoration, hinged doors/trapdoors, bell atlas, irrigated paths, weather emission
gates, sun/cloud geometry, copper oxidation stages and the requested named cameos

The optional bridge passes seven Python tests with 19 native presentation
scenarios, ten packaging tests and both original hardware graphics probes
The final Metal completion orders the retained owning window on the main thread
and publishes its PID only after `NSWindow.isVisible` succeeds
The isolated window probe confirms frame, PID and accepted application activation
Its Core Graphics onscreen flag remains false, so this probe alone does not prove
Minecraft's visible handoff or fullscreen behaviour

The final candidate and installed build pass all 1,054 resource hashes, internal
symlink checks, bridge verification and strict deep signature verification
The account helper retains SHA-256
`706bba4f8cb08d90b080b0949dfd133e0a47f1122ee90693a54b058a05a280d6`
Computer Use started the final installed app but returned `cgWindowNotFound`
Its inventory listed the launcher as running; a Finder fallback was rejected by
automatic approval review. Final-build Settings/picker/Far Lands visual checks
and a real game-window handoff remain unverified

## Water and guided travel in 0.16

Version 0.16.0/build 26 retains the build 25 runtime and authorised account helper
The installed `water_still_grey` atlas has alpha 240/255, while the installed
default biome declares `water_surface_transparency` 0.65. The launcher now applies
both factors instead of treating atlas alpha as the complete surface opacity
Biome colour/opacity overrides and the default fallback share one cached lookup
Out-of-range or non-finite opacity is rejected
The [Minecraft Wiki water article](https://minecraft.wiki/w/Water), read through
its public API with curl, confirms animated biome-tinted translucency and
double-sided exterior water planes. Double-sided surfaces are retained

Guided map travel aims ahead across terrain during vertical legs and toward the
local landmark on final approach. A native regression prevents the initial climb
from facing straight into the sky. Synthetic checks cover biome opacity,
fallbacks and invalid values; installed-art checks cover the resulting material
alongside all 75 species, 42 areas and three passages. All native checks and
101 Python checks pass. The installed-art habitat/passages sweep took 57,417 ms
This is test execution time, not launcher or game startup time

Computer Use inspected the actual installed 0.16.0 title screen, translucent
village fountain, opaque mobs and grey controls, then entered spectator mode,
sent a held movement key and returned with Escape. Earlier in the same session,
the identical Settings implementation opened with Command-comma and closed
with Escape. Pointer hover, VoiceOver and Reduced Motion were not exercised

At 0.929 seconds after the Play click, the first captured frame showed the full
dirt/loading screen. By 11.819 seconds its status read Starting game; a later
process check confirmed the Windows executable. These are observation times,
not exact transition timings. No sign-in/security prompt was accepted by automation
The Wine game was absent from the Computer Use inventory and its bundle lookup
was rejected, so its first rendered frame and menu could not be inspected
The test session then ended and an older app on the mounted disk image launched
another game. That session was preserved. Handoff, exit restoration, black-frame
elimination and end-to-end startup improvement therefore remain unverified

REA re-inspected the actual signed Wine loader as x86_64 Mach-O, SHA-256
`e8d5c0be93e480ba0838c820cf2cdf3550125a24f4c4e4df4f524d7bd9a6815a`
Parent Evidence `ev_783c455de5232d07e828cc485932a38e7bb6efd419a77b3882867c6b4b255bca`
This confirms the inspected artifact identity, without establishing live OS
permission labels. Full-game native decompilation remains unavailable

The assembled app preserves all 1,053 build 25 resource digests and passes strict
deep signature verification. Its verified DMG is 128,664,927 bytes, SHA-256
`30655370cad9ad3c66378d2e2f346ff74d26a29b00f68b7df3e568a4dbff11a6`
The bundle remains an ad-hoc signed macOS 27 local preview

## Connected map and loading screen in build 25

Build 25 replaces the whole launcher scene with the installed Bedrock loading
background and reversible ten-frame atlas after Play. The animation uses 10 fps
and stops with Reduced Motion, Low Power Mode or an inactive window
No generation percentage is fabricated; Cancel retains the real worker policy
The previous game-window handoff remains a two-process transition

All 101 Python checks pass. Native synthetic and installed-art checks pass for
75 species, 42 areas and three passages. They cover loading-frame timing,
Play/warmup state gates, inherited colour-mask/blending rules, malformed material
inheritance, cat bind/tail pose, folded villager arms and five profession composites
New checks cover original held items, crown/jockey construction, hinged-door clone
state, road occupancy, recessed path-edge collision, common terrain seams and bidirectional map crossings that
preserve world position and direction. A guided area-selection regression traverses
the map; mansion checks place the jockey above its foundation and outside solid
geometry. The meadow requires exactly one tribute crown plus ordinary pigs/horses
The map retains at most three habitats

Native renders at 760 × 620 and 1040 × 760 cover the full loading screen
Original-art model renders show opaque/matte mobs, cats, professions, weapons,
the crowned pig and the mounted baby zombie. A connected-map boundary and the
village paths were also rendered and inspected. The crown is a launcher-made
tribute using the owner's block textures, rather than movie artwork

Minecraft Wiki was read through its public API using curl, including
[Cherry Leaves](https://minecraft.wiki/w/Cherry_Leaves),
[Dirt Path](https://minecraft.wiki/w/Dirt_Path),
[Door](https://minecraft.wiki/w/Door),
[Villager](https://minecraft.wiki/w/Villager),
[Water](https://minecraft.wiki/w/Water) and
[the movie pig](https://minecraft.wiki/w/Movie:Pig)
Installed resource/animation/material definitions supply the exact model and
texture references. No original game textures or models enter the source export

A same-process Metal probe used 1040 × 760, 4× MSAA, ten warmup frames and sixty
measured frames per view, before the final path-edge face correction. The single
forest and connected three-habitat
forest use the same active habitat/camera. Minecraft and Chrome for Testing stayed
running, and a compiler overlapped the sample, so these are budget observations

| Graph | Build time | GPU median / p95 | Wall median / p95 | Nodes / triangles |
| --- | --- | --- | --- | --- |
| Single forest | 579.16 ms | 5.56 / 9.39 ms | 10.12 / 15.80 ms | 604 / 186,684 |
| Connected forest | 2,544.62 ms | 5.81 / 9.77 ms | 11.32 / 17.96 ms | 1,808 / 534,210 |

Both samples fit the 33.3 ms idle budget. The connected graph exceeds the 16.7 ms
spectator target at p95; sustained 60 fps and memory growth remain unverified
Neighbour construction runs on the existing asset queue after the first habitat
A separate matched probe measured 100 identical clear camera sweeps through the
connected graph: the previous axis sweep took 93.02 ms and the direct clear-sweep
path took 10.22 ms. Both produced the same endpoint. Blocked sweeps retain axis
sliding and the native collision regressions. This is not a game-startup speedup

REA inspected the signed x86_64 Wine loader without Hopper, parent Evidence
`ev_e3d6587eb7d33ae208a94eba03c2c8d6f1c2371c3b7222e8d09e3f1f21a13dd2`
The embedded plist was independently decoded and both name fields read
Minecraft Launcher. Its package identity remains `org.winehq.wine`
The launcher/helper resources are preserved except for that rebuilt loader
macOS controls permission labels and may retain existing identities

Live Computer Use could inspect the existing mounted build 24 launcher, but
rejected the isolated build 25 preview as an unapproved app. The active Windows
game was preserved. No live build 25 Play handoff, actual gameplay comparison,
security prompt label, VoiceOver or clean-Mac installation is claimed
The supplied temporary screenshot paths had disappeared before inspection

## Original assets and launcher handoff in 0.15

Minecraft Launcher is the app, window and menu name; the artwork reads
Minecraft Mac Edition with its splash at the main logo’s lower-right corner. Buttons start grey
and turn green on hover; the shared 120 ms enlargement respects Reduced Motion
Computer Use inspected the renamed 0.15 title screen and grey Play button
Pointer injection still returned `noWindowsAvailable`, so the green hover and
live Reduced Motion behaviour remain unchecked

The original installed asset definitions now supply seven horse coats and five
marking states, eleven cat skins, four llama coats and habitat-specific skins
Strays retain their original clothing layer and calm Evokers keep crossed arms
Unsaddled horse equipment is hidden. Cave Spiders, Evokers, Elder Guardians,
Pufferfish and Strays bring the roster to 75 species across 42 authored areas
Log/pillar axes and saved full-block facing now remap their original materials
without mutating shared upright materials. No original game assets are bundled

All 101 Python tests pass, including warmup without downloads/sign-in, active-game
protection, PID filtering, real child PID reporting, spawn failure, timeout cleanup and a closed launcher output pipe that must not
stop the owned child
Native synthetic and installed-art checks pass for 75 species, 42 areas and three
passages, including horse layers, Stray clothing, Evoker arms, log axes and furnace
facing. An offscreen original-art render was inspected for those models and blocks

Five installed-art habitats were measured sequentially with the old and new
scenery sources, using the same optimised Swift probe at 1040 × 760 with 4× MSAA
Each sample uses 10 warmup frames and 60 measured frames. An initial run kept
Minecraft active; a repeat after it closed kept Chrome for Testing and the normal
workspace running. Native compilation overlapped the repeat, so these remain
budget observations rather than a controlled speedup or actual Minecraft FPS result
The repeat produced these p95 values

| Scene | Previous wall p95 | Current wall p95 | Current GPU p95 |
| --- | --- | --- | --- |
| Meadow village | 15.07 ms | 15.03 ms | 8.74 ms |
| Woodland mansion | 15.75 ms | 23.02 ms | 11.36 ms |
| Warm reef | 14.50 ms | 26.79 ms | 12.28 ms |
| Frozen ocean | 12.13 ms | 20.69 ms | 10.36 ms |
| Abandoned mineshaft | 11.13 ms | 10.73 ms | 8.16 ms |

These samples fit the 33.3 ms idle budget. New graph construction ranged from
154.51 to 600.26 ms on the existing asset queue; first-scene asset loading is
included. The full native checks retain the per-area node and triangle ceilings

Background warmup uses the existing preparation locks and never starts the
account helper or downloads a missing game. Five unchanged-prefix CLI preparation
samples had median 33.83 ms, range 29.39–40.21 ms, excluding frozen worker startup
and app wiring. No end-to-end Play-to-game speedup has been established
The runtime now reports the actual spawned Wine PID; native matching waits for
an onscreen normal game window before hiding the launcher, and ready/error
restores it. The wait ends with the owned session rather than a fixed timeout
Computer Use verified return to Play after the user quit Minecraft normally
The user reported a black window during build 23 handoff. Build 24 uses app-level
hide/unhide instead of ordering out an individual window, and removes the blocking
Keep Open alert while a game runs. Native checks verify the gameplay quit policy
Final live build 24 handoff verification remains pending; the active game was preserved
This is a two-process handoff, without shared-window embedding

REA bound the owned x86-64 executable, but Hopper readiness timed out before
native strings/xrefs produced evidence. Installed material definitions establish
separate culling/blending rules; the launcher's shared cutout shader remains an
approximation. The task-owned provider process and temporary runtime were cleaned up

The 0.15.0/build 24 local app includes a rebuilt frozen worker. All 981 original
runtime/helper payload files remain byte-identical; its 1,053 resource hashes,
strict deep signature verification and DMG checksum pass. It still requires
macOS 27. Developer ID signing, notarisation, clean-Mac installation, VoiceOver
and display-zoom workflows remain unverified

## Responsive Settings and dragon healing beams in 0.14

The title no longer stops growing at 700 points. Native renders cover 760 × 620,
1040 × 760, 2016 × 1310 and 2560 × 720 windows, with title widths of 532, 728,
1411.2 and 900 points. Width and height constrain the artwork, subtitle and splash
together; the shortcut toast occupies the next row instead of covering the title
Regression checks cover fullscreen growth, doubled bounds and short ultrawide windows
Build 20 was opened through Computer Use and its larger title verified in fullscreen
The final native synthetic checks and all 93 Python tests pass

Build 22 enlarges Play, inventory, Look around and corner text to 5× their area in the
2016 × 1310 render. The same four window sizes use 1.55×, 2.14×, 2.24× and 2.12×
scales. Native checks require the fullscreen factor, separated inventory/spyglass
targets and smaller scaling when setup copy needs space
The final build was inspected live in fullscreen. Desktop pointer automation
returned `noWindowsAvailable`, so hover timing and the live Reduced Motion path
remain unverified. Source guards retain immediate brightness feedback without motion

Settings is an in-window Minecraft menu with a top-right close button, Escape
and ⌘, support. Its heading and close button stay visible while content scrolls
Action labels start at 20 points and body copy at 16 points; available width and
height scale the layout up to 1.5×. Native renders cover 760 × 620, 1040 × 760 and
1440 × 1000 launcher windows. The former fixed-width preferences title bar is gone

Regression checks cover bounded/monotonic scaling and mutually exclusive Help
and Settings state. The volume control keeps its pointer, keyboard and accessibility
adjustments; menu visibility suppresses spectator capture, hints and scenery motion

The central island now has one healing beam from the closest crystal within
32 blocks to the moving dragon. It uses the owner's original beam texture and
an eight-sided native mesh, with UV/transform updates instead of geometry rebuilds
Native animation checks verify the static Reduced Motion connection, its moving
dragon endpoint and removal beyond range
The central scene adds one node and 96 triangles. All 93 Python tests and
70-species/42-area/three-passage installed-art checks pass
Live Computer Use opened Settings through the gear and ⌘, inside the launcher
The × and Escape closed it while preserving the launcher; its volume accessibility
actions remained exposed. VoiceOver and display-zoom workflows were not exercised
This is a visible healing connection in authored scenery, with no combat/health model

## Flight, destinations and repeat-launch checks in 0.13

All 93 Python tests and installed-art native checks for 70 species, 42 areas and
three passages pass. New regressions reject a camera inside a solid volume,
check every area's initial free position, require tree canopy collision categories,
verify continuous bat travel over sixty 100 ms samples and verify crystal bobbing
with a stationary base. Existing cancellation, lifecycle and input checks remain

The picker uses an in-window list, original block textures, search, arrow navigation,
wrapping names and a selected state. It suspends automatic area changes while open
Native renders cover the normal/narrow launcher, Overworld/Nether lists, the corrected
cherry approach and crystal shells. Impeccable 4.6 context/refinement guidance,
its source detector and ECC verification informed this pass

Repeat preflight now recognises same-file graphics aliases and avoids rehashing
the upstream bridge library within one verification. Distinct copies still undergo
digest comparison; each new verification reads the bridge again. Four alternating
samples on unchanged installed bytes reduced the median from 62.86 ms to 29.38 ms,
17 to 8 hash calls and 92,512,240 to 43,015,404 bytes. The frozen worker's unchanged
status path independently took 146.21–170.78 ms across three samples
A same-method render sample used ten route/elevated/interior views, 1040 × 760,
4× MSAA, ten warm-up frames and sixty measured frames per view. Baseline/candidate
highest GPU p95 was 14.80/9.17 ms and wall p95 was 19.06/19.21 ms. Construction
ranged 52.52–579.27/67.64–1036.43 ms; additional canopy/volume checks add work
All samples fit the 33.3 ms idle frame budget; the wall-time tail exceeds the
16.7 ms spectator target. Background load was uncontrolled, so this establishes
neither a rendering speedup nor sustained 60 fps. No browser was closed

These are preflight measurements, not an end-to-end Play speedup. Initial samples
under contention took seconds, so the larger launch delay remains unresolved

Computer Use inspected the mounted 0.12 launcher and invoked Play; its status
reached “Minecraft is running”. The Wine game was absent from the app inventory,
and direct selection returned “Invalid app: Minecraft.Windows.exe”. The available
Computer Use interface supplies no video recorder. No actual gameplay, gameplay
recording, hands-on comparison or VoiceOver assessment is claimed
REA/Hopper identified the mounted 0.12 binary by its SHA-256 and confirmed the
camera's old reverse-route action and explicit world-up call in machine code
The 0.13 candidate was also opened live. Search, no-results feedback, Escape,
selected states and arrow focus were exercised. Return from a focused row exposed
an underlying Play shortcut, which started the game; the final source disables
background controls during the picker and handles Return/Space on its rows
That final keyboard correction is compiled but not live-retested because the
running game still uses the earlier candidate's resources. Those files stay intact
Source inspection, native tests and renderer samples establish the new behaviour

## Explorable structures and saved fixture states in 0.12

All 92 Python tests and native checks for 70 original mob profiles, 42 areas and
three journeys pass locally. Regression checks cover original behaviour hitboxes,
adult/calm groups, numeric movement ranges, zero speed and malformed attributes
Banner colour/pattern pixels, captain skins, wall facings, brewing bottle slots,
doors, hatches and ladders are checked against installed assets and template states

Native segment queries verify the mine branch, stronghold library and wider
portal room, plus temple/monument interiors and their retained solid walls
Passage residents move during twenty simulated seconds; the idle camera retains
a level horizon. End City approach clearance excludes nearby chorus branches
Normal/narrow UI, fixture, mine, stronghold, banner and realm renders were inspected
The stronghold's side lava uses animated floor surfaces rather than raised cubes

REA/Hopper inspection of the old and final packaged camera action confirms the
change from `lookAt:` to `lookAt:up:localFront:`. Impeccable's published refinement
guidance and ECC's interface/verification guidance informed the review; the
Impeccable context launcher was unavailable and was not installed

The paired sample uses an M3 Pro / 36 GB, 1040 × 760, 4× MSAA, ten warm-up and
sixty measured frames per view. Eight habitat route/elevated views and two
passage interiors run sequentially on 0.11 then 0.12 after build/render work ends
No browser was closed for these samples; concurrent game activity was not
recorded per view, so background load is a comparison limit

| Metric | 0.11 baseline | 0.12 candidate |
| --- | ---: | ---: |
| Highest GPU p95 | 10.11 ms | 8.44 ms |
| Highest render wall p95 | 12.79 ms | 11.47 ms |
| Scene construction range | 31.89–562.98 ms | 45.76–552.60 ms |

Both remain within the 50 ms scenery budget. These samples do not establish a
game FPS improvement, Windows comparison or long-session memory result
The final apps pass deep/strict ad-hoc signature and source machine-code checks
All 1,051 baseline resource hashes and 21 symlinks remain unchanged
The [0.12 artifact record](status.md#exploration-and-placement-corrections-in-012)
contains the verified DMG size, digest and platform requirement

Live inspection of the mounted 0.11 launcher showed the corner credit/version
over scenery without a grey footer strip. Computer Use did not approve the
isolated 0.12 preview, and its inventory did not expose the running Wine game
macOS blocked reads from the supplied temporary HEIC paths. Live pointer capture,
VoiceOver, audible transitions and hands-on gameplay comparison remain unverified
Authored scenery still lacks full game AI, brewing, block interactions and
continuous Minecraft generation. No existing world was opened or binary release published

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
| Worker/session behavior | Rust suite; targeted cancellation/helper-lifetime regression; local app check when UI behavior changes |
| Helper/account/download behavior | Rust worker and helper tests; deliberate live check only when required |
| Swift launcher | Native build plus visible local checks for affected states |
| Wine account/Realms patches | Pinned-source checks, rebuilt runtime, XUser tests, and relevant probe/game test |
| Graphics/runtime assembly | Build and overlay verification, graphics probe, game launch on the target Mac |
| Packaging | Rust validation checks, signature/resource/DMG verification, Applications launch with existing data |
| Documentation/export list | Relative links and examples, source-export tests/check, regenerated source inventory |

## Offline source checks

These checks do not read an account, Keychain entry or installed game

```sh
cargo fmt --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked
./minecraft source check
shasum -a 256 -c tools/SOURCE-SHA256.txt
git diff --check
```

The Rust tests cover request validation, safe export, simulated-worker isolation, setup receipts and locks, account-socket ownership/recovery, owned-process cancellation/timeouts, GameInput validation, bounded transfers and monitoring thresholds
The export integration checks a real reviewed export, stale-inventory rejection, refresh and preservation of an existing destination
Counts are dated evidence, not a target to preserve

`./minecraft source verify` checks already fetched upstream revisions and patches without changing them
`source fetch` uses the network
Refresh changed reviewed files with `./minecraft source inventory` before checking their inventory

## Native app and helper

```sh
./minecraft build launcher
./minecraft build test
BEDROCK_SCENERY_DATA="$HOME/Library/Application Support/Bedrock for Mac/game/data" build/launcher-checks
```

The native builder includes the pinned LevelDB bridge and every current launcher source
Tests use the same optimisation as the app, with debug assertions enabled
Synthetic checks cover archive/NBT bounds, model transforms, key bindings, cancellation, motion gates and continuously swept portal-route clearance
The optional installed-art suite builds all original resident types and authored habitats, plus every chunk of the new cave/stronghold plans
It verifies their real materials and geometry without launching Minecraft

`./minecraft build preview` creates an isolated simulated Rust-worker app for first-run, progress, cancellation and completion checks
The preview rejects scenery/setup commands and never launches Wine or accesses an account
Use the [accessibility checklist](accessibility.md#manual-checks-still-needed) for visible focus, smaller/larger windows, keyboard capture, long text, Reduced Motion and Low Power Mode
The primary chunk renderer targets 60 Hz; the dated measurements below also include the earlier custom scenery renderer

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
./minecraft setup helper
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
./minecraft runtime probe graphics
```

Expected graphics evidence includes successful HRESULTs and
`RedPixel=0xFF0000FF`. Account, Store, and privilege probes can prompt and contact
Microsoft. Never run those under the assumption that all probes are offline.

## Verify a packaged artifact

```sh
./minecraft build verify --app 'build/packaged/Minecraft Launcher.app'
hdiutil verify 'build/Minecraft-Launcher-preview.dmg'
shasum -a 256 'build/Minecraft-Launcher-preview.dmg'
```

The Rust verifier checks the complete signature, exact resource inventory, internal symlink boundaries and measured minimum macOS version
The app builder runs it before publishing a new candidate directory
These checks establish consistency with the locally recorded artifact, not notarisation or a clean-Mac installation

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

[`.github/workflows/checks.yml`](../.github/workflows/checks.yml) runs Rust
formatting, Clippy, regression tests, allowlist and inventory checks on Linux, plus native
Swift checks and pinned Rust helper tests on macOS 15. Actions and the Rust
toolchain are pinned. CI does not package Wine, run Minecraft, access Keychain,
or certify that the full app supports macOS 15. Confirm checks belong to the
exact PR commit before merging.

The [security workflow](../.github/workflows/security.yml) analyses Rust with
CodeQL on pushes, pull requests and weekly. Native Swift compilation is covered
above; Swift CodeQL tracing did not complete during validation and remains
unverified. CodeQL does not analyse upstream native sources

The [source-release workflow](../.github/workflows/release.yml) reuses all source
checks at the same commit before creating the allowlisted archive. A manual run exercises
packaging without a GitHub release; a `v*` tag additionally publishes a source
prerelease. Neither path builds or publishes a runtime DMG
