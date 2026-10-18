# Performance

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

## Launch handoff

The session now checks the child process it started while waiting for the
account socket, avoiding repeated external process discovery. It checks every
50 ms rather than every 250 ms. Adopting an existing helper still verifies its
PID and executable; socket type, ownership and permissions remain mandatory

Reproduce the comparison from this repository, which retains upstream history

```sh
mkdir -p work
git show 99fc9aa:standalone.py > work/before.py
python3 -B tests/benchmark.py work/before.py
python3 -B tests/benchmark.py
```

The fixture removes its child, socket and temporary directory after each run
Run variants in sequence without compiling or profiling concurrently

## Included runtime

The game uses x86-64 WineGDK 11.8 through Rosetta and DXMT v0.80 for Direct3D 11
on Metal. DXMT's shader caches remain enabled by default. No image-quality
reduction, frame cap, unsafe compiler flag or altered game file is used to
produce the results above

The package retains the verified display/ColorSync lifetime correction and
IPv6 adapter index correction. The display-query probe previously measured
784,384 retained bytes upstream and 16,384 bytes with the correction after
2,000 queries; see [the graphics evidence](GRAPHICS.md)

Menu window checks observed 20 responses over 45 seconds with a maximum
response time of 13 ms after restarting the earlier blocked session. This
measures Windows message handling. After installing this candidate on October
19, the user confirmed that Marketplace and skin changes both opened quickly.
This verifies the reported menu behaviour in that session; it does not measure
transaction latency or gameplay frame times

## Packaging

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

## Comparison limits

No Windows or native Java Edition baseline was measured. Faster-than-Windows,
native Bedrock performance and universal FPS improvements are not established
by these results. A gameplay comparison needs the same Bedrock world, camera,
resolution, render distance and warm shader caches on the reference systems

The current candidate requires macOS 27 and Rosetta. It is an ad-hoc signed
local preview; notarization, dependency redistribution review and clean-Mac
installation remain separate release work
