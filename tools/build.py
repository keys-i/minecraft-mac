#!/usr/bin/env python3
"""Build the native launcher, assemble its runtime app and create a local DMG"""
import hashlib
import importlib.util
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NAME = 'Minecraft for MacOS'
APP = ROOT / 'build/packaged' / f'{NAME}.app'


MACHO_MAGICS = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'}


def minimum_macos(resources):
    """Every native component must run on the advertised macOS version."""
    versions = {'15.0'}
    for path in resources.rglob('*'):
        if not path.is_file() or path.is_symlink():
            continue
        with path.open('rb') as file:
            if file.read(4) not in MACHO_MAGICS:
                continue
        commands = subprocess.check_output(['otool', '-l', str(path)], text=True)
        versions.update(re.findall(r'\bminos\s+([0-9.]+)', commands))
        versions.update(re.findall(r'LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version ([0-9.]+)', commands))
    return max(versions, key=lambda value: tuple(map(int, value.split('.'))))


def verify_source_bridge(wine, dxmt):
    if not (wine / 'dxmt-unix-bridge.json').exists():
        return None
    spec = importlib.util.spec_from_file_location('packaged_runtime', ROOT / 'src/standalone.py')
    runtime = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runtime)
    runtime.ROOT, runtime.WINE, runtime.DXMT = ROOT, wine, dxmt
    runtime.verify_unix_bridge()
    return json.loads((wine / 'dxmt-unix-bridge.json').read_text())


def record_packaged_bridge(resources, original):
    if original is None:
        return
    wine = resources / 'runtime/wine'
    metadata = dict(original)
    # Ad-hoc signing changes Mach-O bytes. Retain build provenance and record
    # the exact signed copies, including the separately signed upstream reference.
    metadata['source_files'] = original['files']
    metadata['files'] = {name: hashlib.sha256((wine / 'lib/wine/x86_64-unix' / name).read_bytes()).hexdigest()
                         for name in original['files']}
    metadata['packaged_upstream_sha256'] = hashlib.sha256(
        (resources / 'runtime/dxmt/x86_64-unix/winemetal.so').read_bytes()).hexdigest()
    (wine / 'dxmt-unix-bridge.json').write_text(json.dumps(metadata, indent=2) + '\n')


def link_graphics(resources, bridge):
    """Keep one signed copy of each graphics library inside the app bundle"""
    wine = resources / 'runtime/wine/lib/wine'
    dxmt = resources / 'runtime/dxmt'
    names = ['x86_64-windows/' + name for name in
             ('d3d11.dll', 'dxgi.dll', 'd3d10core.dll', 'winemetal.dll')]
    for name in names + ['x86_64-unix/winemetal.so']:
        source = dxmt / name
        target = wine / name
        if name == 'x86_64-unix/winemetal.so' and bridge is not None:
            target = target.with_name('winemetal-upstream.so')
        if hashlib.sha256(source.read_bytes()).digest() != hashlib.sha256(target.read_bytes()).digest():
            raise RuntimeError('The Wine graphics overlay differs from DXMT: ' + name)
        source.unlink()
        source.symlink_to(os.path.relpath(target, source.parent))


