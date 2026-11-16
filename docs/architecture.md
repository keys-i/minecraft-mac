# Architecture

Minecraft Launcher is an ARM64 macOS interface for the owner's Windows Minecraft Bedrock installation
SwiftUI and SceneKit own the launcher; one Rust worker owns setup, the account-service lifetime and the Wine/DXMT game session
The launcher and game still have distinct native windows, with a rendered-frame handoff between them
Rosetta remains necessary for the installed x64 game and compatibility stack
Build 41 adds an optional Linux GPU host and browser client without changing that native Mac path

## Components

| Component | Responsibility | Source |
| --- | --- | --- |
| Native interface | Menus, settings, loading, input and worker observation | `src/launcher/BedrockLauncher.swift` |
| Worker | Structured launcher/scenery events and command dispatch | `src/worker/main.rs` |
| Session | Prefix preparation, verified runtime and owned account/game processes | `src/worker/session.rs` |
| Acquisition | Pinned Microsoft threading and GameInput components | `src/worker/threading.rs`, `src/worker/input.rs` |
| Account helper | Keychain, Microsoft ownership, download and Xbox IPC | `src/standalone-helper.rs` and preserved Xodus patches |
| World generator | Isolated, pinned Bedrock server and seed cache | `src/worker/world.rs` |
| Chunk snapshots | LevelDB decoding, shared blocks, collision and meshing | `src/launcher/Chunks.swift` |
| Scenery | Chunk streaming, camera movement, environment and transitions | `src/launcher/Expedition.swift` |
| Journeys | Persistent scenery-only cave/stronghold edits and physical routes | `src/launcher/Trail.swift` |
| Residents | Original models and bounded local movement/attention | `src/launcher/Crowd.swift`, `src/launcher/Mobs.swift` |
| Developer tools | Build, source, graphics, monitoring, setup and legacy commands | Rust modules in `src/worker/` |
| Stream control | Authenticated browser input, fixed SPSC queue and hardware publisher command | `stream/` |
| Browser client | WHEP playback, pointer capture, input and live stream statistics | `web/` |
| Cloud host | OCI network policy, TLS proxy, MediaMTX and systemd ownership | `cloud/` |

The public entry point is `./minecraft COMMAND`; use `COMMAND --help` for options
All project-owned Python files and embedded Python scripts have been replaced
Upstream source projects retain their own build systems and languages

## Data and process ownership

Installed player data lives in `~/Library/Application Support/Bedrock for Mac/`
Source development uses the checkout; the historical CrossOver bottle is separate

| Path | Owner and lifetime |
| --- | --- |
| `game/` | Owned Microsoft installation and player data; preserve during app updates |
| `bottles/Bedrock-Standalone/` | Prepared standalone Wine prefix; never repoint a conflicting drive |
| `bottles/Bedrock-Mac/` | Historical CrossOver prefix; never use for standalone preparation |
| `runtime/standalone/` | Runtime links, helper ownership records and setup locks |
| `logs/standalone/` | Private local status and diagnostic files |
| `scenery/generator/` | Isolated server payload, prefix, sandbox and generator lock |
| `scenery/worlds/<hash>/` | Generated scenery DB, seed/version manifest and portal-route records |
| Keychain | Stable authorised account helper; never reset access to fix a test |

Play retains one account guard across download, preparation and launch
A guard stops only the child it created; it can reuse an identified existing service without claiming ownership
Socket recovery requires a matching recorded dead helper, a private socket owned by the current user, refusal of connection and unchanged inode identity
Cancellation and timeouts reap owned process groups; they do not use system-wide Wine termination
Prefix preparation first acquires an idle, separate prefix, validates components and preserves conflicting files
Only structured, bounded events reach the interface; arbitrary helper output remains in private logs

The worker inherits the launcher handoff nonce and frame while discarding inherited Wine, CrossOver and dynamic-loader overrides
Microsoft ownership checks, pinned Cargo dependencies and exact payload digests remain mandatory
Bundle assembly preserves the authorised account-helper bytes, signs nested executables, records final signed payload digests and verifies the complete candidate

## Cloud stream boundary

Build 41 keeps the build 40 SwiftUI, SceneKit and Metal application as the native Mac mode
The optional cloud mode runs the x64 Windows Bedrock game on an x86-64 Linux GPU host through WineGDK, DXVK and Gamescope's Vulkan DRM backend
The Rust control binary is source-portable across x86-64, ARM64 and RISC-V Linux, but that does not make the x64 game native on ARM64 or RISC-V

The host capture path is `Vulkan scanout → KMS/DRM PRIME → direct DMA-BUF hardware map → NVENC or VAAPI → WHIP/WebRTC`
`hwmap=mode=read+direct` is mandatory and there is no CPU encoder fallback
Zero-copy describes the fixed input ring and direct GPU mapping boundary; packetisation, encryption, browser decode and network transport still copy data where their APIs require it
The target is 1920 × 1080 at 60 FPS and at most 80 ms regional input-to-photon latency, which remains a deployment target rather than a measured guarantee

