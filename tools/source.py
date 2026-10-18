#!/usr/bin/env python3
"""Export reviewed source files only; never walk the private working tree."""

import argparse
import hashlib
import os
import re
import subprocess
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
INVENTORY = 'tools/SOURCE-SHA256.txt'


# Add individually reviewed source files here. Directories and globs are forbidden.
# Both runtime paths and the source clones are deliberately absent.
ALLOWED_FILES = (
    'minecraft.py',
    '.gitignore',
    '.gitattributes',
    'README.md',
    'assets/README.md',
    'assets/hero.webp',
    'assets/launcher.jpg',
    'AGENTS.md',
    'docs/CONTEXT.md',
    '.github/SECURITY.md',
    '.github/CONTRIBUTING.md',
    'tools/requirements.txt',
    '.github/workflows/checks.yml',
    '.github/workflows/release.yml',
    '.github/workflows/security.yml',
    '.github/dependabot.yml',
    '.github/ISSUE_TEMPLATE/bug_report.yml',
    'docs/RELEASE.md',
    'docs/USER_GUIDE.md',
    'docs/DEVELOPMENT.md',
    'docs/TESTING.md',
    'docs/STABILITY.md',
    'docs/PERFORMANCE.md',
    'docs/LEGACY.md',
    'src/launcher/Icon.swift',
    'LICENSE',
    'vendor/README.md',
    'vendor/licenses/Wine-LGPL-2.1-or-later.txt',
    'vendor/licenses/Wine-NOTICE.txt',
    'vendor/licenses/dxmt-LICENSE.txt',
    'vendor/licenses/dxmt-DXVK-LICENSE.txt',
    'vendor/licenses/dxmt-LLVM-LICENSE.txt',
    'vendor/licenses/dxmt-MinGW-LICENSE.txt',
    'vendor/licenses/DXMT-embedded-NOTICES.txt',
    'tools/bootstrap.sh',
    'tools/setup.py',
    'tools/build/install.sh',
    'tools/monitor.py',
    'tools/legacy/launch.py',
    'src/standalone.py',
    'src/standalone-setup.py',
    'src/standalone-gameinput.py',
    'tools/graphics.py',
    'docs/SETUP.md',
    'tools/legacy/run-windows.sh',
    'tools/build.py',
    'src/launcher/BedrockLauncher.swift',
    'src/launcher/setup.py',
    'tools/build/wine.sh',
    'tools/build/graphics.sh',
    'tools/build/pool.sh',
    'tools/build/bridge.sh',
    'tools/build/probes.sh',
    'docs/GRAPHICS.md',
    'tools/legacy/stage-runtime.py',
    'tools/source.py',
    'tools/legacy/bedrock-helper.rs',
    'src/standalone-helper.rs',
    'tools/legacy/prepare-owned-game.rs',
    'tools/probes/runtime-auth-probe.c',
    'tools/probes/runtime-privilege-probe.c',
    'tools/probes/graphics-probe.c',
    'tools/probes/standalone-graphics-probe.c',
    'tools/probes/standalone-graphics-shader-probe.c',
    'tools/probes/standalone-dxmt-autorelease-shim.m',
    'tools/probes/standalone-dxmt-display-trace.c',
    'tools/probes/standalone-dxmt-display-probe.m',
    'tools/probes/store-callback-probe.c',
    'tools/legacy/gameinput.reg',
    'src/winrt.reg',
    'vendor/patches/Cargo.lock',
    'vendor/patches/xodus-real-store-license.patch',
    'vendor/patches/winegdk-macos-local.patch',
    'vendor/patches/minecraft-store-callback.patch',
    'vendor/patches/standalone-wine-dxmt-abi.patch',
    'vendor/patches/standalone-dxmt-memory-lifetime.patch',
    'vendor/patches/standalone-wine-storage-linkage.patch',
    'vendor/patches/standalone-wine-idl-list.patch',
    'vendor/patches/standalone-wine-ipv6.patch',
    'vendor/patches/standalone-wine-user-privileges.patch',
    'vendor/patches/standalone-wine-xuser-realms.patch',
    'vendor/patches/standalone-wine-xuser-token-refresh.patch',
    'vendor/patches/standalone-wine-xuser-z-device-auth.patch',
    'vendor/patches/keychain-cache.patch',
    'vendor/patches/unified-helper.patch',
    'vendor/patches/standalone-signin-window.patch',
    'vendor/patches/standalone-keychain-write.patch',
    'docs/PUBLISHING.md',
    'tests/test_export_source.py',
    'tests/test_bootstrap_sources.py',
    'tests/test_standalone.py',
    'tests/test_onboarding.py',
    'tests/test_packaging.py',
    'tests/benchmark.py',
    'tests/test_threading_download.py',
    'tests/test_start.py',
    'tests/test_bedrock_monitor.py',
    'tests/test_standalone_setup.py',
    'tests/test_standalone_dxmt_unix.py',
    'tests/xuser-claims.c',
    'tests/xuser-realms.c',
    'tests/xuser-refresh.c',
    'tests/xuser-refresh-live.c',
    'tests/xuser-rta-live.c',
    'tests/run-xuser-refresh-live.sh',
    'tests/run-xuser-rta-live.sh',
    'tests/run-xuser-tests.sh',
    'tests/XUSER.md',
    'tools/legacy/build.sh',
    'tests/test_cli.py',
)

