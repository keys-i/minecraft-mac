"""Release boundaries: private directories, link escapes, and destructive exports."""

import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("export_source", Path(__file__).resolve().parents[1] / "tools/source.py")
export = importlib.util.module_from_spec(spec)
spec.loader.exec_module(export)


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.source = self.base / "source"
        self.source.mkdir()
        (self.source / "README.md").write_text("Reviewed source\n")
        self.destination = self.base / "export"

    def test_private_files_never_enter_export(self):
        for directory in export.PRIVATE_ROOTS:
            private = self.source / directory
            private.mkdir()
            (private / "private-data").write_text("must not leave this machine")
        count = export.export_sources(self.source, self.destination, ("README.md",))
        self.assertEqual(count, 1)
        self.assertEqual({p.relative_to(self.destination).as_posix() for p in self.destination.rglob('*') if p.is_file()},
                         {"README.md", "tools/SOURCE-SHA256.txt"})
        digest = hashlib.sha256(b"Reviewed source\n").hexdigest()
        self.assertEqual((self.destination / "tools/SOURCE-SHA256.txt").read_text(), f"{digest}  README.md\n")

    def test_symlink_leaf_is_rejected(self):
        private = self.base / "private"
        private.write_text("private")
        (self.source / "source.py").symlink_to(private)
        with self.assertRaisesRegex(ValueError, "symlink"):
            export.export_sources(self.source, self.destination, ("source.py",))
        self.assertFalse(self.destination.exists())

    def test_symlink_parent_is_rejected(self):
        private = self.base / "private"
        private.mkdir()
        (private / "note.md").write_text("private")
        (self.source / "docs").symlink_to(private, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            export.export_sources(self.source, self.destination, ("docs/note.md",))

    def test_symlink_within_source_is_also_rejected(self):
        (self.source / "copy.md").symlink_to("README.md")
        with self.assertRaisesRegex(ValueError, "symlink"):
            export.collect_sources(self.source, ("copy.md",))

    def test_unsafe_allowlist_paths_are_rejected(self):
        entries = ("../private", "/private", "docs/../../private", "./README.md", "docs//file", "runtime/helper-session.json", "logs/private.log", "game/Minecraft.Windows.exe", "bottles/world", "sources/xodus/LICENSE")
        for path in entries:
            with self.subTest(path=path), self.assertRaises(ValueError):
                export.collect_sources(self.source, (path,))

    def test_existing_destination_is_never_changed(self):
        self.destination.mkdir()
        existing = self.destination / "user-file"
        existing.write_text("keep")
        with self.assertRaisesRegex(ValueError, "already exists"):
            export.export_sources(self.source, self.destination, ("README.md",))
        self.assertEqual(existing.read_text(), "keep")

    def test_symlink_destination_is_never_followed(self):
        self.destination.symlink_to(self.base / "absent")
        with self.assertRaisesRegex(ValueError, "already exists"):
            export.export_sources(self.source, self.destination, ("README.md",))
        self.assertFalse((self.base / "absent").exists())

    def test_missing_source_leaves_no_partial_export(self):
        with self.assertRaises(ValueError):
            export.export_sources(self.source, self.destination, ("README.md", "missing.py"))
        self.assertFalse(self.destination.exists())
        self.assertEqual(list(self.base.glob(".bedrock-source-*")), [])

    def test_binary_replacement_is_rejected(self):
        (self.source / "README.md").write_bytes(b"MZ\0binary")
        with self.assertRaisesRegex(ValueError, "binary"):
            export.collect_sources(self.source, ("README.md",))

    def test_executable_permissions_survive(self):
        script = self.source / "launcher.sh"
        script.write_text("#!/bin/sh\nexit 0\n")
        script.chmod(0o755)
        export.export_sources(self.source, self.destination, ("launcher.sh",))
        self.assertEqual((self.destination / "launcher.sh").stat().st_mode & 0o777, 0o755)

    def test_reviewed_readme_images_survive_source_export(self):
        repository = Path(__file__).resolve().parents[1]
        for name in ("assets/poster.webp", "assets/launcher.jpg"):
            with self.subTest(name=name):
                target = self.source / name
                target.parent.mkdir(exist_ok=True)
                target.write_bytes((repository / name).read_bytes())
                destination = self.base / target.stem
                export.export_sources(self.source, destination, (name,))
                self.assertEqual((destination / name).read_bytes(), target.read_bytes())

    def test_binary_payload_cannot_masquerade_as_a_readme_image(self):
        for name in ("assets/poster.webp", "assets/launcher.jpg"):
            with self.subTest(name=name):
                target = self.source / name
                target.parent.mkdir(exist_ok=True)
                target.write_bytes(b"MZ\0executable")
                with self.assertRaisesRegex(ValueError, "image format"):
                    export.export_sources(self.source, self.destination, (name,))
                self.assertFalse(self.destination.exists())

    def test_readme_images_are_bounded_before_reading(self):
        target = self.source / "assets/poster.webp"
        target.parent.mkdir()
        target.write_bytes(b"\0" * (2 * 1024 * 1024 + 1))
        with self.assertRaisesRegex(ValueError, "exceeds 2 MiB"):
            export.export_sources(self.source, self.destination, ("assets/poster.webp",))
        self.assertFalse(self.destination.exists())

    def test_real_allowlist_has_no_private_entries_or_duplicates(self):
        self.assertEqual(len(export.ALLOWED_FILES), len(set(export.ALLOWED_FILES)))
        for name in export.ALLOWED_FILES:
            export.checked_relative(name)


if __name__ == "__main__":
    unittest.main()
