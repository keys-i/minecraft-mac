"""Verify the advertised OS target includes every bundled native component."""
import importlib.util
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('packager', Path(__file__).resolve().parents[1] / 'tools/build.py')
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class PackagingTests(unittest.TestCase):
    def test_launcher_bundles_only_poster_fallback_and_keeps_installation_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            resources = root / 'build/Minecraft for MacOS.app/Contents/Resources'
            resources.mkdir(parents=True)
            (root / 'assets').mkdir()
            (root / 'assets/poster.webp').write_bytes(b'approved poster')
            (resources / 'overworld.jpg').write_bytes(b'retired panorama')
            with patch.object(packager, 'ROOT', root), \
                    patch.object(packager.subprocess, 'run'), \
                    contextlib.redirect_stdout(io.StringIO()):
                app = packager.build_launcher()
            self.assertEqual(app.name, 'Minecraft for MacOS.app')
            self.assertEqual((resources / 'poster.webp').read_bytes(), b'approved poster')
            for name in ('overworld.jpg', 'nether.jpg', 'end.jpg', 'sift.jpg'):
                self.assertFalse((app / 'Contents/Resources' / name).exists())
            with (app / 'Contents/Info.plist').open('rb') as file:
                info = plistlib.load(file)
            self.assertEqual(info['CFBundleDisplayName'], 'Minecraft for MacOS')
            self.assertEqual(info['CFBundleIdentifier'], 'local.bedrock.mac.launcher')
            self.assertEqual(info['BedrockProjectPath'], str(root))

    def test_preview_has_its_own_identity_and_simulated_worker(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            launcher = root / 'launcher.app'
            (launcher / 'Contents/Resources').mkdir(parents=True)
            with (launcher / 'Contents/Info.plist').open('wb') as file:
                plistlib.dump({'CFBundleIdentifier': 'local.bedrock.mac.launcher'}, file)
            output = root / 'Preview.app'
            with patch.object(packager, 'build_launcher', return_value=launcher), \
                    patch.object(packager.subprocess, 'run'), \
                    contextlib.redirect_stdout(io.StringIO()):
                packager.main(['preview', '--output', str(output)])
            with (output / 'Contents/Info.plist').open('rb') as file:
                info = plistlib.load(file)
            self.assertTrue(info['CFBundleIdentifier'].startswith('local.minecraft.preview.'))
            fixture = Path(info['BedrockProjectPath'])
            self.assertTrue(fixture.is_relative_to(output))
            worker = fixture / 'src/launcher/setup.py'
            self.assertEqual(worker.read_bytes(), (packager.ROOT / 'tests/preview.py').read_bytes())
            result = subprocess.check_output([sys.executable, str(worker), '--status'], text=True)
            self.assertEqual(json.loads(result)['state'], 'new')
            self.assertFalse((output / 'Contents/Resources/worker').exists())
            process = subprocess.Popen([sys.executable, str(worker)], stdout=subprocess.PIPE, text=True)
            try:
                self.assertEqual(json.loads(process.stdout.readline())['state'], 'busy')
                process.terminate()
                output, _ = process.communicate(timeout=3)
                self.assertEqual(json.loads(output.splitlines()[-1])['state'], 'cancelled')
                self.assertEqual(process.returncode, 0)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                process.stdout.close()

    def test_dmg_stages_only_the_app_and_removes_temporary_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root / 'Example.app'
            (app / 'Contents').mkdir(parents=True)
            (app / 'Contents/Info.plist').write_bytes(b'fixture')
            (root / 'private.txt').write_text('must not be packaged')
            output = root / 'result.dmg'
            stages = []

            def native(command, **kwargs):
                if command[:2] == ['hdiutil', 'create']:
                    stage = Path(command[command.index('-srcfolder') + 1])
                    stages.append(stage)
                    self.assertEqual({entry.name for entry in stage.iterdir()}, {'Example.app', 'Applications'})
                    self.assertEqual((stage / 'Applications').readlink(), Path('/Applications'))
                    self.assertEqual((stage / 'Example.app/Contents/Info.plist').read_bytes(), b'fixture')
                    output.write_bytes(b'disk image')

            with patch.object(packager.subprocess, 'run', side_effect=native) as run, \
                    contextlib.redirect_stdout(io.StringIO()):
                packager.main(['dmg', '--app', str(app), '--output', str(output)])
            self.assertEqual(len(stages), 1)
            self.assertFalse(stages[0].parent.exists())
            self.assertEqual(run.call_args.args[0], ['hdiutil', 'verify', str(output)])

    def test_dmg_rejects_missing_app_and_existing_output_before_native_tools(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root / 'Example.app'
            output = root / 'existing.dmg'
            output.write_bytes(b'keep existing image')
            for exists in (False, True):
                with self.subTest(app_exists=exists):
                    if exists:
                        (app / 'Contents').mkdir(parents=True)
                        (app / 'Contents/Info.plist').write_bytes(b'fixture')
                    with patch.object(packager.subprocess, 'run') as run, \
                            contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                        packager.main(['dmg', '--app', str(app), '--output', str(output)])
                    self.assertEqual(error.exception.code, 2)
                    run.assert_not_called()
                    self.assertEqual(output.read_bytes(), b'keep existing image')

    def test_graphics_links_stay_inside_a_movable_bundle(self):
        for bridge in (None, {'version': 'v0.80'}):
            with self.subTest(bridge=bridge), tempfile.TemporaryDirectory() as temporary:
                resources = Path(temporary) / 'original/Contents/Resources'
                wine = resources / 'runtime/wine/lib/wine'
                dxmt = resources / 'runtime/dxmt'
                names = ['x86_64-windows/' + name for name in
                         ('d3d11.dll', 'dxgi.dll', 'd3d10core.dll', 'winemetal.dll')]
                for name in names + ['x86_64-unix/winemetal.so']:
                    target = wine / name
                    if name.endswith('.so') and bridge is not None:
                        target = target.with_name('winemetal-upstream.so')
                    source = dxmt / name
                    for path in (source, target):
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_bytes(name.encode())
                packager.link_graphics(resources, bridge)
                moved = Path(temporary) / 'moved'
                resources.parents[1].rename(moved)
                for name in names + ['x86_64-unix/winemetal.so']:
                    path = moved / 'Contents/Resources/runtime/dxmt' / name
                    self.assertTrue(path.is_symlink())
                    self.assertTrue(path.resolve().is_relative_to(moved.resolve()))
                    self.assertEqual(path.read_bytes(), name.encode())

    def test_graphics_mismatch_preserves_the_reference(self):
        with tempfile.TemporaryDirectory() as temporary:
            resources = Path(temporary)
            for name, data in [('wine/lib/wine', b'wrong overlay'), ('dxmt', b'original')]:
                path = resources / 'runtime' / name / 'x86_64-windows/d3d11.dll'
                path.parent.mkdir(parents=True)
                path.write_bytes(data)
            with self.assertRaisesRegex(RuntimeError, 'overlay differs'):
                packager.link_graphics(resources, None)
            self.assertEqual((resources / 'runtime/dxmt/x86_64-windows/d3d11.dll').read_bytes(), b'original')

    def test_signed_bridge_retains_provenance_and_checks_packaged_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            wine, dxmt = root / 'wine', root / 'dxmt'
            libraries = wine / 'lib/wine/x86_64-unix'
            libraries.mkdir(parents=True)
            (dxmt / 'x86_64-unix').mkdir(parents=True)
            for name, data in [('winemetal.so', b'bridge'), ('winemetal-upstream.so', b'upstream')]:
                (libraries / name).write_bytes(data)
            (dxmt / 'x86_64-unix/winemetal.so').write_bytes(b'upstream')
            digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
            metadata = {
                'version': 'v0.80',
                'source_commit': '589adb780354b461645b29999cefaf533594ee99',
                'files': {name: digest(libraries / name) for name in ('winemetal.so', 'winemetal-upstream.so')},
                'patch_sha256': digest(packager.ROOT / 'vendor/patches/standalone-dxmt-memory-lifetime.patch'),
                'trace_source_sha256': digest(packager.ROOT / 'tools/probes/standalone-dxmt-display-trace.c'),
            }
            (wine / 'dxmt-unix-bridge.json').write_text(json.dumps(metadata))
            with patch.dict(os.environ, {}, clear=True):
                self.assertEqual(packager.verify_source_bridge(wine, dxmt), metadata)
            resources = root / 'app/Contents/Resources'
            shutil.copytree(wine, resources / 'runtime/wine')
            shutil.copytree(dxmt, resources / 'runtime/dxmt')
            for name in ('vendor/patches/standalone-dxmt-memory-lifetime.patch', 'tools/probes/standalone-dxmt-display-trace.c'):
                target = resources / 'scripts' / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(packager.ROOT / name, target)
            packaged_libs = resources / 'runtime/wine/lib/wine/x86_64-unix'
            for name in metadata['files']:
                (packaged_libs / name).write_bytes(('signed ' + name).encode())
            (resources / 'runtime/dxmt/x86_64-unix/winemetal.so').write_bytes(b'signed upstream reference')
            packager.record_packaged_bridge(resources, metadata)
            recorded = json.loads((resources / 'runtime/wine/dxmt-unix-bridge.json').read_text())
            self.assertEqual(recorded['source_files'], metadata['files'])
            spec = importlib.util.spec_from_file_location('bridge_runtime', packager.ROOT / 'src/standalone.py')
            runtime = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(runtime)
            runtime.ROOT = root / 'player-data-without-sources'
            runtime.WINE = resources / 'runtime/wine'
            runtime.DXMT = resources / 'runtime/dxmt'
            with patch.dict(os.environ, {'BEDROCK_BUNDLE': str(resources)}):
                runtime.verify_unix_bridge()
                (packaged_libs / 'winemetal.so').write_bytes(b'changed after signing')
                with self.assertRaises(RuntimeError):
                    runtime.verify_unix_bridge()

    def test_runtime_dependency_can_raise_minimum_above_python(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ('Python', 'wine'):
                (root / name).write_bytes(b'\xcf\xfa\xed\xfe')
            (root / 'plain.txt').write_text('not a binary')
            def commands(command, **kwargs):
                return 'LC_BUILD_VERSION\n minos ' + ('11.0' if Path(command[-1]).name == 'Python' else '26.0')
            with patch.object(packager.subprocess, 'check_output', side_effect=commands) as read:
                self.assertEqual(packager.minimum_macos(root), '26.0')
            self.assertEqual(read.call_count, 2)

    def test_legacy_load_command_is_included(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'library').write_bytes(b'\xcf\xfa\xed\xfe')
            with patch.object(packager.subprocess, 'check_output', return_value='cmd LC_VERSION_MIN_MACOSX\ncmdsize 16\nversion 16.0\nsdk 26.0'):
                self.assertEqual(packager.minimum_macos(root), '16.0')
