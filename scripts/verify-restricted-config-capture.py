#!/usr/bin/python3
import base64
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("capture", Path(__file__).with_name("soul-restricted-config-capture.py"))
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


class CaptureTests(unittest.TestCase):
    def test_fixed_scope(self):
        self.assertEqual(len(capture.FILES), 7)
        self.assertEqual(len(set(capture.FILES)), 7)
        self.assertTrue(all(p.startswith("etc/") and ".." not in p for p in capture.FILES))

    def test_read_and_rejections(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root / "etc"
            folder.mkdir(mode=0o700)
            file = folder / "config"
            file.write_bytes(b"private fixture\n")
            file.chmod(0o600)
            entry = capture.read_entry(root, "etc/config", os.getuid())
            self.assertEqual(base64.b64decode(entry["content_base64"]), file.read_bytes())
            self.assertEqual(entry["mode"], 0o600)
            self.assertEqual(entry["gid"], file.stat().st_gid)
            file.chmod(0o666)
            with self.assertRaises(ValueError):
                capture.read_entry(root, "etc/config", os.getuid())
            file.chmod(0o600)
            file.write_bytes(b"x" * (capture.MAX_BYTES + 1))
            with self.assertRaises(ValueError):
                capture.read_entry(root, "etc/config", os.getuid())
            file.unlink()
            file.symlink_to("/etc/passwd")
            with self.assertRaises(OSError):
                capture.read_entry(root, "etc/config", os.getuid())
            file.unlink()
            folder.rmdir()
            folder.symlink_to("/etc")
            with self.assertRaises(OSError):
                capture.read_entry(root, "etc/passwd", os.getuid())

    def test_hash_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for path in capture.FILES:
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_bytes(b"fixture")
                file.chmod(0o600)
            entries = [capture.read_entry(root, p, os.getuid()) for p in capture.FILES]
            for entry in entries:
                entry["uid"] = 0
            document = dict(schema="soul.restricted_config_capture.v1", files=entries)
            capture.validate(document)
            entries[0]["sha256"] = "0" * 64
            with self.assertRaises(ValueError):
                capture.validate(document)


unittest.main()