PRIVATE_ROOTS = frozenset({
    "sources", "downloads", "runtime", "logs", "bottles", "build", "game",
    ".git", "__pycache__", "exports", "work", "outputs",
})


def checked_relative(name):
    path = PurePosixPath(name)
    if (not name or path.is_absolute() or str(path) != name
            or any(part in (".", "..") for part in path.parts)
            or path.parts[0] in PRIVATE_ROOTS or "\\" in name
            or "\n" in name or "\r" in name):
        raise ValueError("Unsafe export entry: " + repr(name))
    return path


def read_source(root, name):
    """Reject symlinks in every component, not just symlinks at the leaf."""
    relative = checked_relative(name)
    image = relative.suffix in (".jpg", ".webp")
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError("Refusing symlink in export path: " + name)
    if not current.is_file() or not current.resolve().is_relative_to(root):
        raise ValueError("Missing regular source file: " + name)
    # Open each directory relative to its validated descriptor. O_NOFOLLOW on
    # every component also closes a parent-symlink swap between check and read.
    directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in relative.parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                            dir_fd=directory)
            os.close(directory)
            directory = child
        descriptor = os.open(relative.name, os.O_RDONLY | os.O_NOFOLLOW,
                             dir_fd=directory)
    finally:
        os.close(directory)
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode):
            raise ValueError("Refusing non-regular source file: " + name)
        if image and info.st_size > 2 * 1024 * 1024:
            raise ValueError("README image exceeds 2 MiB: " + name)
        content = stream.read()
    if image:
        jpeg = (relative.suffix == ".jpg" and content.startswith(b"\xff\xd8\xff")
                and content.endswith(b"\xff\xd9"))
        webp = (relative.suffix == ".webp" and content[:4] == b"RIFF"
                and content[8:12] == b"WEBP" and content[12:16] in (b"VP8 ", b"VP8L", b"VP8X")
                and int.from_bytes(content[4:8], "little") == len(content) - 8)
        if not jpeg and not webp:
            raise ValueError("Invalid README image format: " + name)
    else:
        try:
            content.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise ValueError("Refusing non-text source file: " + name) from exc
        if b"\0" in content:
            raise ValueError("Refusing binary source file: " + name)
    return content, 0o755 if info.st_mode & 0o111 else 0o644


def collect_sources(root, allowlist=ALLOWED_FILES):
    root = Path(root)
    if root.is_symlink():
        raise ValueError("The source root must not be a symlink")
    root = root.resolve(strict=True)
    if len(set(allowlist)) != len(allowlist):
        raise ValueError("Duplicate source export entry")
    return [(name, *read_source(root, name)) for name in allowlist]


