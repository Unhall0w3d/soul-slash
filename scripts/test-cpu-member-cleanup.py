#!/usr/bin/env python3
import importlib.util,pathlib,subprocess,unittest
from unittest.mock import Mock,patch
s=importlib.util.spec_from_file_location('trial',pathlib.Path(__file__).with_name('run-cpu-member-trial.py'));m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class Cleanup(unittest.TestCase):
 def test_term_owned_group(self):
  t=m.Trial.__new__(m.Trial);t.proc=Mock(pid=123);t.proc.poll.return_value=None
  with patch.object(m.os,'killpg') as kill:t.terminate();kill.assert_called_once_with(123,m.signal.SIGTERM)
 def test_kill_after_grace(self):
  t=m.Trial.__new__(m.Trial);t.proc=Mock(pid=123);t.proc.poll.return_value=None;t.proc.wait.side_effect=[subprocess.TimeoutExpired('owned',5),0]
  with patch.object(m.os,'killpg') as kill:t.terminate();self.assertEqual([c.args for c in kill.call_args_list],[(123,m.signal.SIGTERM),(123,m.signal.SIGKILL)])
 def test_no_signal_after_exit(self):
  t=m.Trial.__new__(m.Trial);t.proc=Mock();t.proc.poll.return_value=0
  with patch.object(m.os,'killpg') as kill:t.terminate();kill.assert_not_called()
 def test_missing_telemetry(self):
  with patch.object(m.pathlib.Path,'glob',return_value=[]),self.assertRaisesRegex(RuntimeError,'telemetry'):m.resources()
if __name__=='__main__':unittest.main()