def assemble(args):
    app = args.output.absolute()
    wine = ROOT / 'runtime/standalone/wine'
    dxmt = ROOT / 'runtime/standalone/dxmt'
    helper = ROOT / 'sources/xodus/target/release/examples/standalone_helper'
    required = [wine / 'build-manifest.json', wine / 'bin/wine', wine / 'bin/wineserver',
                dxmt / 'manifest.json', helper, ROOT / 'build/packaging-env/bin/pyinstaller']
    for path in required:
        if not path.is_file():
            raise SystemExit('Complete the developer build first. Missing: ' + str(path))
    if app.exists() or app.is_symlink():
        raise SystemExit('The packaged app already exists. Move it aside before making a new package.')
    bridge = verify_source_bridge(wine, dxmt)
    launcher = build_launcher()
    subprocess.run([str(required[-1]), '--noconfirm', '--clean', '--onedir',
                    '--name', 'BedrockWorker', '--distpath', str(ROOT / 'build/frozen'),
                    '--workpath', str(ROOT / 'build/pyinstaller'), '--specpath', str(ROOT / 'build'),
                    str(ROOT / 'src/launcher/setup.py')], check=True)
    app.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(launcher, app)
    resources = app / 'Contents/Resources'
    resources.mkdir(exist_ok=True)
    shutil.copytree(ROOT / 'build/frozen/BedrockWorker', resources / 'worker', symlinks=True)
    packaged_wine = resources / 'runtime/wine'
    (packaged_wine / 'bin').mkdir(parents=True)
    for name in ('wine', 'wine64', 'wineserver', 'wine-preloader', 'wine64-preloader'):
        source = wine / 'bin' / name
        if source.exists():
            shutil.copy2(source, packaged_wine / 'bin' / name, follow_symlinks=False)
    shutil.copytree(wine / 'lib', packaged_wine / 'lib', symlinks=True,
                    ignore=shutil.ignore_patterns('*.a', '*.o', '*.def', '*.debug'))
    shutil.copytree(wine / 'share/wine', packaged_wine / 'share/wine', symlinks=True)
    shutil.copy2(wine / 'build-manifest.json', packaged_wine / 'build-manifest.json')
    # Copy only the required DXMT payload and provenance; omit old Wine backups.
    for name in ('manifest.json', 'x86_64-windows', 'x86_64-unix', 'licenses'):
        source, target = dxmt / name, resources / 'runtime/dxmt' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, target, symlinks=True)
        else:
            shutil.copy2(source, target)
    shutil.copy2(helper, resources / 'standalone_helper')
    (resources / 'scripts').mkdir()
    for name in ('standalone.py', 'standalone-setup.py', 'standalone-gameinput.py', 'winrt.reg'):
        shutil.copy2(ROOT / 'src' / name, resources / 'scripts' / name)
    if bridge is not None:
        for name in ('vendor/patches/standalone-dxmt-memory-lifetime.patch', 'tools/probes/standalone-dxmt-display-trace.c'):
            target = resources / 'scripts' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
    shutil.copytree(ROOT / 'vendor/licenses', resources / 'vendor/licenses')
    shutil.copy2(ROOT / 'vendor/README.md', resources / 'vendor/README.md')
    shutil.copy2(ROOT / 'LICENSE', resources / 'LICENSE')
    link_graphics(resources, bridge)
    # Sign nested binaries before hashing: signing modifies their bytes.
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
    record_packaged_bridge(resources, bridge)
    # A local test artifact, not a public release: retain an exact payload inventory.
    inventory = {}
    for path in resources.rglob('*'):
        if path.is_file() and not path.is_symlink():
            inventory[str(path.relative_to(resources))] = hashlib.sha256(path.read_bytes()).hexdigest()
    (resources / 'payload-sha256.json').write_text(json.dumps(inventory, indent=2) + '\n')
    info = app / 'Contents/Info.plist'
    with info.open('rb') as file:
        plist = plistlib.load(file)
    plist.pop('BedrockProjectPath', None)
    plist['LSMinimumSystemVersion'] = minimum_macos(app / 'Contents')
    with info.open('wb') as file:
        plistlib.dump(plist, file)
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    print('Minimum macOS:', plist['LSMinimumSystemVersion'])
    print(app)


def build_launcher():
    """Build the native development app without touching the installed game"""
    app = ROOT / 'build' / f'{NAME}.app'
    resources = app / 'Contents/Resources'
    executable = app / 'Contents/MacOS/BedrockLauncher'
    cache = ROOT / 'build/swift-module-cache'
    executable.parent.mkdir(parents=True, exist_ok=True)
    resources.mkdir(parents=True, exist_ok=True)
    for name in ('overworld.jpg', 'nether.jpg', 'end.jpg', 'sift.jpg'):
        (resources / name).unlink(missing_ok=True)
    shutil.copy2(ROOT / 'assets/poster.webp', resources / 'poster.webp')
    cache.mkdir(parents=True, exist_ok=True)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-O', '-target',
                    'arm64-apple-macos15.0', '-module-cache-path', str(cache),
                    str(ROOT / 'src/launcher/BedrockLauncher.swift'), str(ROOT / 'src/launcher/Adventure.swift'),
                    str(ROOT / 'src/launcher/Landscape.swift'), str(ROOT / 'src/launcher/Assets.swift'), str(ROOT / 'src/launcher/NBT.swift'),
                    str(ROOT / 'src/launcher/Biome.swift'), str(ROOT / 'src/launcher/Mobs.swift'), str(ROOT / 'src/launcher/Structures.swift'), str(ROOT / 'src/launcher/Journey.swift'), '-o', str(executable)], check=True)
    icon = ROOT / 'build/make-icon'
    iconset = ROOT / 'build/AppIcon.iconset'
    subprocess.run(['xcrun', 'swiftc', '-O', '-module-cache-path', str(cache),
                    str(ROOT / 'src/launcher/Icon.swift'), '-o', str(icon)], check=True)
    subprocess.run([str(icon), str(iconset)], check=True)
    subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(resources / 'AppIcon.icns')], check=True)
    with (app / 'Contents/Info.plist').open('wb') as output:
        plistlib.dump(dict(CFBundleExecutable='BedrockLauncher', CFBundleIdentifier='local.bedrock.mac.launcher',
            CFBundleName=NAME, CFBundleDisplayName=NAME,
            CFBundlePackageType='APPL', CFBundleIconFile='AppIcon', CFBundleVersion='6', CFBundleShortVersionString='0.6.0',
            LSMinimumSystemVersion='15.0', NSHighResolutionCapable=True, BedrockProjectPath=str(ROOT)), output)
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    print('Built', app)
    return app