def export_sources(root, destination, allowlist=ALLOWED_FILES):
    files = collect_sources(root, allowlist)
    destination = Path(destination).absolute()
    if destination.exists() or destination.is_symlink():
        raise ValueError("Destination already exists; choose a new directory")
    # Require an existing parent: do not silently create paths outside user intent.
    parent = destination.parent.resolve(strict=True)
    if not parent.is_dir():
        raise ValueError("Destination parent is not a directory")
    destination = parent / destination.name
    stage = Path(tempfile.mkdtemp(prefix=".bedrock-source-", dir=parent))
    try:
        digest_lines = []
        for name, content, mode in files:
            target = stage / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            target.chmod(mode)
            digest_lines.append(f"{hashlib.sha256(content).hexdigest()}  {name}\n")
        (stage / INVENTORY).parent.mkdir(parents=True, exist_ok=True)
        (stage / INVENTORY).write_text("".join(digest_lines), encoding="utf-8")
        # Rename is atomic on this volume. Never merge into an existing directory.
        if destination.exists() or destination.is_symlink():
            raise ValueError("Destination appeared during export")
        stage.rename(destination)
    except BaseException:
        shutil.rmtree(stage)
        raise
    return len(files)


PROJECTS = {
    "xodus": {
        "url": "https://github.com/xodus-gaming/xodus.git",
        "commit": "0670e25aeb0e0e9f800f8f2f4968ae3b681842a7",
        "patches": ("xodus-real-store-license.patch", "keychain-cache.patch", "unified-helper.patch", "standalone-signin-window.patch", "standalone-keychain-write.patch"),
    },
    "winegdk": {
        "url": "https://github.com/Sightem/WineGDK.git",
        "commit": "b5d23b074cfd5e28e79acceaaefaf41a26ce6272",
        "patches": ("winegdk-macos-local.patch", "minecraft-store-callback.patch"),
    },
    "dxmt": {
        "url": "https://github.com/3Shain/dxmt.git",
        "commit": "589adb780354b461645b29999cefaf533594ee99",
        "patches": (),
    },
}


