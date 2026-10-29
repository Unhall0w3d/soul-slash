#!/usr/bin/env python3
"""Deterministic tests; never call the real GPU."""

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SOURCE = Path(__file__).with_name("log-nvidia-clients.py")
spec = importlib.util.spec_from_file_location("client_logger", SOURCE)
logger = importlib.util.module_from_spec(spec)
spec.loader.exec_module(logger)


def xml(pci="0000:05:00.0", processes=""):
    return (f"<nvidia_smi_log><gpu><pci><pci_bus_id>{pci}</pci_bus_id></pci>"
            f"<processes>{processes}</processes></gpu></nvidia_smi_log>").encode()


def process(pid=42, kind="G", memory="12 MiB", name="secret/document.txt"):
    return (f"<process_info><pid>{pid}</pid><type>{kind}</type>"
            f"<used_memory>{memory}</used_memory><process_name>{name}</process_name>"
            "</process_info>")


class Clock:
    def __init__(self):
        self.value = 0

    def now(self):
        return self.value

    def sleep(self, seconds):
        self.value += seconds


class LoggerTests(unittest.TestCase):
    def test_target_filter_type_and_privacy(self):
        fixture = xml("0000:06:00.0", process()) + b""  # wrong GPU must fail
        with self.assertRaisesRegex(logger.CaptureError, "target_gpu_unavailable"):
            logger.parse_clients(fixture)
        for pci in ("0000:05:00.0", "00000000:05:00.0"):
            self.assertEqual(len(logger.parse_clients(xml(pci, process()),
                                                      starttime=lambda _pid: 99,
                                                      executable=lambda _pid: "app")), 1)
        for pci in ("0001:05:00.0", "00000001:05:00.0", "000000000:05:00.0",
                    "00000000:06:00.0"):
            with self.assertRaisesRegex(logger.CaptureError, "target_gpu_unavailable"):
                logger.parse_clients(xml(pci, process()))
        clients = logger.parse_clients(xml(processes=process(kind="C+G", memory="[Not Supported]")),
                                       starttime=lambda _pid: 99,
                                       executable=lambda _pid: "blender")
        record = next(iter(clients.values()))
        self.assertEqual(record["type"], "both")
        self.assertIsNone(record["memory_mib"])
        self.assertEqual(record["executable"], "blender")
        self.assertNotIn("secret", json.dumps(record))
        self.assertEqual(logger.client_type("?"), "unknown")
        self.assertEqual(logger.client_type("G"), "graphics")
        self.assertEqual(logger.client_type("C"), "compute")
        self.assertEqual(logger.memory_mib("123 MiB"), 123)

    def test_initial_type_change_pid_reuse_and_disappearance(self):
        first = logger.parse_clients(xml(processes=process()), lambda _pid: 10,
                                     lambda _pid: "app")
        second = logger.parse_clients(xml(processes=process(kind="C")), lambda _pid: 10,
                                      lambda _pid: "app")
        reused = logger.parse_clients(xml(processes=process()), lambda _pid: 11,
                                      lambda _pid: "other")
        self.assertEqual([r["event"] for r in logger.changes({}, first, initial=True)], ["initial"])
        self.assertEqual([r["event"] for r in logger.changes(first, second)], ["type_changed"])
        self.assertEqual([r["event"] for r in logger.changes(second, reused)],
                         ["disappeared", "appeared"])
        self.assertEqual([r["event"] for r in logger.changes(reused, {})], ["disappeared"])

    def test_directory_safety_and_size(self):
        with tempfile.TemporaryDirectory() as base:
            root = Path(base)
            existing = root / "existing"
            existing.mkdir()
            with self.assertRaises(FileExistsError):
                logger.Journal(str(existing))
            link = root / "link"
            link.symlink_to(existing, target_is_directory=True)
            with self.assertRaises(ValueError):
                logger.Journal(str(link / "new"))
            with self.assertRaises(ValueError):
                logger.Journal("relative")
            with mock.patch.object(logger, "MAX_BYTES", logger.RECEIPT_RESERVE + 100):
                journal = logger.Journal(str(root / "capture"))
                try:
                    self.assertFalse(journal.write({"event": "x", "data": "a" * 1000}))
                    self.assertTrue(journal.write({"event": "finished", "reason": "size_limit"},
                                                  receipt=True))
                finally:
                    journal.close()
            self.assertEqual((root / "capture").stat().st_mode & 0o777, 0o700)
            self.assertEqual((root / "capture" / "clients.jsonl").stat().st_mode & 0o777, 0o600)

    def test_deadline_and_errors_have_final_receipts(self):
        with tempfile.TemporaryDirectory() as base:
            root = Path(base)
            args = type("Args", (), {"output_dir": str(root / "ok"),
                                     "duration_seconds": 2, "interval_seconds": 1})()
            clock = Clock()
            observed_timeouts = []
            def sample_ok(timeout):
                observed_timeouts.append(timeout)
                return xml()
            self.assertEqual(logger.run(args, sample=sample_ok, now=clock.now,
                                        sleep=clock.sleep), 0)
            records = [json.loads(line) for line in (root / "ok" / "clients.jsonl").read_text().splitlines()]
            self.assertEqual([r["event"] for r in records], ["started", "finished"])
            self.assertEqual(records[-1]["samples"], 2)
            self.assertEqual(records[-1]["reason"], "deadline")
            self.assertEqual(observed_timeouts, [2, 1])
            self.assertGreater(records[0]["logger_pid"], 0)
            args.output_dir = str(root / "errors")
            clock = Clock()
            def fail(timeout):
                raise logger.CaptureError("command_failed")
            self.assertEqual(logger.run(args, sample=fail, now=clock.now,
                                        sleep=clock.sleep), 0)  # deadline before 3rd failure
            args.output_dir = str(root / "three-errors")
            args.duration_seconds = 5
            clock = Clock()
            self.assertEqual(logger.run(args, sample=fail, now=clock.now,
                                        sleep=clock.sleep), 1)
            records = [json.loads(line) for line in (root / "three-errors" / "clients.jsonl").read_text().splitlines()]
            self.assertEqual(records[-1]["reason"], "sample_errors")
            self.assertEqual(len([r for r in records if r["event"] == "sample_error"]), 3)

    def test_unexpected_failures_do_not_claim_deadline(self):
        with tempfile.TemporaryDirectory() as base:
            args = type("Args", (), {"output_dir": str(Path(base) / "io"),
                                     "duration_seconds": 2, "interval_seconds": 1})()
            def io_error(timeout):
                raise OSError("private driver detail")
            self.assertEqual(logger.run(args, sample=io_error), 1)
            records = [json.loads(line) for line in (Path(args.output_dir) / "clients.jsonl").read_text().splitlines()]
            self.assertEqual(records[-1]["reason"], "io_error")
            self.assertNotIn("private driver detail", json.dumps(records))
            args.output_dir = str(Path(base) / "runtime")
            def runtime_error(timeout):
                raise RuntimeError("private detail")
            self.assertEqual(logger.run(args, sample=runtime_error), 1)
            records = [json.loads(line) for line in (Path(args.output_dir) / "clients.jsonl").read_text().splitlines()]
            self.assertEqual(records[-1]["reason"], "runtime_error")
            self.assertNotIn("private detail", json.dumps(records))

    def test_command_timeout_reaps_child(self):
        original = subprocess.Popen
        children = []
        def fake_popen(_command, **kwargs):
            child = original([sys.executable, "-c", "import time; time.sleep(5)"], **kwargs)
            children.append(child)
            return child
        with mock.patch.object(logger.subprocess, "Popen", fake_popen):
            with self.assertRaisesRegex(logger.CaptureError, "command_timeout"):
                logger.nvidia_xml(timeout=0.05)
        self.assertEqual(len(children), 1)
        self.assertIsNotNone(children[0].poll())

    def test_cli_limits(self):
        with self.assertRaises(SystemExit):
            logger.main(["--output-dir", "/tmp/unused", "--duration-seconds", "172801"])
        with self.assertRaises(SystemExit):
            logger.main(["--output-dir", "/tmp/unused", "--interval-seconds", "0"])


if __name__ == "__main__":
    unittest.main()
