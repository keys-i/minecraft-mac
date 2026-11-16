# Accessibility

This guide covers Minecraft Launcher and the repository's player documentation
Accessibility inside the Windows game and Microsoft
sign-in window also depends on those applications

## Controls implemented in the launcher

| Action | Control |
| --- | --- |
| Install, play, retry or continue | The main button, or <kbd>Return</kbd> while it is available |
| Cancel setup | **Cancel Setup**, or <kbd>Escape</kbd> while setup can be cancelled |
| Change accounts | **Minecraft Launcher → Sign Out of Microsoft…**, with the game closed |
| Get help or open logs | The **?** button or **Help** menu opens the in-app guide, which includes setup logs |
| Pause or resume background motion | **Settings → Video → Background animation** or **View → Animate Scenery** |
| Choose a scene | The four item slots in the bottom inventory bar, keys <kbd>1</kbd>–<kbd>4</kbd>, the scroll wheel, or **View**, with the selection exposed to assistive technology |
| Choose an area | The biome name at the top left opens the searchable picker; **View → Choose Biome or Landmark** also works |
| Look around | The corner spyglass or <kbd>⌘</kbd> + <kbd>L</kbd>, then fly with WASD, Space/Shift, aim with the mouse or arrows, and change areas with brackets; <kbd>⌘</kbd> + <kbd>L</kbd> or <kbd>Escape</kbd> returns to the menu |
| Mute or unmute launcher music | **Settings → Audio → Master volume**, with pointer dragging, arrow keys or accessibility increment/decrement; zero mutes it |
| Skip a portal crossing | **Skip journey** or **View → Skip Portal Journey** |
| Scenery preferences | The gear button, **Minecraft Launcher → Settings…**, or <kbd>⌘</kbd> + <kbd>,</kbd>; the top-right **×** or <kbd>Escape</kbd> closes the menu |
| Change scenery from the menu | **View**, including **Next Scene** with <kbd>⌘</kbd> + <kbd>]</kbd> |
| Reopen the launcher | **Window → Show Launcher**, or <kbd>⌘</kbd> + <kbd>0</kbd> |
| Review published app updates | **Minecraft Launcher → Check for Updates…** |

After Play, the scenery and controls are replaced by a full-window loading screen
It uses the installed Bedrock dirt background and ten-frame loading animation,
without invented generation percentages. Status remains text and Cancel stays
available during cancellable setup. The animation stops under Reduced Motion,
Low Power Mode or an inactive window
The launcher waits for the game window before hiding the native app
It returns after game exit/error; **Window → Show Launcher** remains available
Quitting the launcher while Minecraft runs leaves its owned game session running
It no longer presents a Keep Open blocker
Buttons start grey and turn green on hover, alongside their existing focus outline
Inventory slots keep grey hover feedback and the original selection frame
Disabled controls keep their disabled appearance

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
Settings uses the launcher window without a separate title bar. Its text and controls
scale with window size, and long category content scrolls
The category content scrolls independently of its persistent heading and 44-point close
button. Background launcher controls and keyboard shortcuts are disabled while
Settings is open; all sliders retain arrow and accessibility adjustments
Original installed artwork supplies the main title and Minecraft Ten supplies
the subtitle. Both scale with window width and height, including fullscreen
Pixel typography identifies the fallback title and shortcut toast
Actions and regular menu text use installed Mojangles, while section headings use
Minecraft Ten. Bundled Monocraft remains available before game art is installed
Deliberate spectator input, terrain streaming and minimap updates remain available
with ambient animation off; inactive windows stop their map-update timer
Main controls and corner credits reach 5× their area in the tested fullscreen layout
They shrink together in smaller windows to preserve distinct hit targets
Hover adds a short enlargement and brightness change; Reduced Motion removes
the enlargement and transition while keeping immediate brightness feedback
Text shadows are soft, low-opacity and offset by one point
The bundled font is registered only within this app; the owner’s subtitle font
is created in memory without a system font installation

The achievement toast appears when the rendered camera arrives in another biome or realm
It stays for four seconds, fades over 400 ms, and never repeats from an idle timer
The paper doll stays hidden until that fade is complete, then its limbs and cape follow camera movement
Reduced Motion removes the transition and pose animation, while focus and low power pause the character renderer
Routine scenery progress stays in the background; a centred error offers Try again when necessary

The README uses labelled links, image descriptions, headings and expandable
sections. The poster's message is repeated in ordinary text so the image is
not required to understand what the project does

The area and realm controls are unavailable until installed game art is ready
An unsupported scenery format falls back to the approved poster without blocking
the setup controls

The minimap has a stepped circular edge, a north marker and text coordinates
M toggles it while exploring; Settings → Keyboard & Mouse can change that shortcut
The input recorder cancels on Escape, focus loss and closing the settings
It reserves Command-Q and names any swapped control after a conflict
Help uses an in-window menu with the same pixel font, close button and Escape
behaviour as Settings. Credits and version text have a 24-point minimum
The optional character preview has a descriptive accessibility label and visible
recovery for a missing image, and honours reduced motion and low power

## Known limits

Large text, display zoom, increased contrast, keyboard focus and VoiceOver
announcements during changing setup states have not yet been manually verified
with the redesigned interface. Standard controls alone do not establish
VoiceOver or WCAG conformance
Spectator flight supports keyboard movement and aiming; full-window event
routing, focus restoration and VoiceOver operation still need manual checks
Music uses the labelled master-volume control in Settings; no task depends on
hearing it; it pauses outside the focused launcher and while the game runs
The splash stays still with Reduced Motion, Low Power or paused scenery
Mouse-look hides/releases the cursor with native APIs only while the launcher
is key. Escape, responder/window focus loss and teardown release it and remove
the local event monitor; arrow-key aiming remains available
The developer credit is a native Link with an accessible destination label
Long biome names scroll while active; Reduced Motion shows the full static name
The advancement-style hint retains its 60-second display and focused return wait

The launcher cannot supply accessibility features missing from the Windows
game or Microsoft's sign-in window. Handle macOS security and Keychain prompts
yourself; automation does not dismiss or approve them

## Manual checks still needed

- [ ] Complete first setup, retry and sign-out with keyboard navigation
- [ ] Read every button, status, error and progress change with VoiceOver
- [ ] Check focus when setup starts, is cancelled, fails and finishes
- [ ] Check long error messages with large text and display zoom
- [ ] Check spectator WASD/Space/Shift/arrows, mouse capture/release, Control sprint, wheel realm selection, Control-wheel speed, brackets and area crossings
- [ ] Check spyglass button/⌘L/Escape, rapid realm changes and focus after the biome popover closes
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
