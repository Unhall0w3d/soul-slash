#!/usr/bin/python3 -I
import importlib.util
import pathlib
import unittest
import tempfile
from unittest.mock import patch


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, pathlib.Path(__file__).with_name(file))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


helper = module("accounting", "soul-gpu-accounting.py")
installer = module("installer", "install-gpu-accounting.py")


class AccountingTests(unittest.TestCase):
    def test_sanitized_failure_codes(self):
        for message, code in helper.FAILURES.items():
            self.assertEqual(helper.failure_code(ValueError(message)), code)
        self.assertEqual(helper.failure_code(BlockingIOError("private")), "lock_busy")
        self.assertEqual(helper.failure_code(PermissionError("private")), "permission_denied")
        self.assertEqual(helper.failure_code(ValueError("private")), "unknown")
        self.assertEqual(helper.failure_code(RuntimeError("private")), "unknown")

    TEXT = "drm-pdev: 0000:0a:00.0\ndrm-client-id: 42\ndrm-resident-vram: 100 MiB\ndrm-engine-compute: 20 ns\n"

    def test_parser(self):
        self.assertEqual(helper.parse_client(self.TEXT), {"id": "42", "bytes": 100*1024**2, "compute": 20})
        self.assertIsNone(helper.parse_client(self.TEXT.replace("0a:00", "05:00")))
        with self.assertRaises(ValueError):
            helper.parse_client(self.TEXT.replace("drm-resident-vram", "other"))

    def test_complete_snapshot_recheck_only(self):
        bad = {"used": 1024**3, "clients": [], "monotonic": 1}
        good = {"used": 0, "clients": [], "monotonic": 2}
        with patch.object(helper, "collect_once", side_effect=[bad, good]) as collect:
            row = helper.sample()
            self.assertEqual(row["monotonic"], 2)
            self.assertEqual(len(row["accounting_rechecks"]), 1)
            self.assertEqual(collect.call_count, 2)
        with patch.object(helper, "collect_once", return_value=bad) as collect:
            with self.assertRaises(ValueError):
                helper.sample()
            self.assertEqual(collect.call_count, 3)

    def test_other_failure_not_retried(self):
        with patch.object(helper, "collect_once", side_effect=PermissionError) as collect:
            with self.assertRaises(PermissionError):
                helper.sample()
            self.assertEqual(collect.call_count, 1)

    def test_shared_client_race_recollects_whole_snapshot_with_same_bound(self):
        good = {"used": 0, "clients": [], "monotonic": 2}
        with patch.object(helper, "collect_once", side_effect=[ValueError("shared client changed"), good]) as collect:
            row = helper.sample()
            self.assertEqual(row["clients"], [])
            self.assertEqual(row["monotonic"], 2)
            self.assertEqual(row["accounting_rechecks"], [{"reason": "shared_client_changed"}])
            self.assertEqual(collect.call_count, 2)
        with patch.object(helper, "collect_once", side_effect=ValueError("shared client changed")) as collect:
            with self.assertRaisesRegex(ValueError, "shared client changed"):
                helper.sample()
            self.assertEqual(collect.call_count, 3)
        with patch.object(helper, "collect_once", side_effect=ValueError("process identity changed")) as collect:
            with self.assertRaisesRegex(ValueError, "process identity changed"):
                helper.sample()
            self.assertEqual(collect.call_count, 1)

    def test_no_arguments_or_unprivileged_execution(self):
        with patch.object(helper.sys, "argv", ["helper", "/etc/shadow"]), patch.object(helper.os, "geteuid", return_value=0):
            self.assertEqual(helper.main(), 1)
        with patch.object(helper.sys, "argv", ["helper"]), patch.object(helper.os, "geteuid", return_value=1000):
            self.assertEqual(helper.main(), 1)

    def test_exact_sudo_scope(self):
        rule = installer.sudo_rule("a" * 64).decode()
        self.assertTrue(rule.endswith('snapshot ""\n'))
        self.assertIn("NOSETENV: sha256:", rule)
        self.assertNotIn("*", rule)
        with self.assertRaises(ValueError):
            installer.sudo_rule("ALL")

    def test_invalid_digest_cannot_install(self):
        with patch.object(installer, "write_new") as write:
            with self.assertRaises(ValueError):
                installer.main(["--apply", "0" * 64])
            write.assert_not_called()

    def test_start_identity_handles_parentheses(self):
        self.assertEqual(helper.start_ticks("123 (a ) b) " + " ".join(["0"]*19 + ["456"])), 456)

    def test_closing_one_fd_does_not_erase_other_live_gpu_handles(self):
        from types import SimpleNamespace
        def read(path, *args):
            if path.endswith("/fdinfo/11"):
                raise FileNotFoundError
            if path.endswith("/fdinfo/10"):
                return self.TEXT
            if path.endswith("/stat"):
                return "123 (browser) " + " ".join(["0"]*19+["456"])
            return {"vendor":"0x1002", "device":"0x73bf", "mem_info_vram_total":str(16*1024**3),
                    "mem_info_vram_used":str(100*1024**2)}[path.rsplit("/",1)[1]]
        with patch.object(helper.os,"listdir",side_effect=[["123"],["10","11"]]), \
             patch.object(helper,"read",side_effect=read), \
             patch.object(helper.os,"stat",return_value=SimpleNamespace(st_uid=1000)), \
             patch.object(helper.os,"readlink",return_value="/usr/bin/browser"):
            self.assertEqual(len(helper.collect_once()["clients"]),1)

    def installation(self, fail_validation=False):
        with tempfile.TemporaryDirectory() as root:
            base = pathlib.Path(root)
            target = base / "libexec" / "soul-gpu-accounting" / "snapshot"
            rule = base / "sudoers"
            digest = installer.sha(installer.SOURCE.read_bytes())
            # Exercise real file creation and rollback, with privileged metadata
            # checks mocked only in this unprivileged fixture.
            def write(path, data, mode):
                with path.open("xb") as stream:
                    stream.write(data)
                path.chmod(mode)
            original_lstat = pathlib.Path.lstat
            original_stat = pathlib.Path.stat
            def stat(path, **kwargs):
                info = original_stat(path, **kwargs)
                if str(path).startswith("/usr/bin/python"):
                    from types import SimpleNamespace
                    return SimpleNamespace(st_uid=0, st_mode=info.st_mode)
                return info
            def lstat(path):
                info = original_lstat(path)
                from types import SimpleNamespace
                return SimpleNamespace(st_uid=0, st_mode=info.st_mode)
            calls = []
            def run(*args, **kwargs):
                calls.append(args[0])
                if fail_validation and len(calls) == 3:
                    raise RuntimeError("simulated final validation failure")
            with patch.object(installer, "HELPER", target), patch.object(installer, "RULE", rule), \
                 patch.object(installer, "trusted_directory"), patch.object(installer, "write_new", side_effect=write), \
                 patch.object(installer.os, "geteuid", return_value=0), \
                 patch.object(pathlib.Path, "lstat", lstat), \
                 patch.object(pathlib.Path, "stat", stat), \
                 patch.object(installer.subprocess, "run", side_effect=run), \
                 patch("builtins.print"):
                if fail_validation:
                    with self.assertRaises(RuntimeError):
                        installer.main(["--apply", digest])
                    self.assertFalse(target.exists())
                    self.assertFalse(rule.exists())
                else:
                    installer.main(["--apply", digest])
                    self.assertEqual(target.read_bytes(), installer.SOURCE.read_bytes())
                    self.assertEqual(rule.read_bytes(), installer.sudo_rule(digest))
                    with self.assertRaises(ValueError):
                        installer.main(["--apply", digest])

    def test_install_readback_and_existing_target_refusal(self):
        self.installation()

    def test_failed_install_rolls_back_only_created_targets(self):
        self.installation(fail_validation=True)

    def test_digest_bound_upgrade_and_rollback(self):
        from types import SimpleNamespace
        for fail in (False, True):
            with tempfile.TemporaryDirectory() as root:
                base=pathlib.Path(root)
                target, rule=base/"snapshot", base/"sudoers"
                old=b"old installed fixture"
                old_digest=installer.sha(old)
                new_digest=installer.sha(installer.SOURCE.read_bytes())
                original_lstat=pathlib.Path.lstat
                def metadata(path):
                    info=original_lstat(path)
                    return SimpleNamespace(st_uid=0,st_mode=info.st_mode)
                def write(path,data,mode):
                    with path.open("xb") as stream:
                        stream.write(data)
                    path.chmod(mode)
                with patch.object(installer,"HELPER",target), patch.object(installer,"RULE",rule), \
                     patch.object(installer,"BACKUPS",base), patch.object(installer,"trusted_directory"), \
                     patch.object(installer,"write_new",side_effect=write), \
                     patch.object(installer.os,"geteuid",return_value=0), \
                     patch.object(pathlib.Path,"lstat",metadata), patch("builtins.print"):
                    write(target,old,0o755)
                    old_rule=installer.sudo_rule(old_digest)
                    write(rule,old_rule,0o440)
                    outcomes=[None,RuntimeError("aggregate validation failed")] if fail else [None,None]
                    with patch.object(installer.subprocess,"run",side_effect=outcomes):
                        if fail:
                            with self.assertRaises(RuntimeError):
                                installer.upgrade(old_digest,new_digest)
                            self.assertEqual(target.read_bytes(),old)
                            self.assertEqual(rule.read_bytes(),old_rule)
                        else:
                            installer.upgrade(old_digest,new_digest)
                            self.assertEqual(target.read_bytes(),installer.SOURCE.read_bytes())
                            self.assertEqual(rule.read_bytes(),installer.sudo_rule(new_digest))
                    backups=list(base.glob("soul-gpu-accounting-*"))
                    self.assertEqual(len(backups),1)
                    self.assertEqual((backups[0]/"snapshot").read_bytes(),old)


if __name__ == "__main__":
    unittest.main()
