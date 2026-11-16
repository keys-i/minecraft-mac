"""Transaction tests run without Wine, a GPU, or downloaded artifacts."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('dxmt_unix', Path(__file__).resolve().parent.parent / 'tools/graphics.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)
runtime_spec = importlib.util.spec_from_file_location('bridge_runtime', Path(__file__).resolve().parent.parent / 'src/standalone.py')
runtime = importlib.util.module_from_spec(runtime_spec)
runtime_spec.loader.exec_module(runtime)


class StageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.output = self.root / 'output'; self.output.mkdir()
        self.runtime = self.root / 'wine'; (self.runtime / 'bin').mkdir(parents=True)
        (self.runtime / 'bin/wine').write_bytes(b'wine fixture')
        self.lib = self.runtime / 'lib/wine/x86_64-unix'; self.lib.mkdir(parents=True)
        (self.output / 'winemetal.so').write_bytes(b'new bridge')
        (self.output / 'winemetal-upstream.so').write_bytes(b'original library')
        (self.lib / 'winemetal.so').write_bytes(b'original library')
        self.upstream_sha = hashlib.sha256(b'original library').hexdigest()
        self.metadata = {'files': {name: bridge.digest(self.output / name) for name in bridge.FILES}}
        for patch in (mock.patch.object(bridge, 'OUTPUT', self.output),
                      mock.patch.object(bridge, 'UPSTREAM_SHA', self.upstream_sha),
                      mock.patch.object(bridge, 'verified_output', return_value=self.metadata),
                      mock.patch.object(bridge, 'refuse_mapped')):
            patch.start(); self.addCleanup(patch.stop)

    def test_stage_preserves_original(self):
        bridge.stage(self.runtime)
        metadata = json.loads((self.runtime / 'dxmt-unix-bridge.json').read_text())
        self.assertEqual((self.runtime / metadata['original_backup']).read_bytes(), b'original library')
        for name in bridge.FILES:
            self.assertEqual(bridge.digest(self.lib / name), metadata['files'][name])

    def test_failed_manifest_commit_restores_missing_files(self):
        replace = bridge.os.replace
        def fail_manifest(source, target):
            if Path(target).name == 'dxmt-unix-bridge.json': raise OSError('injected commit failure')
            return replace(source, target)
        with mock.patch.object(bridge.os, 'replace', side_effect=fail_manifest):
            with self.assertRaisesRegex(OSError, 'injected'):
                bridge.stage(self.runtime)
        self.assertEqual((self.lib / 'winemetal.so').read_bytes(), b'original library')
        self.assertFalse((self.lib / 'winemetal-upstream.so').exists())
        self.assertFalse((self.runtime / 'dxmt-unix-bridge.json').exists())
        self.assertFalse(list(self.runtime.glob('.dxmt-stage-*')))

    def test_failed_post_install_check_restores_previous_pair_and_manifest(self):
        (self.lib / 'winemetal.so').write_bytes(b'old bridge')
        (self.lib / 'winemetal-upstream.so').write_bytes(b'original library')
        manifest = self.runtime / 'dxmt-unix-bridge.json'
        previous = json.dumps({'files': {'winemetal.so': bridge.digest(self.lib / 'winemetal.so')}})
        manifest.write_text(previous)
        digest = bridge.digest
        def fail_installed(path):
            if Path(path).resolve() == (self.lib / 'winemetal.so').resolve() and Path(path).read_bytes() == b'new bridge':
                return 'injected mismatch'
            return digest(path)
        with mock.patch.object(bridge, 'digest', side_effect=fail_installed):
            with self.assertRaisesRegex(RuntimeError, 'Installed artifact'):
                bridge.stage(self.runtime)
        self.assertEqual((self.lib / 'winemetal.so').read_bytes(), b'old bridge')
        self.assertEqual((self.lib / 'winemetal-upstream.so').read_bytes(), b'original library')
        self.assertEqual(manifest.read_text(), previous)

    def test_mapped_target_is_rejected_before_writes(self):
        bridge.refuse_mapped.side_effect = RuntimeError('mapped target')
        with self.assertRaisesRegex(RuntimeError, 'mapped target'):
            bridge.stage(self.runtime)
        self.assertEqual((self.lib / 'winemetal.so').read_bytes(), b'original library')
        self.assertFalse((self.runtime / 'dxmt-unix-bridge-backups').exists())


class VerificationTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)
        self.wine, self.dxmt = self.root / 'wine', self.root / 'dxmt'
        libraries = self.wine / 'lib/wine/x86_64-unix'
        for path, data in ((libraries / 'winemetal.so', b'bridge'),
                           (libraries / 'winemetal-upstream.so', b'upstream'),
                           (self.dxmt / 'x86_64-unix/winemetal.so', b'upstream')):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        self.handoff = self.root / 'vendor/patches/standalone-dxmt-handoff.patch'
        self.metadata = {
            'version': 'v0.80', 'source_commit': bridge.COMMIT,
            'files': {name: bridge.digest(libraries / name) for name in bridge.FILES},
        }
        for field, name in (
            ('patch_sha256', 'vendor/patches/standalone-dxmt-memory-lifetime.patch'),
            ('handoff_patch_sha256', 'vendor/patches/standalone-dxmt-handoff.patch'),
            ('trace_source_sha256', 'tools/probes/standalone-dxmt-display-trace.c'),
        ):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name)
            self.metadata[field] = bridge.digest(path)
        for patch in (mock.patch.object(runtime, 'ROOT', self.root),
                      mock.patch.object(runtime, 'WINE', self.wine),
                      mock.patch.object(runtime, 'DXMT', self.dxmt),
                      mock.patch.dict(os.environ, {}, clear=True)):
            patch.start()
            self.addCleanup(patch.stop)

    def verify(self):
        (self.wine / 'dxmt-unix-bridge.json').write_text(json.dumps(self.metadata))
        runtime.verify_unix_bridge()

    def test_recorded_handoff_patch_is_required_and_verified(self):
        self.verify()
        self.handoff.write_text('altered patch')
        with self.assertRaises(RuntimeError) as failure:
            self.verify()
        self.assertIn('handoff patch changed', str(failure.exception.__cause__))
        self.handoff.unlink()
        with self.assertRaises(RuntimeError):
            self.verify()

    def test_older_metadata_needs_no_handoff_patch(self):
        del self.metadata['handoff_patch_sha256']
        self.handoff.unlink()
        self.verify()


@unittest.skipUnless(sys.platform == 'darwin', 'Native Cocoa/Metal handoff checks')
class HandoffTests(unittest.TestCase):
    def test_rendered_frame_validation_and_cleanup(self):
        root = Path(__file__).resolve().parent.parent
        lines = (root / 'vendor/patches/standalone-dxmt-handoff.patch').read_text().splitlines()
        start = lines.index('+static struct {')
        helper = []
        for line in lines[start:]:
            if not line.startswith('+'):
                break
            helper.append(line[1:])
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            (folder / 'handoff.inc').write_text('\n'.join(helper) + '\n')
            executable = folder / 'handoff'
            compiled = subprocess.run([
                '/usr/bin/clang', '-std=gnu2x', '-fno-objc-arc', '-O2', '-Wall', '-Wextra',
                '-Wno-unused-parameter', '-I', str(folder), str(root / 'tests/handoff.m'),
                '-framework', 'Cocoa', '-framework', 'QuartzCore', '-framework', 'Metal',
                '-o', str(executable),
            ], capture_output=True, text=True, timeout=30)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            for scenario in ('absent', 'invalid-token', 'valid', 'tiny-view', 'tiny-window',
                             'child-window', 'invalid-frame', 'trailing-frame', 'offscreen',
                             'huge-frame', 'long-frame', 'fullscreen', 'register-failure',
                             'publish-retry', 'publish-terminal', 'post-retry', 'order-retry',
                             'order-terminal', 'recreated'):
                with self.subTest(scenario=scenario):
                    result = subprocess.run([str(executable), scenario], capture_output=True,
                                            text=True, timeout=5)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