def run(*args, cwd=None, capture=False):
    return subprocess.run(args, cwd=cwd, check=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def patch_paths(patches):
    paths = set()
    for patch in patches:
        for line in patch.read_text(encoding="utf-8").splitlines():
            match = re.match(r"^(?:--- a/|\+\+\+ b/)([^\t]+)(?:\t.*)?$", line)
            if not match:
                continue
            name = match.group(1)
            path = PurePosixPath(name)
            if path.is_absolute() or ".." in path.parts or str(path) != name or "\\" in name:
                raise ValueError("Unsafe patch path: " + name)
            paths.add(name)
    return sorted(paths)


def apply_project(root, name, project, source_root=ROOT):
    for patch in project["patches"]:
        file = source_root / "vendor/patches" / patch
        run("git", "apply", "--check", str(file), cwd=root)
        run("git", "apply", str(file), cwd=root)
    if name == "xodus":
        shutil.copyfile(source_root / "vendor/patches/Cargo.lock", root / "Cargo.lock")


def bootstrap(destination, names, source_root=ROOT):
    destination = Path(destination).absolute()
    if destination.is_symlink():
        raise ValueError("Source destination must not be a symlink")
    destination.mkdir(parents=True, exist_ok=True)
    destination = destination.resolve()
    for name in names:
        target = destination / name
        if target.exists() or target.is_symlink():
            raise ValueError(f"{target} already exists; use --check to verify it")
    for name in names:
        project = PROJECTS[name]
        temp = Path(tempfile.mkdtemp(prefix=f".{name}-bootstrap-", dir=destination))
        try:
            run("git", "init", "--quiet", str(temp))
            run("git", "remote", "add", "origin", project["url"], cwd=temp)
            run("git", "fetch", "--depth", "1", "origin", project["commit"], cwd=temp)
            run("git", "checkout", "--quiet", "--detach", "FETCH_HEAD", cwd=temp)
            actual = run("git", "rev-parse", "HEAD", cwd=temp, capture=True).decode().strip()
            if actual != project["commit"]:
                raise ValueError(f"Unexpected {name} source revision")
            apply_project(temp, name, project, source_root)
            if (destination / name).exists() or (destination / name).is_symlink():
                raise ValueError(f"Destination {name} appeared during preparation")
            temp.rename(destination / name)
        except BaseException:
            shutil.rmtree(temp)
            raise
        print(f"Prepared {name} at {project['commit']}", flush=True)


def verify_project(repository, name, project, source_root=ROOT):
    """Replay patches in a tiny temporary tree; never modify an installed checkout."""
    repository = Path(repository)
    if repository.is_symlink():
        raise ValueError("Refusing a symlink source checkout")
    actual = run("git", "rev-parse", "HEAD", cwd=repository, capture=True).decode().strip()
    if actual != project["commit"]:
        raise ValueError(f"{name} is not at the pinned source revision")
    patches = [source_root / "vendor/patches" / patch for patch in project["patches"]]
    paths = patch_paths(patches)
    tracked = {}
    for entry in run("git", "ls-tree", "-rz", project["commit"],
                     cwd=repository, capture=True).decode().split("\0"):
        if entry:
            metadata, path = entry.split("\t", 1)
            tracked[path] = metadata.split()[0]
    with tempfile.TemporaryDirectory(prefix="bedrock-source-check-") as temp:
        prepared = Path(temp)
        for path in paths:
            if path in tracked:
                target = prepared / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(run("git", "show", project["commit"] + ":" + path,
                                       cwd=repository, capture=True))
                target.chmod(0o755 if tracked[path] == "100755" else 0o644)
        apply_project(prepared, name, project, source_root)
        if name == "xodus":
            paths.append("Cargo.lock")
        for path in paths:
            target = repository / path
            if target.is_symlink() or not target.is_file():
                raise ValueError(f"Missing regular patched source file: {name}/{path}")
            if target.read_bytes() != (prepared / path).read_bytes():
                raise ValueError(f"Source differs from preserved patches: {name}/{path}")
    return len(paths)



def inventory(files):
    """Hash only individually reviewed files, in the published order"""
    return ''.join(f'{hashlib.sha256(content).hexdigest()}  {name}\n' for name, content, _mode in files)


def main(argv=None):
    parser = argparse.ArgumentParser(description='Fetch pinned sources and prepare reviewed source releases')
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ('fetch', 'verify'):
        command = commands.add_parser(name)
        command.add_argument('--project', choices=('all', *PROJECTS), default='all')
        command.add_argument('--destination', type=Path, default=ROOT / 'sources')
    command = commands.add_parser('export', help='Export the reviewed source into a new directory')
    command.add_argument('destination', type=Path)
    commands.add_parser('inventory', help='Refresh the reviewed source checksums')
    commands.add_parser('check', help='Validate source boundaries and recorded checksums')
    commands.add_parser('list', help='List the individually reviewed source files')
    args = parser.parse_args(argv)
    try:
        if args.command in ('fetch', 'verify'):
            names = tuple(PROJECTS) if args.project == 'all' else (args.project,)
            if args.command == 'fetch':
                bootstrap(args.destination, names)
            else:
                for name in names:
                    count = verify_project(args.destination / name, name, PROJECTS[name])
                    print(f'Verified {name}: pinned revision and {count} patched files')
        elif args.command == 'export':
            count = export_sources(ROOT, args.destination)
            print(f'Exported {count} reviewed files')
        elif args.command == 'list':
            print('\n'.join(ALLOWED_FILES))
        else:
            files = collect_sources(ROOT)
            expected = inventory(files)
            target = ROOT / INVENTORY
            if args.command == 'inventory':
                temporary = target.with_suffix(target.suffix + '.new')
                with temporary.open('x', encoding='utf-8') as output:
                    output.write(expected)
                os.replace(temporary, target)
            elif target.read_text() != expected:
                raise ValueError('Source inventory is stale; run python3 minecraft.py source inventory')
            print(f'Verified {len(files)} reviewed source files')
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Source operation stopped: {error}\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
