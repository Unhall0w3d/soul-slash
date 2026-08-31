#!/usr/bin/env python3
"""User-manager-scoped metadata-only desktop notification observer."""

from __future__ import annotations

import argparse
import hashlib
import signal
import subprocess
import sys
import time
from pathlib import Path

from soul_voice_notification_observer import NotificationMonitorParser


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--ruby", required=True)
    parser.add_argument("--cli", required=True)
    args = parser.parse_args()
    root = Path(args.project_root).resolve(strict=True)
    cli = Path(args.cli).resolve(strict=True)
    ruby = Path(args.ruby).resolve(strict=True)
    if root not in cli.parents or cli.is_symlink() or not cli.is_file():
        raise SystemExit("notification CLI boundary is invalid")
    if ruby.is_symlink() or not ruby.is_file():
        raise SystemExit("Ruby runtime boundary is invalid")

    monitor = subprocess.Popen(
        ["dbus-monitor", "--session", "type='method_call',interface='org.freedesktop.Notifications',member='Notify'"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace",
    )
    stopping = False

    def stop(_signum, _frame):
        nonlocal stopping
        stopping = True
        monitor.terminate()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    notification_parser = NotificationMonitorParser()
    try:
        assert monitor.stdout is not None
        for line in monitor.stdout:
            if stopping:
                break
            for observation in notification_parser.feed(line.rstrip("\n")):
                if observation.delivery != "spoken" or not observation.spoken_key:
                    continue
                window = int(time.time() // 90)
                digest = hashlib.sha256(f"{observation.source}\0{observation.category}\0{window}".encode()).hexdigest()
                subprocess.run(
                    [str(ruby), str(cli), "deliver", "--event", "communication_urgent", "--unique-key", f"desktop:{digest}"],
                    cwd=root, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    timeout=25, check=False,
                )
    finally:
        if monitor.poll() is None:
            monitor.terminate()
            try:
                monitor.wait(timeout=2)
            except subprocess.TimeoutExpired:
                monitor.kill()
                monitor.wait(timeout=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
