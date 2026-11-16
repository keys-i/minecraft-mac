# Using Minecraft Launcher

This is an open-source preview. There is no public notarized installer yet.
The steps below describe a complete local app built from this repository;
GitHub's **Download ZIP** contains source, not an installable app. Developers can
follow [the build guide](build.md).

## Before you start

- An Apple Silicon Mac. Intel Macs are not supported by the current launcher.
- macOS 27 or newer for the current local bundle. A component targeting an
  older OS does not mean the whole app can run there
- Rosetta, which runs the Intel-based Wine and graphics components. Follow
  [Apple's Rosetta instructions](https://support.apple.com/en-us/102527).
- An internet connection and a Microsoft account that owns **Minecraft for
  Windows**. Ownership only on a console or phone does not establish that PC
  entitlement. The launcher checks the account's actual license with Microsoft.
- At least 8 GB free for game setup; leave more room for worlds, backups, and
  temporary files. This is not the storage budget for compiling the project.

The current launcher verifies the account on each Play action. It has no
supported offline-launch mode. The native UI currently uses Store market `CA`;
developers can select a different two-letter market through the CLI.

Rosetta-free execution is not supported by this build
Apple provides general Rosetta support through macOS 27 and limits it to certain
older games in macOS 28; this launcher's eligibility has not been established
The native launcher alone does not remove the x64 game's translation requirement

## Install, sign in, and play

1. Open your locally built `.dmg` and drag **Minecraft Launcher** onto its
   **Applications** shortcut. Eject the disk image after copying finishes.
2. Open **Minecraft Launcher** from Applications and click **Install & Play**.
3. Complete Microsoft sign-in with the account that owns the Windows game.
4. Let setup download Minecraft and the required Microsoft component. There
   are no separate Homebrew, Python, compiler, Wine, or DXMT installs for players
   using the complete app bundle.
5. If Minecraft shows its welcome screen, select **Sign in now** to use the
   Microsoft session. Confirm your expected gamertag in the game.

Later launches show **Play**. Quit Minecraft normally to finish the session.
You can close the launcher window while playing; the launcher keeps its account
service running until Minecraft exits. Reopen the app to return to its window.

**Cancel** pauses setup and keeps completed game installation steps and worlds.
Choose **Continue** to retry. An interrupted game-file download restarts; it is
not a resumable transfer. Avoid starting multiple copies of the app.

## Background scenery

Look around keeps the pointer captured for camera movement and hides clickable
menu controls. Press **Escape** to use the menus again
The pixel minimap sits on the left; **M** shows or hides it
Use **Settings → Keyboard & Mouse** to change movement, map, realm and travel keys
Conflicting assignments swap, and Escape cancels recording

**Settings → Video → World seed** creates a repeatable launcher landscape after
**Generate** or Return. It is separate from the seed of any saved Minecraft world
**Settings → Character** accepts your exported skin and cape PNGs for the small
paper doll. Choose slim arms only for a modern three-pixel arm skin
These local files stay on your Mac; no default skin is shown as your character

After Minecraft is installed, click the biome name at the top left to find an
area. Choose realms with the four inventory slots, keys **1–4**, or the scroll wheel
Normal realm changes pass through a mine’s Nether portal, a stronghold’s End
portal or an artistic Sift rift
The longer cave tours normally take 2–3 minutes; **Space** and **Skip journey** use the destination portal transition
Entering Look around interrupts the tour and leaves the same caves and ruins explorable
The main menu groups Play and Settings in the centre, with one corner spyglass
Settings has Video, Audio, Keyboard & Mouse, Character and Accessibility categories
Video controls background animation, automatic touring and chunk distance
Audio has master volume; Keyboard & Mouse has sensitivity, inverted Y and all key bindings
Each category has its own Reset defaults button
Choose **Abandoned mineshaft** or **Stronghold · Portal room** in the area picker
to explore the tunnels, side shafts, libraries and portal room at your own pace

The spyglass button at the bottom right or **⌘L** enters spectator view
Fly with **WASD**, rise with **Space**, descend with **Shift**, and aim by moving
the mouse. **Control** sprints; **Control + Scroll** changes flight speed. The arrow keys also
turn the camera. Mouse-look captures the cursor; **Escape** releases it and
returns to the menu. Switching windows releases it too; click the scene to recapture
Fly north, south, east or west to enter a neighbouring biome without a scene swap
The picker and **[ / ]** guide you towards another area; movement keys take control
Wooden doors open as you approach; Escape returns to the biome picker and hotbar
The three normal dimensions use seed-based chunks from the pinned official Bedrock generator
Biomes can repeat, and generated rivers, lakes, caves and structures share the same world data
The custom Sift and historical Far Lands use the authored scenery renderer
Guided underground journeys keep their scenery additions available to explore
The minimap appears while Look around is open and leaves with spectator mode
It shows north, terrain and your coordinates. Its historical Far Lands view is
marked map-unavailable because that 3D wall has no shared heightmap
Turning off background animation keeps deliberate flight and its map available
Settings controls **Render distance** in 16 × 16-block chunks, from 8 to 512
New installations and Reset defaults use 16 chunks; existing choices are preserved
Nearby terrain keeps full block detail; distant detail is sampled progressively from the same generated chunks
Large distances need substantial first-time generation and disk space; preparations stay in the background
The previous scene or installed panorama stays visible until nearby terrain is ready for Look around
Choose **Far Lands** in the Overworld picker to visit a historical recreation;
choose another area to return. It is not a current Bedrock biome
The Overworld village includes pigs, horses, baby animals and a crowned
Technoblade tribute pig with a red cape. The woodland mansion contains a chicken jockey
Use **⌘L** or **Escape** to return to a hover where you are

An achievement appears when a new biome or realm is reached, stays for four seconds and fades away
The paper doll stays hidden until that fade ends, then follows your movement with animated limbs and cape
Scenery preparation has no frontend progress bar; a centred error offers Try again if preparation fails
