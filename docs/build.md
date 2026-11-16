# Build Minecraft Launcher

Build and test locally on Apple Silicon with Apple Command Line Tools, CMake and Rust 1.97.1 or later
The separate account helper uses the pinned Rust 1.98.0 toolchain and Protocol Buffers compiler
The launcher and worker are native ARM64; the Windows game, Wine and DXMT still require Rosetta
The packaged minimum macOS version is measured from every native component, including the supplied runtime

## Build a complete local app

The `minecraft` script runs the Rust command from any working directory
Cargo reuses an unchanged release executable; there is no Python interpreter, freezer or packaging environment

```sh
./minecraft source fetch
./minecraft play --setup-only --jobs 2
./minecraft build app
./minecraft build dmg
```

First-time developer setup downloads the pinned sources and several GB of separately licensed runtime/game files
Use the Microsoft account that owns Minecraft for Windows when the sign-in window appears
`bash tools/bootstrap.sh` retains the interactive Command Line Tools and Rosetta preparation path
`./minecraft play --check` is read-only and does not sign in, build or download anything

To reuse the runtime and authorised helper from an existing signed local app, copy its verified resources into a new candidate
This does not rebuild the account helper or change the installed application

```sh
./minecraft build app --runtime-bundle "$HOME/Applications/Minecraft Launcher.app/Contents/Resources" \
  --output 'build/candidate/Minecraft Launcher.app'
```

Output paths must be new: app, preview, DMG and source export operations never merge into an existing result
Finish and verify the candidate before asking the player to quit Minecraft normally and replacing an installed app/runtime
Preserve the preceding working app as recovery, along with all accounts and saves
Local ad-hoc signatures do not establish Developer ID signing or notarisation

## Build and deploy the cloud stream

The browser path is a separate Rust binary and does not replace the native Mac application
Build the Linux host for the architecture that will run the control plane; the Windows Bedrock process itself remains x86-64

```sh
cargo build --locked --release --manifest-path stream/Cargo.toml \
  --target x86_64-unknown-linux-gnu
./minecraft stream publish --dry-run
terraform fmt -check -recursive cloud
```

The OCI image must already contain a Vulkan-capable GPU driver, Gamescope, Caddy, FFmpeg with WHIP plus NVENC or VAAPI, and MediaMTX v1.15.4
Create DNS for the chosen hostname, supply the required Terraform variables and use the built Linux `MinecraftStream` binary as `stream_binary`

```sh
terraform -chdir=cloud init
terraform -chdir=cloud plan
terraform -chdir=cloud apply
```

Terraform creates the GPU instance and narrow network policy, copies the reviewed host files and starts only Caddy, MediaMTX and the authenticated input host
It preserves the boot volume and never uploads game files, saved worlds or account credentials

Before starting gameplay, prepare `/srv/minecraft-owned` through a private administrator session and keep every file owned by the dedicated `minecraft` user
Its executable `launch` file must stay in the foreground while it runs the verified owned game through x86-64 WineGDK and DXVK, and it must own the Xbox account-service lifetime
This project does not provide a generic script that bypasses the per-user Microsoft sign-in or redistributes the game

```sh
sudo chown -R minecraft:minecraft /srv/minecraft-owned
sudo chmod 0700 /srv/minecraft-owned /srv/minecraft-owned/launch
sudo systemctl start minecraft-stream-game minecraft-stream-media
sudo minecraft-stream-link
```

Rebuild the Rust binary and run `terraform apply` again to update the host
The host-generated session token survives that update unless the administrator explicitly replaces `/etc/minecraft-stream/token`
Measure browser FPS, decode time, input p50/p95 and the `/health` queue counters on the deployed regional GPU before making performance claims

## Iterate without losing a working build

```sh
cargo build --locked --release --bin MinecraftWorker
./minecraft build launcher
./minecraft build preview --output 'build/preview/Minecraft Launcher Preview.app'
./minecraft build test
```

The development app uses this checkout and its Rust worker, while reusing readable installed artwork when the checkout has no game data
The isolated preview bundles a simulated Rust worker and never reads an account, installs a game or starts Wine
Build packaging is transactional; a failed candidate is removed from its private staging directory
Source compilation and packaging share their development output, so run one build at a time

## Command-line setup and diagnostics

```sh
./minecraft setup helper --jobs 2
./minecraft setup threading
./minecraft setup download --game-dir "$PWD/game" --market CA
./minecraft runtime check
./minecraft runtime prepare
./minecraft runtime probe graphics
./minecraft runtime launch --market CA
./minecraft monitor status
./minecraft monitor mark 'Observed a rendering problem'
./minecraft benchmark
```

Market codes are two uppercase ASCII letters
`runtime launch --network-diagnostics` enables only the existing host/status observer, with private local logs
It does not enable HTTP headers, payloads or credential tracing
Monitoring identifies the exact owned game process and its birth time; stopping it never stops Minecraft
`benchmark` measures seven isolated read-only status processes, without Microsoft or Keychain access

`tools/build/wine.sh` builds the patched compatibility runtime
`tools/build/graphics.sh` acquires the pinned DXMT release, and `tools/build/bridge.sh` builds the optional display-lifetime/handoff bridge
Their data processing and validation run in Rust
`./minecraft graphics --help` lists explicit bridge validation and staging operations
Runtime replacement refuses mapped libraries and keeps the original graphics pair for rollback

## Preparing a source release

### Update the source inventory

The explicit export allowlist is `tools/sources.txt`
Add each reviewed source, licence or document by name; do not add runtime trees or recursive globs

```sh
./minecraft source inventory
./minecraft source check
shasum -a 256 -c tools/SOURCE-SHA256.txt
./minecraft source export /existing/parent/new-source-directory
```

Export checks every path component without following symlinks, validates text/media boundaries and preserves executable permissions
A new export is promoted atomically without replacing a racing destination
`source fetch` acquires exact pinned revisions; `source verify` replays preserved patches in a private temporary tree and leaves the checkout unchanged
Never reset a modified source checkout to silence a verification failure

## Release limits

Run the checks in [Testing](test.md) and keep the evidence for compilation, installed-art rendering, live game launch and clean-Mac installation separate
The source release workflow publishes only when a requested tag is pushed
No source command signs in or bundles Microsoft game payloads into a source export
See [Release status](status.md) for the current local candidate and remaining binary release gates
