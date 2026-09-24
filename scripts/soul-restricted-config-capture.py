#!/usr/bin/python3
"""Explicit, fixed-scope system configuration export; never restores files."""

import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

FILES = (
    "etc/audit/rules.d/70-soul-workstation-events.rules",
    "etc/audit/rules.d/71-soul-mount-events.rules",
    "etc/pam.d/su",
    "etc/sudoers.d/85-soul-sudo-audit",
    "etc/logrotate.d/soul-sudo-audit",
    "etc/snmp/snmpd.conf",
    "etc/soul-observability/config.alloy",
)
MAX_BYTES = 1024 * 1024


def read_entry(root, relative, expected_uid=0):
    # Directory descriptors prevent symlink traversal and path replacement races.
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        parts = relative.split("/")
        for part in parts[:-1]:
            next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = next_fd
            info = os.fstat(fd)
            if info.st_uid != expected_uid or info.st_mode & 0o022:
                raise ValueError("unsafe source directory")
        leaf = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
        try:
            before = os.fstat(leaf)
            if (not stat.S_ISREG(before.st_mode) or before.st_uid != expected_uid
                    or before.st_mode & 0o022 or before.st_size > MAX_BYTES):
                raise ValueError("unsafe source file")
            with os.fdopen(os.dup(leaf), "rb") as stream:
                data = stream.read(MAX_BYTES + 1)
            after = os.fstat(leaf)
            if (len(data) > MAX_BYTES or len(data) != before.st_size
                    or (before.st_mtime_ns, before.st_ctime_ns, before.st_size)
                    != (after.st_mtime_ns, after.st_ctime_ns, after.st_size)):
                raise ValueError("source changed during capture")
            return dict(path="/" + relative, uid=before.st_uid, gid=before.st_gid,
                        mode=stat.S_IMODE(before.st_mode), mtime_ns=before.st_mtime_ns,
                        size=len(data), sha256=hashlib.sha256(data).hexdigest(),
                        content_base64=base64.b64encode(data).decode("ascii"))
        finally:
            os.close(leaf)
    finally:
        os.close(fd)


def validate(document):
    entries = document["files"]
    if document["schema"] != "soul.restricted_config_capture.v1" or len(entries) != len(FILES):
        raise ValueError("invalid capture schema")
    for relative, entry in zip(FILES, entries):
        data = base64.b64decode(entry["content_base64"], validate=True)
        if (entry["path"] != "/" + relative or len(data) > MAX_BYTES
                or entry["size"] != len(data) or entry["uid"] != 0
                or entry["mode"] & 0o022
                or hashlib.sha256(data).hexdigest() != entry["sha256"]):
            raise ValueError("invalid capture entry")


def main():
    if sys.argv[1:] == ["--collect"]:
        if os.geteuid() != 0:
            raise ValueError("collection requires explicit root authorization")
        document = dict(schema="soul.restricted_config_capture.v1",
                        captured_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                        files=[read_entry("/", path) for path in FILES])
        print(json.dumps(document))
        return
    if sys.argv[1:] != ["capture"] or os.geteuid() == 0:
        raise ValueError("run as the operator: python3 -I scripts/soul-restricted-config-capture.py capture")
    root = Path(__file__).resolve().parent.parent
    parent = root / "Soul/private/operator_backup"
    # Refuse redirected or shared destination ancestors before authorizing root.
    for path in (root / "Soul/private", parent):
        info = path.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("capture destination must be owner-private")
    result = subprocess.run(
        ["/usr/bin/pkexec", "/usr/bin/python3", "-I", str(Path(__file__).resolve()), "--collect"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120, check=False)
    if result.returncode:
        raise ValueError("authorization or fixed-file collection failed; no capture published")
    document = json.loads(result.stdout)
    validate(document)
    os.umask(0o077)
    # A unique private directory holds an atomic file; no prior capture is overwritten.
    destination = Path(tempfile.mkdtemp(prefix="restricted-config-", dir=parent))
    temporary = destination / "capture.partial"
    final = destination / "capture.json"
    try:
        with temporary.open("xb") as stream:
            stream.write(result.stdout)
            stream.flush()
            os.fsync(stream.fileno())
        validate(json.loads(temporary.read_bytes()))
        temporary.rename(final)
    except Exception:
        temporary.unlink(missing_ok=True)
        destination.rmdir()
        raise
    print(f"Captured {len(FILES)} files with verified hashes: {final}")
    print("No backup was started. Refresh this capture after system configuration changes.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired):
        sys.exit("Restricted configuration capture failed; no source files were changed.")
