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
| Pause or resume background motion | The labelled scenery button beside Help |
| Choose a scene | **Overworld**, **Nether**, **The End** or **The Sift**, with the selection exposed to assistive technology |
| Choose an area | The labelled map menu or **View → Choose Biome or Landmark** |
| Skip a portal crossing | **Skip journey** or **View → Skip Portal Journey** |
| Scenery preferences | **Minecraft for MacOS → Settings…**, or <kbd>⌘</kbd> + <kbd>,</kbd> |
| Change scenery from the menu | **View**, including **Next Scene** with <kbd>⌘</kbd> + <kbd>]</kbd> |
| Reopen the launcher | **Window → Show Launcher**, or <kbd>⌘</kbd> + <kbd>0</kbd> |
| Review published app updates | **Minecraft for MacOS → Check for Updates…** |

The interface uses standard SwiftUI text, buttons and progress controls with
custom world-style drawing. The main button has an explicit keyboard focus
outline. The block-built progress indicator has a label and percentage, and the
decorative scenery, 3D actors and particles are hidden from assistive technology
The area menu and passage controls remain accessible outside that decorative layer
Each
setup step exposes whether it is current, complete or upcoming. Status and errors are
written as text rather than communicated through colour alone

Worker stage and title changes request a macOS accessibility announcement;
percentage-only updates do not repeat it. Reduced Motion disables the button
animation, camera motion, 3D actor actions, flowing textures, particles, biome journeys and automatic realm changes
Low Power Mode also stops ambient motion and automatic scene changes. Waiting
states use text rather than a spinner. Reduce Transparency gives the launch
panel an opaque background. The window can be resized,
and its content scrolls so longer status and error messages remain reachable

The README uses labelled links, image descriptions, headings and expandable
sections. The poster's message is repeated in ordinary text so the image is
not required to understand what the project does

## Known limits

Large text, display zoom, increased contrast, keyboard focus and VoiceOver
announcements during changing setup states have not yet been manually verified
with the redesigned interface. Standard controls alone do not establish
VoiceOver or WCAG conformance

The launcher cannot supply accessibility features missing from the Windows
game or Microsoft's sign-in window. Handle macOS security and Keychain prompts
yourself; automation does not dismiss or approve them

## Manual checks still needed

- [ ] Complete first setup, retry and sign-out with keyboard navigation
- [ ] Read every button, status, error and progress change with VoiceOver
- [ ] Check focus when setup starts, is cancelled, fails and finishes
- [ ] Check long error messages with large text and display zoom
- [ ] Check increased contrast, light/dark appearance and reduced motion
- [ ] Check pause/resume, all area choices, Skip journey, Reduce Transparency and Low Power Mode
- [ ] Check Settings, Edit, View, Window, Help, About, Services, updates and protected Quit
- [ ] Check that scenery stops in the background, behind other windows and during gameplay
- [ ] Verify that game input capture can return control to macOS as expected

These are acceptance checks, not recorded passes. Use a disposable test world
and preserve existing saves when testing transitions into the game

## Report a barrier

Open a [problem report](https://github.com/keys-i/minecraft-mac/issues/new?template=bug_report.yml)
and choose **Accessibility or keyboard controls**. Describe the action, what
blocked it, your Mac/macOS version and any relevant accessibility setting or
assistive technology. Include only a short, reviewed error excerpt if needed