def preview(args):
    """Build the real interface with an isolated, simulated setup worker"""
    app = args.output.absolute()
    if app.exists() or app.is_symlink():
        raise SystemExit('The preview already exists; choose a new --output path.')
    launcher = build_launcher()
    if (launcher / 'Contents/Resources/worker').exists():
        raise RuntimeError('The development launcher unexpectedly contains a real worker')
    shutil.copytree(launcher, app)
    fixture = app / 'Contents/Resources/preview'
    (fixture / 'src/launcher').mkdir(parents=True)
    (fixture / 'logs/standalone').mkdir(parents=True)
    shutil.copy2(ROOT / 'tests/preview.py', fixture / 'src/launcher/setup.py')
    info = app / 'Contents/Info.plist'
    with info.open('rb') as file:
        values = plistlib.load(file)
    identity = hashlib.sha256(os.fsencode(app)).hexdigest()[:12]
    values.update(CFBundleIdentifier='local.minecraft.preview.' + identity,
                  CFBundleName=NAME + ' Preview', CFBundleDisplayName=NAME + ' Preview',
                  BedrockProjectPath=str(fixture))
    with info.open('wb') as file:
        plistlib.dump(values, file)
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    print(app)
    print('Interface preview only; sign-in, download and gameplay are simulated.')


def disk_image(args):
    app, output = args.app.resolve(), args.output.absolute()
    if not (app / 'Contents/Info.plist').is_file():
        raise ValueError('Build the packaged app first.')
    if output.exists() or output.is_symlink():
        raise ValueError('Output already exists; choose a new --output path.')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='bedrock-dmg-', dir=output.parent) as temporary:
        stage = Path(temporary) / 'Install'
        stage.mkdir()
        # Include the app alone so adjacent private build files stay local
        shutil.copytree(app, stage / app.name, symlinks=True)
        (stage / 'Applications').symlink_to('/Applications', target_is_directory=True)
        subprocess.run(['hdiutil', 'create', '-srcfolder', str(stage), '-volname',
                        NAME, '-format', 'ULFO', '-ov', str(output)], check=True)
    subprocess.run(['hdiutil', 'verify', str(output)], check=True)
    print(output)
    print('Local test image. Developer ID signing and notarization are separate release steps.')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('launcher', help='Build the native development launcher')
    demo = commands.add_parser('preview', help='Build an isolated interface preview with simulated setup')
    demo.add_argument('--output', type=Path, default=ROOT / 'build/preview' / f'{NAME} Preview.app')
    app = commands.add_parser('app', help='Assemble the app with the prebuilt runtime')
    app.add_argument('--output', type=Path, default=APP)
    dmg = commands.add_parser('dmg', help='Create a verified drag-to-Applications DMG')
    dmg.add_argument('--app', type=Path, default=APP)
    dmg.add_argument('--output', type=Path, default=ROOT / 'build/Minecraft-for-MacOS-preview.dmg')
    args = parser.parse_args(argv)
    if args.command == 'launcher':
        build_launcher()
    elif args.command == 'preview':
        preview(args)
    elif args.command == 'app':
        assemble(args)
    else:
        try:
            disk_image(args)
        except ValueError as error:
            parser.error(str(error))


if __name__ == '__main__':
    main()
