# Release status

This is a source preview with an ad-hoc signed local DMG. Developer ID signing,
notarization and clean-Mac installation have not been verified. Apple Developer
membership is not required to publish source or build a local preview

Status snapshot: October 20, 2026. The earlier native launcher source was merged in
[PR #1](https://github.com/1JRobertson/bedrock-mac/pull/1), merge commit `0205d2a`.
That merge did not publish a binary. Use [Testing](test.md) for the manual
test matrix and artifact checks; use [Source releases](build.md#preparing-a-source-release) for source
inventories and exports

## Flight and destination corrections in 0.13

The destination picker now uses Minecraft block textures, readable list rows,
search, no-results feedback and arrow focus. Background controls are disabled
while it is open, including Play's Return shortcut. Camera placement checks
solid volumes and nearby sightlines; canopies now block scenery movement
Flying residents no longer inherit walking waits. End crystal shells use the
installed game's bob/rotation formulas while their bases remain stationary
Idle rendering targets 30 fps and spectator flight targets 60 fps

All 93 Python tests, native synthetic checks and installed-art checks for 70
species, 42 areas and three passages pass. Render samples fit the idle budget;
wall-time tails exceed the spectator target and construction costs increased
The measured preflight reduction does not establish an end-to-end startup fix
See [testing and its limits](test.md#flight-destinations-and-repeat-launch-checks-in-013)

The final 0.13.0/build 17 candidate passes deep/strict ad-hoc signature checks
All helper/runtime bytes and 21 symlinks match the previous candidate. Of 1,051
baseline resource entries, 1,050 are unchanged; only the startup script changes,
with two source-provenance files added for its current paths
REA/Hopper confirms the packaged free-position search calls the solid-volume
and swept-clearance checks. The final local DMG requires macOS 27, has
128,179,124 bytes and SHA-256

```text
af781f0ab44b7fe42280ac670c6aef57edd4121ff6f5d583d3f3957ea18060a9
```

An earlier 0.13 candidate was exercised live and launched the real game during
the keyboard check. Its resource directory remains intact for that session
The final keyboard fix is compiled and packaged, with its live retest outstanding
The game remains unavailable to Computer Use, so gameplay recording/comparison,
full engine behaviour and faster-than-Windows claims remain unverified
Worlds and authenticated helper/runtime bytes are preserved
No binary release, merge or notarisation was performed

## Exploration and placement corrections in 0.12

The mineshaft and stronghold are persistent area-picker destinations with moving
residents, open side shafts/libraries and a reachable portal room. Temple and
monument shells retain walls while opening their interiors. End City vegetation
stays clear of the tower, ship and camera approach; idle aiming keeps a level horizon

Saved banner colours, patterns and mounting replace the universal captain banner
Brewing stands show saved bottle slots; doors, trapdoors and ladders follow their
saved states. Original behaviour hitboxes replace visual model extents when
planning resident routes. The corner spyglass matches the shortcut hint

All 92 Python tests, 70-species/42-area native checks, three journeys and 125
source checks pass. Paired rendering stays inside the 50 ms scenery budget
See [the method and limitations](test.md#explorable-structures-and-saved-fixture-states-in-012)

The full candidate and isolated preview verify against source machine code
All 1,051 runtime resource hashes and 21 symlinks are preserved. The local
0.12.0/build 15 DMG requires macOS 27 and verifies at 128,286,963 bytes
SHA-256:

```text
eae5882e1550ceb8a67e694bd99b3bb77c2cdf4ded034569a4f606e42f16394f
```

The 0.12 preview's live controls, VoiceOver and gameplay comparison remain
unverified because the available computer controls did not expose those targets
This remains authored launcher scenery, with no full Minecraft engine parity
Installed apps, worlds and authenticated helper/runtime bytes were preserved
No binary release, merge, Developer ID signing or notarisation was performed

## World and menu corrections in 0.11

The separate 0.11 candidate fixes Enderman/Blaze alpha handling, copper golem
eyes, crop/fixture geometry, village foundations and closed terrain boundaries
Native collision queries guard resident, idle-camera and flight paths. Committed
scene actions keep residents moving during idle hover; the stronghold descends
over forty blocks and portal-colour handoffs join destination arrivals
Settings now contains master volume and matches the title screen; Help is
local, long biome names scroll and the subtitle has an extruded face

All 92 Python tests, native fixtures, 70-species/40-area integration and 125
source checks pass. The paired rendering sample remains within the existing
50 ms scenery budget, with highest GPU p95 11.26 ms and movement-input p95
4.86 ms. Collision preparation adds background construction work
[The method, paired results and limits](test.md#world-geometry-and-menu-fidelity-in-011)
record this as launcher validation, not a game-performance improvement

The full app, isolated preview and 127,982,563-byte LZFSE DMG verify locally
All 1,051 baseline resource hashes and 21 symlinks remain unchanged; minimum
packaged macOS stays 27. The DMG SHA-256 is:

```text
2802e655ce318e1e079489da51f7128cbb7ba8b5b2ae26c64db4c5c0f961261f
```

Computer Use denied preview access, so live-window footer behaviour, pointer
capture, VoiceOver and listening checks remain unverified. No alternative
screen-capture or UI-control route bypassed that denial. Every-block rendering,
complete Minecraft AI, clean-Mac installation and notarisation remain outside
the verified result. No installed app, account or world was replaced, and no
binary release was published

## Material and interaction fidelity in 0.10.1

Water now uses the installed biome palette, cached alpha-preserving RGB tinting
and the original alpha once. Lava keeps its original colours without doubled
emission. Variant-specific geometry takes precedence over the default body
Current warm/cold animals use matching installed models/skins

The splash overlaps the original title. Pixel actions and installed utility
icons share the block controls’ styling. The lower-left **@Keys-i** credit links
to **keysi.dev**, with the actual launcher version at lower right. The scenery
Play/pause button and extra hotbar backing are removed; motion preferences stay
in Settings/View. The advancement-style hint keeps its 60/70-second timing

Idle scenery follows a continuous twelve-second hover. Overworld scenes have a
twenty-minute daylight rig with original sun/moon art, batched stars, dusk colours
and once-per-second lighting/fog updates. Nether and End retain realm lighting
Mouse-look captures relative movement and releases the cursor on focus loss,
Escape or teardown. WASD, Space/Shift, Control sprint and scroll speed remain
Native synthetic and installed-art checks and all 92 Python tests pass locally

Residents gain bounded terrain/water-aware strolls, diagonal gait timing,
unsynchronised idling, sheep grazing and hopping. Eligible base-pack classic
pigs, cows, chickens and wolves have a launcher-only 10% daylight / 15% night
selection chance. These additions do not reproduce every game block/state,
combat, breeding, village jobs or the complete Minecraft simulation
[Testing and remaining manual checks](test.md#material-hover-and-input-fidelity-in-0101)
keep that limitation explicit

The separate full 0.10.1 candidate and isolated preview verify against the final
source machine code. All 1,051 baseline resources and 21 runtime symlinks remain
unchanged, including the account helper, worker and approved poster
The corrected small-island camera passes both smooth and rounded terrain checks
Eight sampled route/flight views have a highest GPU p95 of 10.60 ms and wall p95
of 14.56 ms, inside the existing 50 ms scenery budget. This is not game FPS
All 125 reviewed source files pass boundary/checksum checks

The local LZFSE DMG verifies, retains minimum macOS 27, and is 125,937,610 bytes
SHA-256:

```text
39dcc7920cbc9e80087f07b9cca92755f21bd45d3bf1c7c81374de56c4f1a382
```

It remains an ad-hoc signed preview. Full-window mouse capture/release, developer
link activation, VoiceOver, long-session memory and a complete real-time day/night
cycle remain manual checks. No installed app, game, world or account was replaced

## Spectator title screen in 0.10

The native launcher now uses the owner’s original Minecraft title artwork and
splash pool, a Minecraft Ten Mac Edition subtitle and a connected item hotbar
The permanent keyboard footer is replaced by a 60-second achievement-style hint
that returns after 70 uninterrupted seconds of launcher-window focus
The top-left control shows only the biome; Look around stays in the lower corner

Spectator view adds WASD/Space/Shift flight, arrow/drag aiming, scroll speed and
bracket/boundary travel between authored habitats. It keeps one current graph,
cancels replaced loads and clears held input on focus loss. Area changes are
scene swaps, not continuous game world generation
Original installed menu/game music uses native AVAudioPlayer, with a visible
mute control, Settings volume and focus/visibility/gameplay pause gates
No game artwork, font or audio is added to source or distribution

The 92 Python tests, native fixtures and installed-art integration pass
Source-rendered layouts include flight, narrow, hidden-hint, error and missing-art
states. Four elevated views stay within the existing 50 ms scenery budget
[The method and results](test.md#spectator-flight-title-artwork-and-music-in-010)
record actual GPU/wall timings and distinguish preparation from listening tests
Full-window input, VoiceOver, audible transitions and long-session memory remain
unverified because the disposable preview is not accessible to Computer Use

The separate full 0.10.0 candidate passes outer/deep signature verification
Its native machine code matches the source build. All 1,051 resource hashes and
21 runtime symlinks from 0.9.1 remain unchanged, including the helper, worker,
runtime and poster. No installed app, world or account data was replaced
The LZFSE local DMG verifies; minimum macOS remains 27. It is
129,094,745 bytes with SHA-256:

```text
dd25705a63670edb56026d93b1d04b1820ee9cee97c97517db14a7f7b3290c27
```

All 125 explicitly reviewed source files pass the boundary and checksum checks
The isolated preview uses a simulated worker; it is not a live game test
No binary release is published

## Typography refinement in 0.9.1

The main title retains Monocraft; actions and section titles use rounded system
type, while supporting copy uses plain system type. Text over scenery has a soft,
low-opacity one-point shadow. Physical button/panel shadows are attached to their
background surfaces, preventing duplicate shadows behind the labels

The native build and 92 Python tests pass. Source-generated first-run, ready,
busy, error, long-detail and playing layouts were checked again at narrow,
normal and wide sizes. Full-window keyboard and VoiceOver workflows remain
unverified. The scenery renderer is unchanged from the measurements below

The separate 0.9.1 app and DMG verify, preserving all 1,051 resource hashes and
runtime symlinks from 0.9. Minimum macOS remains 27; the local DMG is
128,084,241 bytes with SHA-256:

```text
0e513a1f26946520cc7a54bf4cf4453fe567c8ff2e67ad2223398b5e8457d3cd
```

## Gameplay-reference scenery and title screen in 0.9

Version 0.9 follows actual Minecraft gameplay references for the village,
fortress, stronghold portal chamber and End City. Village clearings follow
individual building foundations and connecting paths; nearby foliage, fallen
logs, roots, fungi, coral fans and hanging cave growth fill the camera foreground
Original cutout leaves, cloud art, darkened End sky and patterned fish replace
several simplified surfaces. Sift terrain and its rift remain labelled interpretations

Play is now central on the title screen, above a compact item hotbar
Installed stone art supplies button faces. The larger centred title and smaller
control area leave more of the live world visible. Look around also uses ⌘L
The mine/Nether and stronghold/End journeys remain; the fortress has a roofed
junction and connected side rooms, and the stronghold has recessed barred openings

The 92 Python tests, native fixtures and installed-art checks pass locally
All 40 area renders, 24 passage views and paused comparisons pass, alongside
source-generated narrow/normal/wide UI states. The 49-view probe's highest GPU
p95 is 12.00 ms and wall p95 is 14.71 ms against a 50 ms budget
[Method, baseline and limits](test.md#gameplay-reference-composition-in-09)
distinguish these scenery measurements from game or Windows performance

The separate 0.9.0 candidate retains all 1,051 resources from 0.8 byte-for-byte,
including the runtime, worker, account helper, font and approved poster
Only the launcher executable, app version metadata and outer signature change
The installed app, accounts and saved worlds remain untouched
The outer signature and LZFSE disk image verify; minimum macOS remains 27
The DMG is 128,076,318 bytes with SHA-256:

```text
15f0b548533081d79ee1e185783955c9076232ec6d4840ff22581f6bf4fa91dd
```

The isolated preview uses a simulated worker; its scenery reads installed art
The 138-second local tour records the authored scenery and portal journeys
Full-window interaction, VoiceOver, long-session memory and gameplay performance
remain unverified. Developer ID signing, notarisation and clean-Mac installation
remain release gates; no binary release is published

## Player-height worlds and Minecraft controls in 0.8

Version 0.8 replaces the elevated diorama framing with low routes through wider,
chunked terrain. River bends, frozen water, deeper sea floors and shaped cave
ceilings put residents into their own habitats. A full Trial Chamber surrounds
the camera. Mansion entrances face the approach and saved window panes connect
to their neighbours. Original fluid and portal atlas frames supply surface motion

The native interface uses pixel titles, stone buttons, a four-slot item hotbar,
a searchable biome picker and an experience-style setup meter. Look around stops
the camera route and lets the user drag the world; Done or Escape restores it
Realm slots also use keys 1–4. Existing macOS menus and the setup/account protocol
remain in place. Long details scroll inside the setup panel
The mine and stronghold share the terrain builder for their forest approaches
The Sift remains an artistic interpretation using existing Minecraft blocks and mobs

Local validation passed on October 19, 2026: all 92 Python tests, native fixtures,
installed-art checks, all 40 area renders, 24 passage views and 40 paused comparisons
Source-generated SwiftUI layouts cover first-run, ready, progress, errors and
playing at narrow, normal and wide sizes. These do not verify window interaction
The 49-view Metal probe's highest GPU p95 is 9.57 ms and highest wall p95 is
11.86 ms against the unchanged 50 ms frame budget. See [the method and limits](test.md#player-height-worlds-and-launcher-08-measurements)

The separate full 0.8.0 candidate preserves every one of the 1,048 resources
inventoried in 0.7, including runtime, worker, account helper and poster bytes
It adds the unmodified Monocraft font, its full OFL licence and current vendor
notices, producing a 1,051-file resource inventory. Launcher machine code matches
the source build; the outer ad-hoc signature and LZFSE disk image verify
No nested runtime/helper binary was rebuilt or re-signed
The DMG is 128,049,140 bytes and retains the runtime's macOS 27 minimum

```text
e308367cd42e022148b118885cdbf529a0945b9cbefe19533dda578b7647bc60
```

The isolated UI preview uses a simulated worker and reads only installed game art
The 138-second local video shows the scenery and passages, rather than gameplay
Full-window interaction, keyboard, VoiceOver, live-game performance and long-session
memory remain unverified. Computer Use denied the earlier preview session; no
alternate desktop automation or desktop capture was used
The installed app, worlds and account data remain untouched. No binary release
is published; Developer ID signing, notarisation and clean-Mac installation
remain release gates

## Expanded habitats and journeys in 0.7

Version 0.7 replaces the three-biome strips with 37 independent habitats and
expands the resident catalogue from 46 to 62 original Minecraft mob types
Added visits include the savanna outpost, swamp hut, woodland mansion, warm-ocean
reef, dripstone caves and Trial Chamber. Villages gain farms and pens, the bastion
and fortress become larger complexes, and the End City gains towers and bridges
Canopies, clouds, vegetation, flowing surfaces, waterfalls and ambient particles
supply movement alongside resident groups

The 22-second mine descent passes original mobs, rails, ore, supports, side shafts,
a cart and cobwebs before crossing an enclosed obsidian portal into a Nether vista
The 20-second stronghold route descends stairs, passes libraries and Silverfish,
then approaches a raised 12-frame End portal. The 16-second Sift approach remains
explicitly artistic, using installed Minecraft blocks and existing mob species
These scenes do not add dimensions or content to Minecraft

Repeated structure pieces now share decoded meshes within a scene, and face
culling classifies each palette entry once. In the sequential graph-build probe,
the mansion changed from 236.13 to 42.87 ms and the bastion from 1,023.81 to
101.03 ms, with unchanged geometry counts. Final graph construction ranged from
5.47 to 101.03 ms on the existing background queue. The previous graph stays
visible during loading; native crossfades respect the existing motion gates

Local validation on October 19, 2026 passed: all 91 Python tests, native fixtures,
installed-art integration for 62 types and 37 habitats, 24 passage renders and
37 paused comparisons within one 8-bit channel step. The 46-view Metal probe's
highest GPU p95 was 4.77 ms and highest wall p95 was 5.94 ms against 50 ms
All graphs remained below the existing 1,200-node / 150,000-triangle budget
See [the method and limits](test.md#expanded-habitat-07-measurements)
These are offscreen scenery results, not live-game FPS or application input latency

The separate full 0.7.0 candidate preserves all 1,048 resource hashes from 0.6,
including runtime, worker, account helper, poster and licences. Only the native
launcher and app metadata/signature are updated. Launcher machine code matches
the source build and the ad-hoc signature and LZFSE disk image verify
The DMG is 127,107,801 bytes and retains the runtime's macOS 27 minimum

```text
50e54089d50257e8290786669e9cc03c51ac24d6a7ec16c0b5834f116fb8545b
```

The 132-second local video tours all 37 habitats and shows all three journeys
The separate UI preview uses a simulated worker and only reads installed game art
Full-window interaction, keyboard, VoiceOver, live-game and long-session memory
checks remain unverified. Computer Use denied the earlier preview session; no
alternate desktop automation or capture route was used
The installed app, worlds and account data remain untouched; no binary release
has been published and Developer ID signing/notarization remain release gates

## Original Minecraft art in 0.6

Version 0.6 replaces the rejected procedural creatures with original models and
textures read from the owner's installed Minecraft. Original templates supply
villages, igloos, ruined portals, fossils, the Ancient City, bastions, shipwrecks
and End City pieces. No Minecraft assets are added to source or the DMG

The 31 area views and three portal journeys remain selectable. The catalogue
contains 46 resident types plus the Happy Ghast and dragon. The mine camera stays
below its support beams, Nether frames are 4 × 5 blocks, and the stronghold uses
a 12-frame End portal. Shulkers stay still and the dragon stays at the central island
Sift remains an artistic interpretation using existing Minecraft art

Scene construction now runs on a serial asset queue, with queued cancellation,
obsolete-result rejection and main-thread presentation. First-run and unsupported
art fall back to the approved poster. Shared materials and metadata remain cached;
archive buffers and the old scene graph are released after construction/replacement

Local checks passed on October 19, 2026: 91 Python tests, the native CI fixtures,
installed-art integration, 31 area renders, fifteen passage viewpoints and eleven
identical paused-frame comparisons. The native fixtures cover malformed archives,
gzip/NBT, numeric pack precedence, empty archive stubs, UV direction, plane faces,
bind transforms, parent cycles, cancellation and main-thread completion
The 121-file source boundary, source hashes and diff checks also pass

The forty-view M3 Pro probe's highest GPU p95 is 11.45 ms and highest wall p95 is
13.45 ms against the 50 ms frame budget. Cold graph construction reached 646.27 ms
on the asset queue; enqueueing returned in 0.03 ms in the native check
These are offscreen/API results, not application input latency or game benchmarks
See [Testing](test.md#original-asset-06-measurements) for the method and per-realm results

The separate full 0.6.0 candidate contains 1,048 inventoried resources. The 1,046 existing
resources apart from the notice match exactly, including the runtime, worker,
helper and licences. The notice is updated and the approved poster is added. Launcher machine code matches the
source build, and its ad-hoc bundle signature and LZFSE disk image verify
The image is 126,714,712 bytes and retains the runtime's macOS 27 minimum

```text
1ba47ac1fb5b8f10410ad44a0d752e1fd81381c65c1a385c08cb4002f10bd3d6
```

The 104-second local video is an offscreen scenery tour. The isolated UI preview
uses a simulated worker and reads only public art from the installed game
Full-window, keyboard, VoiceOver, long-session memory and live-game checks remain
unverified. The installed app and public binary release have not been replaced

## Earlier 0.5 procedural preview

The 0.5 artwork was rejected for visual fidelity and is superseded by 0.6
The measurements below describe that earlier candidate

Version 0.5 adds 31 selectable habitat and landmark areas, with 42 species in
the resident catalogue alongside the original Happy Ghast and dragon rigs
Only three neighbouring areas are built at once. The roster includes snowy
terrain, desert and jungle temples, mangroves, mushroom fields, Pale Garden at
dusk, lush caves, Deep Dark, all five Nether biomes and the End City and ship

Nether entry follows a 14-second descent from a grassy mine entrance along rails
through an obsidian portal. End entry returns to an Overworld stronghold and
descends through its horizontal portal. Sift has an artistic rift crossing
The area menu and native View menu reach every stop; Skip journey cancels a
crossing. Reduced Motion and Low Power Mode go directly to the destination
Pause, inactivity, occlusion and gameplay stop both the renderer and tour clock

The native checks cover all eleven pages, the full resident catalogue, aquatic
pool placement, Creaking visibility at dusk, bounded selection, passage timing,
rapid replacement and skip behaviour. The 91 Python tests pass locally
All 31 area renders, fifteen passage viewpoints and eleven paused-frame comparisons
pass. The forty-view GPU probe stays within the 50 ms budget for 20 fps, with a
maximum 11.67 ms GPU p95; methods and limits are in [Testing](test.md#native-app-and-helper)
The README poster, game runtime, worker, account helper and installed app are unchanged

The separate 0.5.0 full candidate preserves 1,046 resource hashes from 0.4,
including every runtime, worker, helper and licence file. Only the scenery
notice changes among its 1,047 inventoried resources. Its launcher machine code
matches the native source build; the ad-hoc signature and LZFSE DMG verify
The runtime still requires macOS 27. No installed app or public release was replaced

The isolated interface preview opened as a separate process. Its sign-in,
download and play worker is simulated and does not use account or world data
Full-window, keyboard and VoiceOver workflows remain unverified because
Computer Use access to the earlier preview was denied

The local DMG is 127,446,320 bytes. Its SHA-256 is

```text
7b726a9d791e5980f6fd9ff0ad7d942d6fcdc64ff3efcf7f72a3b9b60ac36b96
```


## Earlier 0.4 live realm preview

Version 0.4 replaces static panoramas with four native 3D landscapes and twelve
area views. Each realm contains 9–13 residents, shared terrain geometry, flowing
surfaces or ambient particles, and camera journeys between its areas

Biomes advance every 18 seconds and realms every 54 seconds. Clouds, plants,
waterfalls, lava and mobs move within the scene. The same motion gate stops
rendering and automatic changes when paused, inactive, occluded, in Low Power
Mode, with Reduced Motion, or while Minecraft runs

The source and isolated preview compile; 91 Python tests and the native graph,
texture, motion, camera-boundary and rapid-change checks pass locally. The twelve
area GPU probe and its limits are recorded in [Testing](test.md#native-app-and-helper)
The README poster is unchanged; earlier artwork is no longer bundled or loaded

The local 0.4.0 full app retains 1,046 matching resource hashes, including every
runtime, worker, helper and licence file. The third-party note was extended and
four unused JPEGs removed, leaving 1,047 inventoried resources. Launcher machine
code matches the native build; its ad-hoc signature and LZFSE DMG verify
The image is 127,585,943 bytes, with no game/account/world payload, and
retains the runtime's macOS 27 minimum. No installed app was replaced and no
public binary release was created

The isolated 0.4 Preview opens separately. A 32-second offscreen scenery video
shows all twelve views at 6.75× speed; it is not a recording of the application
window or gameplay. Full-window and VoiceOver checks remain unverified

Local 0.4-preview DMG SHA-256

```text
144189ccafc314a0fe582515c6f1a439f1f0584a148240cb8a0b4d859d7af42f
```

## Earlier 0.3 mob preview

The 0.3 interface used four local world panoramas, slow camera motion, ambient
particles, native 3D mobs, manual scene selection and automatic scene fades. A compact launch
panel replaces the earlier poster card; setup progress assembles isometric
blocks and shows sign-in, download, preparation and play as separate steps

The mob revision follows official visual references: pixel faces, a blue harness
and goggles, varied tentacle lengths, and a dragon with horns, articulated neck
and tail, four legs and hinged membranes. The generic rider and invented Sift mob
were removed. Authored textures are generated locally; no official game assets
were added to the source or bundle. See the [measured render cost](test.md#native-app-and-helper)

Overworld, Nether and End scenery are joined by an artistic Sift preview
[Mojang's announcement](https://www.minecraft.net/en-us/article/mclive_sept2026_recap)
places its Java/Bedrock arrival in 2027. This launcher does not add it to the game
or provide every historical game version. The illustrated adventure draws from
classic realms and newer mobs without claiming complete update compatibility

The Mac menus include Settings, Edit, View, Window, Help and a manual update
check; About, Services and protected Quit use native app-menu behaviour

The native build and progress/motion policy checks pass locally. The 91-test
Python suite includes the isolated preview bundle and cancellation path
`minecraft.py build preview` produces the real interface with a simulated worker
and no access to accounts, downloads or worlds. Keyboard, VoiceOver, motion,
foreground CPU/GPU and long-session memory checks remain manual acceptance work
Offscreen Metal rendering confirms that the authored actors move and pause;
the complete window and menu interactions have not been visually verified

The revised local 0.3.0 candidate preserves all 1,051 resource hashes from the
adventure build, including its runtime, worker and account helper. Only launcher
machine code changed. Its ad-hoc signature and LZFSE DMG verify. The image is
129,640,227 bytes, contains no account/game/world payload, and retains the
full runtime's macOS 27 minimum. The installed app was not replaced and no public
binary release was created

Local mobs-preview DMG SHA-256:

```text
8bcc931dbcff5c09451b00918339da9b8d5d0e61053dddbca6eb6a8b004ae5ca
```

## Earlier October 19 interface update

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
