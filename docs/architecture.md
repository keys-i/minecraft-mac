# Architecture

Minecraft for MacOS runs the owner's Windows Minecraft Bedrock installation on an
Apple Silicon Mac through WineGDK and DXMT. The intended user flow is **open the
app → Install & Play → Microsoft sign-in → Minecraft**, then **Play** on later
launches. A separate Minecraft welcome confirmation can still ask the user to
select **Sign in now**.

The repository is GPLv3 source with separately licensed upstream components.
It contains no Minecraft payload or Microsoft account. Current release status
and verified behavior live in [Release status](status.md). Original
CrossOver work is documented in [Earlier CrossOver implementation](architecture.md#earlier-crossover-implementation).

## Components

The repository root exposes one command, `minecraft.py`, alongside its README,
licence and Git configuration. App code lives in `src/`, developer tools and
native probes in `tools/`, and preserved upstream patches/notices in `vendor/`.
Installed app script names and the player's data directories retain their
existing contracts

| Command | Purpose |
| --- | --- |
| `python3 minecraft.py play` | Build missing source components and launch with monitoring |
| `python3 minecraft.py runtime --help` | Prepare, inspect, probe or launch an existing runtime |
| `python3 minecraft.py build --help` | Build the launcher, bundle the app or create a DMG |
| `python3 minecraft.py source --help` | Fetch/verify pinned upstreams, export source and manage checksums |
| `python3 minecraft.py monitor --help` | Inspect a session, mark a problem or stop the owned monitor |
| `python3 minecraft.py legacy --help` | Historical CrossOver launch/check path |

Use `COMMAND --help` for arguments. On a Mac without Command Line Tools,
`bash tools/bootstrap.sh` preserves the interactive prerequisites setup

| Component | Responsibility | Source of truth |
| --- | --- | --- |
| Native launcher | Window, Play/Cancel, status rendering, sign-out menu, worker lifetime | `src/launcher/BedrockLauncher.swift` |
| Worker | Installation checks, bundle wiring, setup lock, one account session, structured status | `src/launcher/setup.py` |
| Session runtime | Prefix preparation, account helper ownership, Wine environment, game launch | `src/standalone.py` |
| Account helper | Keychain cache, Microsoft login and license, game download, Xbox IPC | `src/standalone-helper.rs` and pinned Xodus patches |
| Acquisition tools | Helper compilation and verified Microsoft threading component | `src/standalone-setup.py` |
| GameInput preparation | Verify/extract known MSI files and prepare registry entries | `src/standalone-gameinput.py` |
| Windows compatibility | WineGDK with local GDK, Store, privilege, and Realms patches | `tools/source.py`, `vendor/patches/standalone-wine-*.patch` |
| Graphics | Pinned upstream DXMT and optional verified display-lifetime bridge | `tools/build/graphics.sh` |
| Packaging | Swift bundle, frozen Python worker, runtime inventory, local DMG | `tools/build.py` |
| Source distribution | Explicit reviewed file allowlist and checksum inventory | `tools/source.py`, `tools/SOURCE-SHA256.txt` |

The native title screen places a central Play button and compact four-slot realm
hotbar over one live SceneKit world. Busy/error states use a separate status panel
The installed game supplies the original title artwork, Minecraft Ten subtitle
font and splash pool. The Mac Edition subtitle uses an extruded face and sloped stone backing
The yellow splash uses a native repeating scale animation, removed when motion
is disabled, the launcher loses focus or a game/error/biome picker takes priority
Monocraft supplies the fallback title and shortcut toast; rounded system type
identifies actions, and plain system type supplies supporting copy
Original installed item icons and hotbar/selection textures supply the connected
inventory bar. Realm names and number shortcuts remain in help/accessibility labels
Stone controls and installed utility glyphs share hover, press and focus states
Action headings/buttons now use pixel type. The hotbar has no extra backing
The splash overlaps the title; the bottom corners hold a native developer Link
and the actual launcher bundle version. Scenery motion controls remain in Settings/View
The top-left biome name opens an in-window destination list with original block
textures, search, selected states and arrow-key navigation. Automatic biome travel
waits while the picker is open; native menus also give direct access
The corner spyglass control or ⌘L enters spectator flight in `FlightView`
Native `SCNCameraController` owns aiming; WASD moves, Space/Shift changes height,
arrows turn, captured relative mouse movement aims, and scrolling changes speed
between 2 and 32 blocks/s. Control doubles travel speed while held
Capture owns one local event monitor and restores cursor association/visibility
and the window’s previous mouse-event preference on release. It never installs
a global monitor, event tap or Input Monitoring service
A 60 Hz timer exists only while movement/turning keys are held; focus loss,
responder loss, hiding and teardown clear input. Delta time is capped at 0.1 s
Crossing an authored area boundary or pressing brackets loads the next/previous
biome in the current realm. Only one graph is presented; obsolete builds cancel
Arrival wraps to the opposite edge, preserves direction/relative height and
uses a safe landing when an End island gives way to void. These are authored
area swaps, not continuous Minecraft generation. Realm slots remain available
Leaving flight restores the current area route; teardown removes the recogniser
`ShortcutHint` owns the 60-second toast and subsequent 70-second focused wait
The view uses key-window notifications; the in-window Settings menu suppresses
shortcut hints, spectator capture and automatic scenery motion while open
One cancellable sleeping task handles deadlines without polling; a hidden toast's
wait restarts after focus is lost, while an already visible toast keeps its expiry
Entering flight replaces it with 60-second movement instructions; leaving
dismisses it. Setup, errors, passages and a running game suppress the toast
A running game disables Look around
`Music.swift` owns one native AVAudioPlayer and one cancellable load on the
existing serial asset queue. It reads original installed menu/game Ogg tracks
on demand, avoids an immediate repeat and limits each source to 32 MiB/20 minutes
Settings opens inside the launcher from the gear button or the app menu's ⌘, action
It has a persistent top-right close button and Escape dismissal, without a separate
preferences window or title bar. Text, spacing and hit targets scale with its bounds
from 20-point action labels / 16-point body copy to a maximum 1.5× scale
Content scrolls at compact sizes while the heading and close button stay visible
Settings owns the launcher’s master-volume control (default 18%); zero mutes it
The header has no separate sound control Losing launcher focus, occlusion or game launch pauses playback
Closing the view cancels the pending load and releases the player. Artwork,
fonts and audio remain in the owner’s installation and are never redistributed
`Assets.swift` reads original models, textures and structure templates from the
owner's installed `game/data` directory. `NBT.swift` decodes bounded gzip/NBT
structures; the archive reader supports the game's versioned `.brarchive` packs
Newer packs override older packs in numeric version order, and empty archive
stubs fall back to ordinary files. Nothing is extracted or copied from the game

`Biome.swift` defines 42 selectable habitats and landmark visits across four realms
`Landscape.swift` builds one complete habitat per selection, replacing the former
three-biome strips. `Terrain.swift` owns deterministic interpolated noise, ground
height, cave ceilings, clearings and 16 × 16 visible chunks. Buried faces are omitted
Domain edges and flat undersides close the terrain shell; Nether ceilings are capped
The same mesh builder supplies the forest above the mine and stronghold approaches
Static voxel meshes use SceneKit collision category 2. One temporary native
renderer prepares their transforms/geometry before offscreen segment queries
Completed graph actions are committed before moving from the asset queue to
the presentation renderer, so prepared scenes do not leave residents stationary
Residents reject wall-crossing strolls, retry bounded alternatives and retrace
their outward route. Idle camera paths are checked once at construction; flight
uses short swept segments and axis sliding, with foliage and structure faces
blocking travel. Original non-solid plants, rails and fluids do not block flight
Underwater viewing uses blue fog; submerged Nether lava has a 1.5-block orange
visibility limit rather than a clear view of the terrain underneath
Camera routes stay at player height or low spectator height, including underwater
Texture tint is baked once into cached RGB pixels while preserving original
alpha. Fluids use original biome colours, one alpha application and native atlas
frames at 20 fps for water / 10 fps for lava, without doubled lava emission
`Daylight` owns a twenty-minute Overworld sky rig with original sun/moon art,
batched stars and once-per-second lighting/fog updates. A shared asset epoch
preserves time between areas; motion gates pause visible updates. Nether, End
and underground scenes retain their environmental lighting
Idle camera routes form a continuous twelve-second hover loop with eased reversals
and an explicit world-up vector. Initial placement checks solid volumes and nearby
sightlines; animated tree canopies share the collision category used for scenery
Flight arrivals use the same free-position search when a destination contains a wall
Original block materials supply strata, vegetation, roots, fungi, chorus plants,
waterfalls and flowing water/lava. Tree canopies, clouds and bounded ambient
particles move independently of the camera
Village clearings follow individual building plots and their connecting paths,
instead of flattening and clearing an entire rectangle. Tree canopies share one
geometry per wood type within each scene. Near-camera placement brings plants,
fallen logs, roots, fungi, coral fans and ceiling-attached cave growth into view
Original cloud art moves above the Overworld; the original greyscale End sky is
darkened in a small native bitmap before it becomes the background cubemap

`Mobs.swift` shares original geometry/skins within each scene and places 70 types
in habitat-specific groups. Five newer types are skipped on older installations
when their original art is absent; malformed assets still fail clearly
Aquatic residents use water pockets, Striders use lava,
and fortress residents use bridge height. River residents follow the actual
channel, and land residents avoid water. Horses, cats, wolves, parrots and axolotls
use original skin variants. Tropical fish add the original pattern layer and colour
variants. Variant-specific geometry now takes precedence over default geometry
Residents use unsynchronised bounded strolls, original movement/stroll attributes
where available, sampled terrain/water bounds, diagonal gait timing, sheep
grazing and species-specific hops. Flying hero actors follow circular paths
Original behaviour collision boxes bound resident clearance rather than visual
limbs or Blaze rods. Adult/calm component groups provide movement attributes;
the midpoint represents original movement ranges in this scenery simulation
Flying residents turn while travelling instead of inheriting walking waits
End crystal shells follow the original installed bob/rotation formulas; bases stay still
Four eligible classic species use base-pack models at a daylight-dependent
10–15% launcher-only chance, selected once during scene construction
Classic prototypes stay within the current scene factory; no old-version
download, separate simulation, combat, breeding or village job system is added
The dragon stays at the central island. A single octagonal healing beam uses the
installed End crystal beam texture, follows the closest crystal shell within 32
blocks and disappears out of range. The dragon’s movement action owns its
transform and UV updates, keeping the endpoint aligned without a separate action
or geometry rebuilds. Reduced Motion retains a static connection
This illustrates the crystal connection without adding a combat/health simulation
Enderman and Blaze native shader alpha is treated as material data, preserving
opaque bodies and emissive eyes; the copper golem also receives its eye layer
Blaze rods, dragon parts and the Breeze's three original wind layers are assembled
from the installed assets. Ambient actions do not reproduce the game's AI or
complete animation system

`Structures.swift` imports original village, outpost, mansion, igloo, ruined portal,
Trial Chamber, Ancient City, bastion, fossil, shipwreck and End City pieces
The complete chamber surrounds an interior camera. Mansion panels
and End City towers/bridges are composed locally from original templates
Repeated pieces clone one decoded geometry per scene rather than reparsing NBT
Pane connections are rebuilt from saved neighbours, including templates that
defer their connection states until placement. Face culling classifies each palette
entry once, avoiding repeated string matching
for every block and its neighbours
Code-generated temples, huts, fortresses and passages use installed block textures
Some partial blocks and structure entities remain simplified; the launcher does
not reproduce world generation, the game renderer or its Molang interpreter
The importer reads banner mounting, facing, base dye and up to six saved pattern
layers, with the original captain-banner skin reserved for captain banners
Brewing stands render the saved bottle slots; doors, trapdoors and ladders use
their saved orientation and open state. These are rendered states, not brewing
or block-interaction simulations. Authored jungle/desert temples and the ocean
monument use wall/roof shells with reachable interiors

| Realm | Areas | Residents and landmarks |
| --- | --- | --- |
| Overworld | 25 | Villages, outpost, mansion, temples, witch hut, shipwreck, reef, river, ice spikes, monument, caves, Trial Chamber, Ancient City, mineshaft and stronghold |
| Nether | All five biomes | Piglins, brutes, Hoglins, Striders, Ghasts, Blazes, Wither Skeletons and magma cubes; fortress, bastion and fossils |
| End | Five biome areas and an End City visit | Dragon, Endermen, Endermites and Shulkers; caged crystals, chorus branches, gateway, city towers, bridges and ship |
| Sift | Six artistic areas | Existing illagers, Allays and Vex among coral, cherry trees, amethyst and rifts |

`Journey.swift` owns bounded selection and the 18-second area clock
The 22-second Nether entry descends a supported, ore-lined mine past side shafts,
cobwebs, a minecart and bats, then crosses a 4 × 5 obsidian portal into a lava/
fortress vista. The 28-second End entry descends over forty blocks into an Overworld stronghold, passes
side libraries and a Silverfish spawner, then approaches a raised 12-frame portal
Sift has a 16-second explicitly artistic rift approach
The mineshaft and stronghold are also persistent picker destinations sharing
their passage geometry. Terrain is carved around the mine branch and library
rooms; rock above their ceilings closes the surrounding surface. Mine branches
have end caps, broken rail junctions, timber supports and embedded ore veins
Passage residents use the same collision-checked strolls as habitat residents
Portal surfaces fill the departing camera before a colour-matched dimension
transition. Destinations start beside a corresponding portal or End spawn
platform, then join the existing hover path without a visible camera reset
**Skip journey** cancels a passage; another selection replaces it immediately
Reduced Motion and Low Power Mode select the destination directly
The existing graph remains visible during loading. Short native fades join scenes
only while motion is enabled; cancellation rejects obsolete graph results

The renderer targets 30 fps while idle and 60 fps during spectator flight. Native checks bound each habitat to 1,200 nodes
and 350,000 logical triangles; actual measurements are recorded in [Testing](test.md)
A serial asset queue builds scenes away from the interface thread. Cancelling a
selection drops queued work and ignores obsolete results; completed graphs move
to the main thread before presentation. The loader retains shared materials and bounded JSON metadata, drops archive
buffers after graph construction and keeps mob prototypes within the current page
`Adventure.swift` pauses and releases its scene when dismantled

Before game art exists, or when scenery is unsupported, the approved poster
remains visible and scenery navigation is unavailable. Setup and Play still work
The art loader refreshes after successful installation. A development or isolated
preview may read public art from the normal installed game directory, while its
worker remains isolated from accounts and worlds. No game art is redistributed
in source or the DMG, and no scenery service or model download is required

The Sift scenery follows the colourful terrain, rifts and illager presence in
[Mojang's Dungeons II announcement](https://www.minecraft.net/en-us/article/minecraft-dungeons-ii-is-live)
Its area names, flora and use of visiting existing mobs are artistic choices,
not announced Bedrock biomes or a claim about native Sift species. Its Java/Bedrock
arrival was announced for 2027; the launcher does not add it to the installed game

Ambient motion and automatic scene changes stop with Reduced Motion, Low Power
Mode, the pause control, an inactive app, an occluded window or a running game
The scene-change task cancels when its view disappears or its motion gate changes
The experience bar fills 40 segments from the worker's bounded overall
setup fraction; the four steps use the existing sign-in/download/preparation
boundaries. Percentages describe weighted setup progress, not bytes or an ETA

Resizing, keyboard shortcuts and the worker protocol remain native SwiftUI
behaviours; status changes request macOS accessibility announcements
`minecraft.py build preview` copies the real interface into a separate bundle
with `tests/preview.py` as its only worker and an internal fixture root. It has a
different app identity and does not access accounts, downloads or saved worlds
See [Accessibility](accessibility.md) for controls and outstanding manual checks

Settings uses the same pixel typography, stone buttons and square volume track
as the title screen. The volume track supports pointer, arrow keys and
accessibility adjustment. Help opens a local, dismissible guide with setup-log
access; reporting a problem remains a separate external action
Long biome names scroll only while the launcher is active; Reduced Motion
shows the full name over several lines
Settings stores scenery preferences in the app's own defaults. Edit, View,
Window and Help use native menu commands; About, Services and Quit remain macOS
app-menu behaviours. Check for Updates makes one bounded-time request to the
project's public GitHub releases API and distinguishes DMG releases from source
archives. It opens the fixed project Releases page for manual review; it never
downloads or replaces an app or game

The [stability notes](status.md#stability-fixes-and-earlier-gameplay-evidence) describe token renewal, device/title
authentication, recorded dead-socket recovery, and the optional graphics bridge.
The bridge's source provenance is included in packaged resources, with library
hashes recorded again after ad-hoc signing.

The account helper uses the real owner's Microsoft content license. The Store
callback compatibility patch does not fabricate ownership. DXMT handles
Direct3D 11; the launcher disables Direct3D 12 for the tested game path.

## Launch sequence

1. The native app runs the worker with `--status`, which reads existing state
   without signing in, downloading, or preparing a prefix.
2. Play starts the worker. It acquires `onboarding.lock`, copies current bundled
   scripts into the data directory, and points runtime/helper symlinks at the
   current app bundle. It checks hardware, OS, Rosetta, runtime, and free space.
3. For a new game, the worker starts one helper with `--download --serve-after`.
   For an existing game, it uses `--serve`. The helper checks the Microsoft
   session and ownership before exposing the Xbox service.
4. New or changed runtime setup acquires the verified threading DLL and prepares
   the separate Wine prefix, including GameInput. A setup signature makes
   unchanged preparation reusable.
5. `src/standalone.py launch` reuses the account service and runs
   `G:\\Minecraft.Windows.exe` in Wine. The outer worker keeps the helper alive.
6. Normal game exit returns the launcher to Play and stops the owned helper.
   Failure and cancellation unwind owned subprocesses; cancelled setup can be
   retried. Incomplete game downloads restart from scratch.

The app consumes newline-delimited JSON on worker stdout: `state`, `title`,
`detail`, and nullable `progress`. States include `new`, `ready`, `busy`,
`playing`, `cancelled`, and `error`; `checking` and `cancelling` are also used by
the front end. Only known progress lines and safe `BEDROCK_ERROR` codes are
translated into UI text. Arbitrary account output must not become UI text.

## Data and process ownership

The app is now named **Minecraft for MacOS**. Its earlier data-folder name,
Keychain service and bundle identifier are retained so existing installations
keep their saved worlds and sign-in without a data migration

| Item | Packaged app | Development checkout |
| --- | --- | --- |
| Root (`BEDROCK_HOME`) | `~/Library/Application Support/Bedrock for Mac` | Repository root by default |
| App components | App bundle `Contents/Resources` | `runtime/standalone/`, `sources/xodus/target/` |
| Game files | `<root>/game` | `<root>/game` or CLI `--game-dir` |
| Wine prefix and worlds | `<root>/bottles/Bedrock-Standalone` | Same relative path |
| Logs | `<root>/logs/standalone` | Same relative path |
| Runtime links and helper record | `<root>/runtime/standalone` | Same relative path |

The bundle's `BEDROCK_BUNDLE` tells the worker where to find shipped scripts and
components. The frozen worker also executes an allowlist of copied Python
scripts; players do not need a system Python or build tools. An app replacement
relinks its components at the next Play action. Game files and worlds live
outside the app, while credentials remain in Keychain.

The credential service is `Minecraft Bedrock Standalone`, item `account-v1`.
It holds the user and device token map. One process caches a single Keychain
read; direct writes avoid the old setter's extra reads. Sign-out removes the
user identity and user tokens, retaining the device identity and all game data.
Legacy token entries are left untouched rather than automatically imported.

`/tmp/xodus.sock` is a user-owned, mode-0600 Unix socket shared by the Xbox
integration. Only one helper can use it. The app checks the helper PID and
executable recorded in `runtime/standalone/helper-session.json` before reuse.
The helper also holds an account lock under
`~/Library/Application Support/Minecraft Bedrock Standalone/`. Setup, onboarding,
and standalone launch have their own lock files; the presence of a lock file
alone does not prove that a process still holds its lock.

Wine maps `G:` to the selected game and `R:` to the data root. The earlier
CrossOver prefix is `bottles/Bedrock-Mac`; it is not migrated automatically.

## Build and trust boundaries

Swift and the pinned DXMT target macOS 15, but the current local Wine/Python
bundle requires macOS 27. The packager scans native load commands and records
the highest minimum OS; a UI deployment target alone cannot establish support
Wine and DXMT are x86-64 and require Rosetta; the native launcher is arm64.

Account and license traffic uses verified HTTPS. Game bytes use a separate
client without account headers/cookies; it currently permits the two catalog
HTTP CDN hosts documented in [Account and game preparation](architecture.md#standalone-setup).
Some unencrypted package sections lack complete integrity authentication. This
is an unresolved release gate, not a claim that host allowlisting authenticates
HTTP downloads. See [SECURITY.md](../.github/SECURITY.md).

App resource checksums, a valid ad-hoc bundle signature, source checksums, and
notarization serve different purposes. None substitutes for game-package
authentication or clean-machine testing. Builds are currently ad-hoc signed;
rebuilding the helper can require new Keychain authorization.

## Where to make changes

- User journey or error copy: launcher files and [user guide](play.md).
- Account/download behavior: helper source plus source-level tests; preserve the
  one-helper lifecycle covered in `tests/test_onboarding.py`.
- Wine/Xodus fixes: tracked patches and bootstrap/build configuration, not just
  edits in ignored `sources/` or `build/` checkouts.
- New public files: explicit source-export allowlist and regenerated inventory.
- Build, packaging, or supported-version changes: [development guide](build.md)
  and dated [release evidence](status.md).

---

## Standalone graphics

These are component notes and historical test observations. The current complete
app's minimum OS and verified behavior are in [release status](status.md);
the component's deployment target does not establish support for the whole app.

`tools/build/graphics.sh` stages the upstream DXMT v0.80 release into
`runtime/standalone/dxmt/`. It checks the pinned SHA-256 before extracting only
the four x64 graphics DLLs and `winemetal.so`. No CrossOver payload is used.
The installer does not change a Wine prefix or game files.

The release is MIT licensed and targets **macOS 15.0 or newer**, despite the
source build documentation's broader Sonoma requirement. It contains an x86_64
Unix library, so Apple Silicon requires Rosetta. Upstream source compilation
requires LLVM 15 and Xcode 16's Metal tools; the verified release avoids installing
that toolchain. Its release and source provenance are recorded in `manifest.json`.

After building standalone Wine:

```sh
./tools/build/graphics.sh --wine-runtime "$PWD/runtime/standalone/wine"
./tools/build/probes.sh
```

The first command installs the five DXMT binaries into our standalone Wine's
`lib/wine/` tree, backing up displaced Wine binaries under DXMT's `wine-originals/`.
This is necessary because installed Wine 11.8 searches its own DLL directory
before `WINEDLLPATH`. Re-run this command after reinstalling Wine. It also links
our Wine's `ntdll.so` and `winemac.so` into DXMT's separate staging directory.
DXMT's upstream `@rpath` entries resolve these relative to `winemetal.so`.
The Windows DLLs retain their Wine builtin markers. The launcher can retain the
DXMT directory itself in `WINEDLLPATH` and must use:

```text
d3d11,dxgi,d3d10core,winemetal=b
```

DXMT v0.80 supports Direct3D 10/11, not Direct3D 12. The standalone launcher
disables Direct3D 12 with `d3d12,d3d12core=`. Minecraft 1.26.5203.0 successfully
falls back to Direct3D 11, reports feature level 11.1, and reaches gameplay.
The user confirmed it working on September 29, 2026. This was tested in the
separate standalone prefix; the earlier CrossOver bottle remains intact.

DXMT v0.80 expects a legacy Wine macOS window-data layout. Standalone Wine uses
`vendor/patches/standalone-wine-dxmt-abi.patch` to export an adapter table with that layout,
keeping Wine's own internal layout unchanged. Merely creating a D3D11 device
does not exercise this window bridge.

`runtime/standalone/probes/standalone-graphics-probe.exe` creates a hidden window,
requests a hardware FL11.0 device and swapchain, clears a GPU texture red, reads
it back, and presents. Success requires `RedPixel=0xFF0000FF` and successful HRESULTs
(an occluded presentation status is acceptable). It has a 45-second watchdog and
does not show a game window. This probe checks the basic GPU/window bridge;
it does not cover every shader or gameplay scenario.

`standalone-graphics-shader-probe.exe` extends coverage without a game window:
it compiles vertex and pixel shaders, samples a 4×4 texture, and checks every
pixel after GPU readback. A second shader discards alternating pixels and checks
the resulting checkerboard. Both cases passed on September 30, 2026; see
`build/dxmt/shader-probe.log`. This covers basic shader translation and discard,
not Minecraft's full material library. Starting even a hidden-window Wine probe
can activate the Wine application, so run probes while gameplay testing is idle.

The original swapchain probe optionally accepts `BEDROCK_GRAPHICS_STRESS_FRAMES`
(capped at 1,200) for a bounded presentation soak. Setting
`BEDROCK_GRAPHICS_STRESS_AUTORELEASEPOOL=1` wraps each presentation in DXMT's
autorelease pool for allocation diagnosis only. These options do not modify the
runtime or enable a game workaround. Initial evidence showed slower host-memory
growth with a pool; this is not yet an established explanation of the overnight
Minecraft hang, nor a verified production fix.

The September 30 hang had about 20.7 GB in native `MALLOC_TINY`/`MALLOC_SMALL`
regions, versus about 390 MB in IOAccelerator allocations. That points toward
host allocations; it does not establish which caller caused the hang.
DXMT v0.80's per-frame `WMTQueryDisplaySettingForLayer` reads Cocoa display
properties without an autorelease pool. A narrow experimental adapter wraps
only that scalar-returning call, preserving the other 131 Unix-call entries.
It leaves calls returning borrowed objects alone.

Build the candidate separately, then explicitly stage its recorded bytes into
a stopped test runtime:

```sh
./tools/build/pool.sh
./tools/build/pool.sh --stage-existing-runtime /absolute/path/to/test-wine
```

This does not run from the normal graphics installer. The builder pins the
original v0.80 binary hash and Unix-call layout; the stage operation validates
both artifact hashes and the adapter source hash. The original library remains
beside the adapter as `winemetal-upstream.so`. Use
`BEDROCK_DXMT_DISPLAY_QUERY_POOL=0` for control and `=1` for the candidate.
Do not set the probe's separate `BEDROCK_GRAPHICS_STRESS_AUTORELEASEPOOL` during
this comparison. Reinstalling normal DXMT restores the original entry library.

The candidate with SHA-256
`daad45337c6e9a05256d31163fcb68e5502e6ab12ea69a9da45312dc9bb9b015`
passed clear/readback, textured shader, discard shader, and 1,200 presentations.
In equal-length presentation runs, observed steady RSS growth fell from roughly
64 KB/s to 28 KB/s. These short measurements include allocator noise and do not
prove an overnight game-memory fix. Logs are `build/dxmt/shim-control*`,
`build/dxmt/shim-pooled*`, and `build/dxmt/shim-standalone-graphics-*`.
This narrow adapter was used only for diagnosis; the gameplay runtime now uses
the corrected source rebuild described below.

The source audit also found unreleased ColorSync profiles/tags during DXGI
output construction and no pool around the finish thread's Metal diagnostics.
`vendor/patches/standalone-dxmt-memory-lifetime.patch` records source fixes for those
paths and the display query. The narrow adapter does not implement these
additional fixes. A full DXMT rebuild needs LLVM 15 and Xcode's Metal toolchain;
this machine currently has Command Line Tools and no `metal` executable.

A partial rebuild is possible without those tools: `tools/build/bridge.sh`
compiles only `winemetal_unix.c` with the query/output pools and ColorSync releases.
It links to the unchanged upstream library for its exported shader compiler and
cache functions, preserving the upstream shader binaries. The C++ finish-thread
pool is excluded. Output remains under `build/dxmt-memory-unix/`; nothing is
installed into the normal runtime. The builder checks the source commit, original
binary hash, Unix-call layout, and the expected source changes after patching.
These source fixes are always enabled in the rebuilt bridge; the earlier
`BEDROCK_DXMT_DISPLAY_QUERY_POOL` switch applies only to the narrow adapter.

The opt-in qualification and staging flow is:

```sh
./tools/build/bridge.sh
./tools/build/bridge.sh --validate
# After gameplay qualification, stop the target runtime before staging:
./tools/build/bridge.sh --stage-existing-runtime "$PWD/runtime/standalone/wine"
```

`--validate` makes a disposable APFS clone of standalone Wine and a private Wine
prefix, installs the candidate only there, runs both rendering probes, and records
their exact binary hashes. It can briefly activate Wine. Set
`STANDALONE_WINE_RUNTIME` to use a different base runtime. Alternatively,
`--validate-runtime /absolute/path/to/test-wine` tests an existing isolated runtime
whose graphics pair already matches the build.

Staging verifies the original source, four input headers, patch, trace source,
patched source, and both output hashes. It requires a matching render-validation
record; rebuilding different bytes invalidates that record. It refuses mapped
target libraries, preserves the original library under `dxmt-unix-bridge-backups/`,
and atomically replaces the dependency, entry library, and manifest in order.
Any failed commit or final hash check restores the previous files. The installed
manifest is `dxmt-unix-bridge.json` at the Wine runtime root. Transaction regression
tests run without Wine using
`python3 -m unittest discover -s tests -p test_standalone_dxmt_unix.py`.

To restore the official graphics implementation, rerun
`tools/build/graphics.sh --wine-runtime <stopped runtime>`. It refuses mapped
graphics files and clears optional bridge manifests only after all five official
payloads pass hash verification. Displaced binaries remain backed up.

The optional `BEDROCK_DXMT_DISPLAY_TRACE=1` logs only elapsed time and counts of
layer queries and output descriptions. This distinguishes per-frame temporary
allocations from repeated output enumeration without logging account data.
`display-memory-probe` is a native, headless allocation diagnostic built alongside
the bridge. Run it separately against each library:

```sh
build/dxmt-memory-unix/display-memory-probe "$PWD/build/dxmt-memory-unix/winemetal-upstream.so"
build/dxmt-memory-unix/display-memory-probe "$PWD/build/dxmt-memory-unix/winemetal.so"
```

Across 2,000 calls, upstream retained about 4.6 MB versus roughly 25 KB with the
patched bridge, with identical reported display values. Each call already has an
autorelease pool in this diagnostic, isolating the owned ColorSync objects.
The original output-description leak is about 2.3 KB/call: explaining 20 GB over
nine hours would require roughly 280 calls/second. Main-menu growth observed in
Minecraft was much smaller, so the overnight hang's cause remains unproven.

An initial scripted bridge build accidentally skipped its patch due to a path
filter; it is useful only as a tracing control. The corrected builder explicitly
asserts the applied source changes. Candidate 3 records patched-source and binary
hashes in `unix-bridge-manifest.json`; the bridge hash is
`567e2afef0f00d3f93f68e17eb4b9dde24cb9e6a2d4b211f54e0e9c6fb0e8ff3`.
That exact candidate passed the hardware clear/readback/Present probe and both
texture and discard shader readbacks. Logs are
`build/dxmt-memory-unix/candidate3-standalone-graphics-*.log`.

In a five-minute Minecraft comparison, native tiny-allocation growth fell from
about 7.4 MB to 0.36 MB. The game made roughly 100 layer queries per second but
only two output-description queries at startup. Local-world loading, movement,
and saving passed with the corrected bridge. After fresh isolated validation,
the exact recorded pair was installed into the normal standalone runtime on
September 30. The normal launcher then passed a Lifeboat join, movement, and
disconnect with the new account helper and token-refresh runtime. The game held
about 2 GB of physical memory during that short online session. Fullscreen through
Video settings, fullscreen UI input, and return to the original window size passed.
These bounded tests do not prove the overnight freeze is resolved.

The subsequent September 30 gameplay session captured 654 samples over
1 hour 51 minutes using the corrected normal runtime. The user confirmed
multiplayer with an Xbox player. Physical footprint ranged from 4.18 to
5.15 GiB, macOS memory pressure stayed normal, the swapout counter did not
increase, and the launcher exited with code 0. No macOS crash was recorded.
This is stronger gameplay evidence, but still shorter than the earlier
nine-hour freeze; overnight stability remains unverified.

A growth alert and the user's report of slight lag prompted two diagnostic
captures around 3:45 p.m. Pacific. Both memory maps and thread samples completed.
Native malloc allocated about 81 MiB at capture; much of the footprint was in
Wine reserve, graphics, and owned unmapped memory. The thread samples contained
unresolved Rosetta frames and repeated Wine syscall-dispatch frames, limiting
attribution. The game log contained startup graphics warnings without a new
connection timeout or device-lost error. These observations establish neither
a memory leak nor the cause of the lag. No additional graphics fix was justified
by this evidence. See the [earlier gameplay results](status.md#earlier-gameplay-results);
raw diagnostics remain private under `logs/standalone/monitor/`.

The same probe builder produces the existing account and Store-callback probes.
It copies only the owner's `MicrosoftGame.Config` beside these probes, as required
by GDK, and leaves the original game directory unchanged. All generated output
stays under ignored `runtime/`.

On 2026-09-29, the standalone Wine 11.8 + upstream DXMT v0.80 package passed both
device creation and the hidden-window probe on this M4 Pro / macOS 15.3.1.
The swapchain, GPU readback, and presentation returned `S_OK`; the red pixel
matched `0xFF0000FF`. Evidence is in `build/dxmt/swapchain-probe-dxmt.log`.
An initial `E_FAIL` came from Wine's own D3D11 DLL shadowing DXMT, resolved by the
installation overlay above. The subsequent Minecraft test confirmed the D3D11
fallback and working gameplay. Inspection of the live game process found the
standalone Wine and DXMT Metal library loaded, with no CrossOver or D3DMetal
files mapped. A later test entered the Lifeboat online lobby with other players.
The local save was reopened, moved in, and saved successfully on September 30.
The September 30 session above subsequently confirmed Xbox multiplayer.
PS5 friend sessions, active Realm gameplay, and overnight stability remain
untested.

---

## Standalone setup

This setup obtains each user's Windows Bedrock game through their own Microsoft account. It does not use CrossOver or distribute Minecraft, Microsoft runtime binaries, credentials, or licenses.

This is the developer/reference CLI guide. Players should start with the
[user guide](play.md); for a complete build from a fresh checkout,
follow [local development](build.md). Commands here use checkout data
unless `BEDROCK_HOME` is set; the packaged app has a separate data directory.

From this directory:

```sh
./src/standalone-setup.py --check
./src/standalone-setup.py --dry-run --threading --build-helper --download-game
```

Both commands are offline. They do not read Keychain or modify the current game. `--check` returns a nonzero status when required setup files are missing.

To prepare a new installation:

```sh
./src/standalone-setup.py --threading --build-helper
./src/standalone-setup.py --download-game --game-dir "$PWD/game" --market CA
```

The source build requires Git, Rust 1.98.0, Protocol Buffers (`protoc`), and the macOS Command Line Tools. Setup downloads only the required 197 MB Gaming Services member from Microsoft's pinned GDK archive; Minecraft needs several additional gigabytes. The setup checks available space. `--jobs 4` is the default build parallelism.

An already prepared game is reused without account access. New downloads require a destination that does not exist. Close Minecraft and stop its account helper before downloading; setup refuses to replace an active `/tmp/xodus.sock` or overwrite an installation. Failed downloads discard only their own temporary directory. They do not resume game file transfers.

Sign in using the Microsoft account that owns Minecraft: Java & Bedrock for PC. `--market` accepts a two-letter country code and defaults to `CA`. Microsoft selects the currently available Windows package; game versions are therefore not pinned. A future game update may require new compatibility fixes.

One helper executable performs login, licensed download, executable preparation, and the Xbox service. Its credentials remain in one macOS Keychain item, `account-v1`, under `Minecraft Bedrock Standalone`. Each process reads that item once and caches it. Previous builds used four separate entries; this build leaves those untouched and asks for Microsoft sign-in again rather than triggering four authorization dialogs to import them. Rebuilding this ad-hoc signed executable can still cause macOS to request Keychain access again. No account tokens or content keys are written to project files.

`--check-download GAME_DIR` checks catalog selection, download metadata, package parsing, disk space, and the account's content license without installing game files. It requires a nonexistent game destination and can request Keychain access. Known failure stages use credential-free `BEDROCK_ERROR` codes; logs omit raw service responses and signed download URLs.

Account writes use Security.framework's `SecItemAdd`/`SecItemUpdate` path. The
legacy keyring setter reads the current secret before every write, which can
request authorization repeatedly even when application-level reads are cached.
The direct update removes those hidden reads without changing Keychain access
permissions. macOS still controls authorization for the initial read and updates.

The native launcher owns one account helper for the entire Play action. On a
fresh installation it uses `--download --serve-after`, keeps that process alive
while the runtime is prepared, and reuses its Xbox service when Minecraft starts.
The helper stops when the game exits, setup fails, or setup is cancelled. Sign-in waits are bounded to 15 minutes; first downloads have a two-hour limit. Cancellation drops the active download and removes its temporary staging directory. Setup retries preserve the game and worlds. Previously download and
launch each started a helper, causing a second Keychain read during onboarding.
The integration test exercises this flow with a private socket and fails if more
than one helper is started. This does not test or override macOS Keychain dialogs.

Expired or incomplete user tokens trigger sign-in again. Expired device tokens are
renewed using the existing device identity. Credential read failures preserve the
saved account. The launcher recovers only its recorded dead helper's private,
non-listening socket; unknown endpoints remain untouched. See
[stability notes](status.md#stability-fixes-and-earlier-gameplay-evidence) for Wine token refresh and friend joining.

The native app menu includes **Sign Out of Microsoft…**. The helper’s `--sign-out GAME_DIR` mode removes only user tokens and user identity from the account item, keeps the device identity, and never changes game files or worlds. It refuses while an account service is active.

The launcher may start the service with:

```sh
XODUS_LOG=off RUST_LOG=off ./sources/xodus/target/release/examples/standalone_helper --serve "$PWD/game"
```

Use the same binary for download and service. Each `--serve` start reacquires the signed-in account's real Microsoft content license for the installed package before opening the Xbox IPC service. A copied prepared executable does not replace account ownership. `--download GAME_DIR --serve-after` performs both in one process. Stop the service with Ctrl-C after exiting the game. An account lock prevents two standalone helpers from accessing the same saved session concurrently.

`--threading` retrieves the exact compressed Gaming Services ZIP member using an HTTPS byte-range request to Microsoft's [GDK April 2026 Update 4](https://github.com/microsoft/GDK/releases/tag/April-2026-Update-4-v2604.4.7897) archive. It requires HTTP 206, verifies the exact compressed length and SHA-256, checks the decompressed length, and verifies the original pinned DLL hash. Servers that ignore Range are rejected instead of downloading the full archive. A completed older `.zip.part` is validated and promoted without overwriting a racing destination. Incomplete older partial archives remain untouched while the smaller component request is used. An existing full GDK archive is still supported and verified against Microsoft's published digest. The verified DLL goes in `runtime/xgameruntime.dll.threading`; conflicting existing files are preserved and rejected.

The compressed member starts at byte `1101515484`, is `196592307` bytes long,
and has SHA-256 `f8d5f3ebe7339d9d65ebf4b4d68cb7a5281c0f944acafd613ccc68d7d908baed`.
These constants were extracted from the full archive after validating its pinned digest.

| File | SHA-256 |
| --- | --- |
| `GDK_2604.4.7897.zip` | `3da3f104fa66bb3ee1299b3dc8c0a3ecac1cb56a4cf04136b8595942272017eb` |
| `xgameruntime.dll.threading` | `aa611155057ebd01cf315ad702a4b5725aa9d5e6fad87732c956fe0a1e5fcfba` |

The helper uses Xodus commit `0670e25aeb0e0e9f800f8f2f4968ae3b681842a7` with the source patches and dependency lockfile in `vendor/patches/`. The game download uses Microsoft's package metadata and owner license, downloads into a private temporary directory, checks paths and file sizes, prepares encrypted executables using that license, and promotes the directory only after preparation succeeds.

The account/catalog/license client requires HTTPS. Game bytes use a separate client without account headers or cookies, preserving the URL supplied by the authenticated catalog. HTTP is accepted only for `assets1.xboxlive.com` and `assets2.xboxlive.com` on port 80, including redirects. Those Microsoft CDN names do not currently provide matching HTTPS certificates; rewriting their scheme causes setup to fail. TLS certificate validation remains enabled for HTTPS URLs. The package parser's existing segment checks do not provide complete verification of every unencrypted package section.

Verified locally: owner-account download and preparation on the development Mac, Microsoft sign-in through Minecraft’s welcome confirmation, helper compilation, offline installation checks, nested Microsoft DLL extraction, path traversal rejection, preservation of conflicting DLLs and symlinks, and refusal to access a second account session while the existing Xbox helper is running. A completely fresh account on a clean Mac has not yet been tested. Wine, graphics, prefix installation, and gameplay validation are handled separately from this setup script.

### Native GameInput installation

The current Microsoft GameInput MSI stalls in its service configuration custom action under the standalone Wine build. `src/standalone-gameinput.py` reads the owned game's MSI directly, verifies its pinned checksum, and extracts four exact native x64 files by checksum. It emits a registry file for the launcher to import, including both `RedistDir` views and the real demand-start `GameInputRedistService` executable. It does not execute MSI custom actions or report registry installation as complete before import.

The launcher must stop only its separate Wine prefix before extraction:

```sh
./src/standalone-gameinput.py --prefix "$PWD/bottles/Bedrock-Standalone" \
  --msi "$PWD/game/Installers/GameInputRedist.msi" \
  --wineserver "$PWD/runtime/standalone/wine/bin/wineserver"
```

It refuses busy prefixes, CrossOver bottles, symbolic-link destinations, conflicting installed files, and unknown MSI versions. Import the emitted `bottles/Bedrock-Standalone/.standalone-tools/legacy/gameinput.reg` using that prefix's Wine, then stop that prefix's server to flush its registry. Run the same command with `--check` for read-only verification of installed hashes and persisted registry entries; `--wineserver` is optional for this check. `--verify-payload` validates extraction entirely in memory.

The OLE/MSZIP parser is adapted from [BedrockOnLinux](https://github.com/Wyze3306/BedrockOnLinux) commit `7a315c836b7ae8068042bc466b0540c16ffe3a5e`; the script contains its full MIT copyright and license notice. Microsoft payload bytes are never included in the source release.

---

## Earlier CrossOver implementation

Historical development notes. Use the native launcher described in the main README for current standalone work.

### Earlier CrossOver configuration

- Mac mini M4 Pro, macOS 15.3.1, Rosetta.
- Windows game 1.26.5203.0 downloaded through the signed-in Microsoft account.
- CrossOver 26.3 trial runs Windows programs. The trial lasts 14 days.
- D3DMetal renders the game. DXMT also passed a hardware DirectX 11 device probe.
- Custom WineGDK DLL and macOS bridge compile and load; the signed-in Xbox user resolves successfully.
- The 41% loading stall and 82% crash are fixed. The game loads into a playable world.
- Mouse/keyboard input, movement, crafting, and block breaking work; the user confirmed normal gameplay on September 29, 2026.
- A non-empty world save exists on disk. Reopening that save and multiplayer have not been tested.

The combined `bedrock_helper` owns Microsoft login, executable preparation, and the Xbox account service. Its credentials stay in macOS Keychain under `Minecraft Bedrock Mac`. A process-local cache avoids repeatedly asking Keychain for the same entry. Authentication and license tokens are not printed or saved in project files.

### Earlier CrossOver launcher

Double-click **python3 minecraft.py legacy**. It starts or reuses the local account helper, waits for it to be ready, and launches the game. This launch path has reached gameplay with the existing signed-in helper; a new helper session can still require Keychain approval. Use this launcher so the required runtime overrides and game working directory are applied.

Client worlds are stored under `bottles/Bedrock-Mac/drive_c/users/crossover/AppData/Roaming/Minecraft Bedrock/`, inside the account's `games/com.mojang/minecraftWorlds` directory. They are separate from the dedicated server's worlds.

To check the installation without launching:

```sh
./tools/legacy/launch.py --check
```

### Diagnostic commands

Run the helper from this directory, leaving it open for the game:

```sh
umask 077
XODUS_LOG=off RUST_LOG=off ./sources/xodus/target/release/examples/bedrock_helper "$PWD/game" > logs/bedrock-helper.log 2>&1
```

Once `/tmp/xodus.sock` exists and the helper reports that preparation finished:

```sh
./tools/legacy/run-windows.sh "$PWD/game/runtime-auth-probe.exe"
./tools/legacy/run-windows.sh "$PWD/game/Minecraft.Windows.exe"
```

Stop the helper with Ctrl-C after closing the game. Do not run multiple account helpers at once.

`tools/legacy/build.sh runtime`, `tools/legacy/stage-runtime.py`, `tools/legacy/build.sh helper`, and `tools/legacy/build.sh probes` rebuild the local components from the prepared sources. Exit the game and helper before rebuilding. A changed helper binary may require macOS to authorize Keychain access again.

The bottle lives under `bottles/Bedrock-Mac`; a symlink in the standard CrossOver Bottles directory makes it visible in CrossOver. Graphics is set to D3DMetal. The server files and worlds in the parent Bedrock directory are separate.

### Startup fixes

- Native overrides for WineGDK's `twinapi.appcore`, `windows.ui.core.textinput`, `windows.web`, and `wintypes`, with the activation mappings in `src/winrt.reg`. The `wintypes` capability query avoids the fatal `E_NOTIMPL` at 82%.
- `minecraft-store-callback.patch` completes the unsupported game-license query with `E_NOTIMPL` on the caller's task queue. The previous immediate stub stranded Minecraft at 41%. This reports a missing Store capability; it does not fabricate ownership or alter the game's licensing checks. The executable is prepared using the account's real Microsoft license.
- Microsoft's bundled GameInput redistributable and the missing directory registration in `tools/legacy/gameinput.reg`.

After staging the runtime, register the classes and install the bundled input component:

```sh
./tools/legacy/run-windows.sh reg import "$PWD/src/winrt.reg"
./tools/legacy/run-windows.sh msiexec /i 'Y:\git\minecraft\bedrock\macos-client\game\Installers\GameInputRedist.msi' /qn /norestart
./tools/legacy/run-windows.sh reg import "$PWD/tools/legacy/gameinput.reg"
```

The MSI path above is for this Mac's existing Wine drive mapping. For another checkout, use that bottle's Windows path to the same bundled installer. Restart Minecraft after installation.

`tools/probes/store-callback-probe.c` verifies that both thread-pool and manually dispatched completion queues receive exactly one callback, report the expected error, and leave the license output untouched. Both cases pass, including with the staged `wintypes` module.

### Sources and local changes

- [Xodus](https://github.com/xodus-gaming/xodus), commit `0670e25aeb0e0e9f800f8f2f4968ae3b681842a7`.
- [WineGDK](https://github.com/Sightem/WineGDK), commit `b5d23b074cfd5e28e79acceaaefaf41a26ce6272`.
- [macOS runtime reference](https://github.com/wtfsayo/cricket26-crossover): licensed Store integration and macOS IPC patches.
- CrossOver 26.3 official trial archive SHA-256: `8688e0848c4e5f79f1cc351cb52d32447da00c6c00cfd3b4bb2d164d44589a26`.
- Microsoft GDK `2604.4.7897` Gaming Services runtime provides the threading DLL. SHA-256: `aa611155057ebd01cf315ad702a4b5725aa9d5e6fad87732c956fe0a1e5fcfba`.

Apply the reference patches in `vendor/patches/` to their pinned source trees, then `minecraft-store-callback.patch` to WineGDK and `keychain-cache.patch` and `unified-helper.patch` to Xodus; use `vendor/patches/Cargo.lock`. The source clones, game, binaries, bottle, and private logs are ignored. `runtime/staged-hashes.json` records staged runtime hashes.

The credential-cache tests cover concurrent reads, persistent updates, failed writes, and deletion. Logs in `logs/` record the actual runtime and graphics checks. Store/account success alone does not establish multiplayer support.