Browser input uses one authenticated WebSocket controller, a strict 24-byte binary protocol, a preallocated 1,024-event SPSC ring and Linux uinput
The ring stores events in place, performs no hot-path allocation and releases held keys and buttons when a controller disconnects
The browser receives media through WHEP, removes its bearer ticket from history, keeps session deletion same-origin and reports decoded FPS, drops, decode time and input RTT
TCP input can head-of-line block under packet loss, so the regional latency target requires live network measurement

Caddy is the only public HTTP service and terminates TLS on TCP 443
MediaMTX v1.15.4 and the Rust host remain on loopback, while WebRTC media uses UDP 8189
Terraform exposes only HTTPS, WebRTC UDP and SSH restricted to the configured administration CIDR
The bearer token is generated on the host, stored mode 0600 and returned only by `sudo minecraft-stream-link`
The dedicated media unit alone receives bounded `CAP_SYS_ADMIN` because FFmpeg `kmsgrab` must read DRM planes while Gamescope owns the display; its device list and other systemd protections remain restricted

Terraform never downloads the game, transfers an account or embeds Microsoft credentials
The operator must prepare `/srv/minecraft-owned/launch` as the dedicated `minecraft` user; that foreground program owns the verified game, x86-64 WineGDK/DXVK runtime and Xbox account-service lifetime
The game and publisher services stay enabled but stopped until that per-user boundary is complete
No Oracle deployment, Linux account sign-in or live GPU DMA-BUF import has been completed in this source environment

## Shared world data

The three Minecraft dimensions use chunks generated by the pinned official Bedrock server, version 1.26.52.3
The isolated generator uses a separate prefix, two server threads, low CPU priority and loopback-only networking
It never opens the player's worlds or account helper
One serial generation queue prevents concurrent server writes and LevelDB reads
A seed/version hash chooses the private scenery database; its manifest records completed dimension/chunk coordinates and located destinations
Private behaviour-pack functions check at most 16 chunks together, with a scoreboard result and an ordered console barrier before the next batch
The launcher submits at most 128 nearest chunks per generator handoff from a radial working set, then loads that saved wave before requesting more
One official-server lifecycle rotates bounded windows with at most ten ticking areas; readiness follows saved data, final cleanup and a normal server exit
Brief generator-lock contention waits for owned cleanup, with a 30-second deadline and cancellation

Immutable `WorldData` snapshots feed rendering, movement, resident clearance and the minimap
The native decoder validates little-endian NBT palettes, packed storage, dimension heights and biome sections
Meshes omit buried faces and share original materials from the installed game
Palette solidity is resolved once; opaque and translucent partitions retain only their own vertex buffers
A serial asset queue owns asset caches and constructs meshes; the main thread installs completed node graphs
The previous scene or installed panorama stays visible while the nearest 9 meshes and their 25-chunk lighting and collision halo prepare; Look around then becomes available while the selected horizon keeps streaming
The normal fog horizon expands only through complete radial mesh shells, so unfinished terrain remains covered while flight waits for rendered chunks
Stale work is cancelled or rejected by its request/revision token
Near meshes retry one transient construction failure without stopping independent chunks; a repeated entry-mesh failure remains visible instead of silently opening incomplete terrain
Crossing a chunk retains an in-flight distant page unless that page intersects the changed near boundary or falls outside the new radius
Menu scenery targets 30 FPS and active Look around/journeys target at least 60 FPS, including in Low Power Mode
The native display link drives input; measured submitted-frame intervals adapt only the 3D viewport between 75% and 100% resolution
Menus and text retain native resolution, with bounded private frame diagnostics in `logs/scenery/frames.json`
Hidden, unfocused or game-covered views stop continuous rendering; inactive streaming cancels owned generation, reads and mesh work
The requested chunk radius is 8–512 in the three generated dimensions
The nearest 8–16 chunk radius retains full voxel geometry and collision; farther terrain uses progressively coarser vertical solid bands from those same official chunks
The default is 16 chunks; stored choices remain intact
The detailed set is a Euclidean disc with one complete eight-neighbour data halo for shared-face invalidation and bounded skylight/blocklight propagation
One radial outer shell is queued at a time, and low-priority page meshes leave buried interiors on disk
Distant bands preserve canopy gaps, cavern voids and End-island undersides, including the Nether
Only completed page meshes advance the fog horizon; cancelled pages return to the pending set
A 512-chunk disc can encompass 823,473 saved chunks, so first-time preparation can take substantial time and storage
This is progressive voxel detail at distance, not hundreds of thousands of fully detailed chunks resident simultaneously
The authored Sift and historical Far Lands retain their earlier bounded renderer
The chunk-completion index is split into 32 × 32 region files rather than repeatedly parsing one growing manifest
Old completion records migrate before their header is rewritten, and the native reader can invalidate and retry a missing saved chunk twice

