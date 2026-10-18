<h1 align="center">Minecraft for MacOS</h1>

<p align="center">
  <a href="https://github.com/keys-i/minecraft-mac/actions/workflows/checks.yml"><img src="https://github.com/keys-i/minecraft-mac/actions/workflows/checks.yml/badge.svg?branch=main" alt="Build and test checks" /></a>
  <a href="https://github.com/keys-i/minecraft-mac/actions/workflows/release.yml"><img src="https://github.com/keys-i/minecraft-mac/actions/workflows/release.yml/badge.svg?branch=main" alt="Source release checks" /></a>
  <a href="https://github.com/keys-i/minecraft-mac/actions/workflows/security.yml"><img src="https://github.com/keys-i/minecraft-mac/actions/workflows/security.yml/badge.svg?branch=main" alt="Python security analysis" /></a>
</p>

![Minecraft Bedrock on a Mac — a block-built world, waterfalls and a laptop portal](assets/poster.webp)

<p align="center">
  <strong>Play Minecraft Bedrock on your Mac</strong><br />
  An unofficial launcher for the Windows edition, with familiar controls and a native Mac window
</p>

<p align="center">
  <a href="docs/build.md#build-a-complete-local-app"><strong>Build the preview</strong></a>
  &nbsp;&nbsp; <a href="docs/play.md">Player guide</a>
  &nbsp;&nbsp; <a href="docs/status.md">Release progress</a>
</p>

> [!IMPORTANT]
> **There isn't a public DMG to download yet**
> You can build the preview from source today. The [release page](docs/status.md#before-publishing-a-binary-preview) explains what's left before an installer can be shared

## Before you start

- [ ] An **Apple Silicon Mac** running **macOS 27 or later**
- [ ] [Rosetta installed](https://support.apple.com/en-us/102527)
- [ ] A Microsoft account that owns **Minecraft for Windows**[^ownership]
- [ ] Internet access and at least **8 GB free** for game setup

## Your first launch

Once you've [built the app](docs/build.md#build-a-complete-local-app):

1. Drag **Minecraft for MacOS** into **Applications** and open it
2. Choose **Install & Play** and sign in with your Microsoft account
3. Let the game download, then choose **Sign in now** if Minecraft asks

After setup, choose **Play** to open Minecraft again

> [!TIP]
> You can press <kbd>Return</kbd> to activate the launcher's main button. Quit Minecraft normally when you're finished so your world can save

## Questions

<details>
<summary><strong>Can I play with friends on Xbox or PlayStation?</strong></summary>

Earlier builds joined a featured server and a PS5 friend's world, and displayed
the joined-Realms list. Multiplayer still needs more testing with the current
launcher, including joining an active Realm. Check the
[tested scenarios](docs/status.md#earlier-gameplay-results) before relying on a
particular setup

</details>

<details>
<summary><strong>Is this Java Edition or an official Mac version?</strong></summary>

It's the Windows **Bedrock Edition**, running through WineGDK, Rosetta and DXMT.
The launcher is native macOS; the game uses compatibility layers. This project
isn't affiliated with Mojang or Microsoft

</details>

<details>
<summary><strong>Where are my worlds, and how do I back them up?</strong></summary>

Your worlds are kept outside the app. Follow the
[backup and update steps](docs/play.md#your-files-backups-and-updates) before
replacing a build. Signing out keeps your game and worlds

</details>

<details>
<summary><strong>I want to build or contribute</strong></summary>

Start with the [build guide](docs/build.md). Once the runtime and packaging
environment are prepared, the same CLI builds the app and DMG:

```sh
python3 minecraft.py build app
python3 minecraft.py build dmg
```

| Working on | Guide |
| --- | --- |
| Building or packaging | [Build guide](docs/build.md) |
| Launcher, runtime or sign-in | [Architecture](docs/architecture.md) |
| Verifying a change | [Testing](docs/test.md) |
| Submitting a change | [Contributing](.github/CONTRIBUTING.md) |

</details>

Need a hand? [Read the player guide](docs/play.md#troubleshooting) or
[report a problem](https://github.com/keys-i/minecraft-mac/issues/new?template=bug_report.yml)

[Accessibility](docs/accessibility.md) · [Security](.github/SECURITY.md) ·
[Third-party notices](vendor/README.md)

[^ownership]: Owning Minecraft only on a phone or console doesn't establish a Windows licence. The launcher checks Windows ownership when you sign in
