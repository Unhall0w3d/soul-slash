#!/usr/bin/env python3
import importlib.util, pathlib, unittest
s=importlib.util.spec_from_file_location('trial',pathlib.Path(__file__).with_name('run-cpu-member-trial.py'));m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class Bounds(unittest.TestCase):
 def test_safe(self):m.validate({'cpu_c':65,'available_bytes':20*1024**3,'rss_bytes':6*1024**3,'gpu_fds':[]})
 def test_each_guard(self):
  base={'cpu_c':65,'available_bytes':20*1024**3,'rss_bytes':6*1024**3,'gpu_fds':[]}
  for key,value in [('cpu_c',85),('available_bytes',12*1024**3-1),('rss_bytes',16*1024**3+1),('gpu_fds',['/dev/dri/renderD128'])]:
   with self.subTest(key=key),self.assertRaises(RuntimeError):m.validate({**base,key:value})
 def test_exact_tool(self):
  good={'function':{'name':'lookup_task','arguments':'{"task_id":"R-42"}'}}
  self.assertTrue(m.valid_tool([good]))
  for calls in [[],[good,good],[{'function':{'name':'shell','arguments':'{"task_id":"R-42"}'}}],[{'function':{'name':'lookup_task','arguments':'{"task_id":"R-42","exec":"x"}'}}],[{'function':{'name':'lookup_task','arguments':'not json'}}]]:self.assertFalse(m.valid_tool(calls))
 def test_frozen_cases(self):
  self.assertEqual(len(m.CASES),6);self.assertEqual(len({c['id'] for c in m.CASES}),6)
  self.assertTrue(all(c['rubric'] for c in m.CASES))
if __name__=='__main__':unittest.main()