The left pixel-circle minimap rasterises 128 × 128 samples from the same blocks and overlays loaded residents plus distinctive structure blocks
It appears in Look around and toggles with M; F3 toggles a non-interactive debug panel with coordinates, direction, biome, chunk counts, light, FPS, render scale and Metal device
Dark covered areas and deep night enable a Look around-only neutral light floor while preserving the original block textures and world data
Physical key bindings, camera capture and master volume remain in the native Minecraft-style settings
The biome title is 1.25 times the corner-credit type size and automatically scrolls when it overflows
Reduced Motion removes animated transitions and marquee motion

Portal routes prepare and retain their generated raw terrain before choosing existing caves and excavation-weighted small joins in scenery overrides, without modifying the Bedrock database or any player world
At most two versioned route records per dimension retain the anchors, discovered cave connections and procedural seed after reopening
Legacy records remain readable and a versioned recovery copy precedes replacement; migration rebuilds owned edits instead of accumulating older excavations
The Nether path includes a nearby cave, mineshafts, dungeon, buried ruins and an obsidian lava-pool portal
The End path follows a reachable house chest where available, then a ravine/mine approach, dungeon, lush/dripstone cavern, stronghold prisons, kitchens, shrine, sleeping rooms, aqueduct and hidden portal passage
Routes share collision/meshing/map data and remain explorable; manual movement cancels the cinematic while retaining its structures
Tours target 165 seconds of movement; Space and Skip journey share the coordinator-owned portal handoff

Residents use original installed geometry and textures, swept support/medium checks, home-bounded targets, occupied-target rejection, displacement-based facing/gait and independent head glances
Right-click toggles the first visible wooden door or trapdoor within five blocks; player proximity never opens either, while villagers register only with doors and reject roaming points they cannot reach directly
Different hostile residents can occasionally approach and visibly spar without scenery health, drops or permanent deaths
Held tools reuse the extruded installed-item mesh on the left-hand attachment, and Bedrock's singular beetroot block resolves its plural stage texture as cutout crop geometry
Streamed and authored models share leg phases and the installed bat timing profile
Native rabbit adult/baby tracks own crouching, takeoff and landing, with collision checked across each hop
Declared geometry identifiers, calm visibility and native rest transforms are resolved before shared rigs and attention pivots are attached
Horse neck attention retains its native limits; turtle and axolotl movement selects their installed swimming tracks
Cube geometry and collision share size variants, with native delay ranges and a scenery approximation for runtime jump power and squish
Drowned remain bottom walkers in ambient scenery; amphibious pose selection distinguishes wet support from free water
Authored species awareness selects a 10–40% chance per eight-second attention interval
This is scenery AI, not a reproduction of the complete Minecraft behaviour/combat engine
Sift and historical Far Lands remain authored interpretations, not official dimensions or current Bedrock generation
The earlier `Adventure`, `Terrain` and `Passage` implementation remains for custom scenery and regression coverage

## Assets and sound

`Assets.swift` reads original models, block textures, fonts, structures, title art, splashes and music directly from the owner's installed data
Archive readers are bounded; newer versioned packs override older entries across PNG/TGA formats and geometry filenames
Loose same-pack files take precedence, partial catalog definitions inherit unchanged fields, and path arrays support dictionary entries
Grass colour-mask alpha selects tint while preserving opaque dirt, shortened path sides use cropped UVs, and plants use cutout geometry
Block families share opaque, cutout, blend and fluid policies; cells retain secondary water and snow-covered vegetation, and complete-cell edits clear both
Secondary vegetation uses one additional chunk mesh with primary-block context for placement and occlusion
Fluids preserve raw biome colour/fog, crop shallow side UVs and orient flowing tops from the surface gradient
Installed flipbook metadata drives cached square frames through one active scene clock
Chunk vertices carry occluded skylight and blocklight; daylight updates material uniforms rather than rebuilding geometry
No Minecraft art, music, game payload or account data is included in source exports
`Music.swift` owns one native player, bounded on-demand loading, focus/visibility pauses and the settings master-volume control
The asset queue releases archive buffers after each completed build/load

## Earlier CrossOver implementation

`./minecraft legacy --check` inspects the preserved historical path without launching it
`./minecraft legacy` and `./minecraft legacy stage` retain its account/session and isolated staging tools
The standalone launcher is the current implementation; never repair it by mutating the older bottle
See preserved upstream notices in `vendor/README.md` and the dated historical evidence in [Testing](test.md)
