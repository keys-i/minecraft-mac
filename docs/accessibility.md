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

The interface uses standard SwiftUI text, buttons and progress controls with
custom block-style drawing. The main button has an explicit keyboard focus
outline. The progress bar has a label and percentage, and the decorative poster
and grass edge are hidden from assistive technology. Status and errors are
written as text rather than communicated through colour alone

Worker stage and title changes request a macOS accessibility announcement;
percentage-only updates do not repeat it. Reduced Motion disables the button
animation and replaces the waiting spinner with text. The window can be resized,
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
- [ ] Verify that game input capture can return control to macOS as expected

These are acceptance checks, not recorded passes. Use a disposable test world
and preserve existing saves when testing transitions into the game

## Report a barrier

Open a [problem report](https://github.com/keys-i/minecraft-mac/issues/new?template=bug_report.yml)
and choose **Accessibility or keyboard controls**. Describe the action, what
blocked it, your Mac/macOS version and any relevant accessibility setting or
assistive technology. Include only a short, reviewed error excerpt if needed
