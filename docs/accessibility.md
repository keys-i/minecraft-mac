# Accessibility

This guide covers the native Minecraft for MacOS launcher and the repository's
player documentation. Accessibility inside the Windows game and Microsoft
sign-in window also depends on those applications

## Controls implemented in the launcher

| Action | Control |
| --- | --- |
| Install, play, retry or continue | The main button, or <kbd>Return</kbd> while it is available |
| Cancel setup | **Cancel Setup**, or <kbd>Escape</kbd> while setup can be cancelled |
| Change accounts | **Minecraft for MacOS → Sign Out of Microsoft…**, with the game closed |
| Get help or open logs | The **Help** menu |
| Pause or resume background motion | **Settings → Animate the background adventure** or **View → Animate Scenery** |
| Choose a scene | The four item slots in the bottom inventory bar, keys <kbd>1</kbd>–<kbd>4</kbd>, or **View**, with the selection exposed to assistive technology |
| Choose an area | The biome name at the top left opens the searchable picker; **View → Choose Biome or Landmark** also works |
| Look around | The eye-and-arrows button at the bottom right or <kbd>⌘</kbd> + <kbd>L</kbd>, then fly with WASD, Space/Shift, aim with mouse movement or arrows, and change biomes with brackets; the same button, shortcut or <kbd>Escape</kbd> restores the route |
| Mute or unmute launcher music | The labelled speaker button; Settings also supplies a volume slider |
| Skip a portal crossing | **Skip journey** or **View → Skip Portal Journey** |
| Scenery preferences | **Minecraft for MacOS → Settings…**, or <kbd>⌘</kbd> + <kbd>,</kbd> |
| Change scenery from the menu | **View**, including **Next Scene** with <kbd>⌘</kbd> + <kbd>]</kbd> |
| Reopen the launcher | **Window → Show Launcher**, or <kbd>⌘</kbd> + <kbd>0</kbd> |
| Review published app updates | **Minecraft for MacOS → Check for Updates…** |

The interface uses standard SwiftUI text, buttons and progress controls with
custom world-style drawing. Buttons have an explicit keyboard focus
outline. The segmented experience bar has a label and percentage, and the
decorative scenery, 3D actors and particles are hidden from assistive technology
The free-look crosshair is decorative and is hidden too
The area menu and passage controls remain accessible outside that decorative layer
Each
setup step exposes whether it is current, complete or upcoming. Status and errors are
written as text rather than communicated through colour alone

Worker stage and title changes request a macOS accessibility announcement;
percentage-only updates do not repeat it. Reduced Motion disables the button
animation, camera motion, 3D actor actions, flowing textures, particles, biome journeys and automatic realm changes
Low Power Mode also stops ambient motion and automatic scene changes. Waiting
states use text rather than a spinner. Reduce Transparency gives the launch
panel an opaque background. The window can be resized down to 760 × 620 points
Long status details scroll inside the setup panel and remain selectable
Original installed artwork supplies the main title and Minecraft Ten supplies
the subtitle. Pixel typography identifies the fallback title and shortcut toast; rounded system type identifies
actions and section titles, while explanatory copy uses plain system type
Text shadows are soft, low-opacity and offset by one point
The bundled font is registered only within this app; the owner’s subtitle font
is created in memory without a system font installation

The shortcut toast displays **⌘ + L to look around** for 60 seconds, then returns
after 70 uninterrupted seconds with the launcher as the active window
Switching to another app or Settings cancels that return wait. Entering spectator
view shows 60-second movement instructions; leaving dismisses them. Setup, errors
and journeys suppress hints. The instruction remains available through the eye button's
label/help even while the toast is hidden; no repeated VoiceOver announcement is requested
Reduced Motion replaces the toast fade with an immediate change

The README uses labelled links, image descriptions, headings and expandable
sections. The poster's message is repeated in ordinary text so the image is
not required to understand what the project does

The area and realm controls are unavailable until installed game art is ready
An unsupported scenery format falls back to the approved poster without blocking
the setup controls

## Known limits

Large text, display zoom, increased contrast, keyboard focus and VoiceOver
announcements during changing setup states have not yet been manually verified
with the redesigned interface. Standard controls alone do not establish
VoiceOver or WCAG conformance
Spectator flight supports keyboard movement and aiming; full-window event
routing, focus restoration and VoiceOver operation still need manual checks
Music uses a visible mute button and labelled volume slider; no task depends on
hearing it. It pauses outside the focused launcher and while the game runs
The splash stays still with Reduced Motion, Low Power or paused scenery
Mouse-look hides/releases the cursor with native APIs only while the launcher
is key. Escape, responder/window focus loss and teardown release it and remove
the local event monitor; arrow-key aiming remains available
The developer credit is a native Link with an accessible destination label

The launcher cannot supply accessibility features missing from the Windows
game or Microsoft's sign-in window. Handle macOS security and Keychain prompts
yourself; automation does not dismiss or approve them

## Manual checks still needed

- [ ] Complete first setup, retry and sign-out with keyboard navigation
- [ ] Read every button, status, error and progress change with VoiceOver
- [ ] Check focus when setup starts, is cancelled, fails and finishes
- [ ] Check long error messages with large text and display zoom
- [ ] Check spectator WASD/Space/Shift/arrows, mouse capture/release, Control sprint, scroll speed, brackets and area crossings
- [ ] Check eye button/⌘L/Escape, rapid realm changes and focus after the biome popover closes
- [ ] Check music volume/mute, track completion, window switching, occlusion and gameplay handoff
- [ ] Check the 60-second toast expiry and 70-second return, including Settings and app switching
- [ ] Check increased contrast, light/dark appearance and reduced motion
- [ ] Check pause/resume, all area choices, Skip journey, Reduce Transparency and Low Power Mode
- [ ] Check Settings, Edit, View, Window, Help, About, Services, updates and protected Quit
- [ ] Check clickable developer credit and lower-corner version at narrow/wide sizes
- [ ] Check day/night lighting and advancement hints with Increased Contrast and Reduced Motion
- [ ] Check that scenery stops in the background, behind other windows and during gameplay
- [ ] Verify that game input capture can return control to macOS as expected

These are acceptance checks, not recorded passes. Use a disposable test world
and preserve existing saves when testing transitions into the game

## Report a barrier

Open a [problem report](https://github.com/keys-i/minecraft-mac/issues/new?template=bug_report.yml)
and choose **Accessibility or keyboard controls**. Describe the action, what
blocked it, your Mac/macOS version and any relevant accessibility setting or
assistive technology. Include only a short, reviewed error excerpt if needed
