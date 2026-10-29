#!/usr/bin/env python3
import importlib.util,pathlib,unittest
s=importlib.util.spec_from_file_location('trial',pathlib.Path(__file__).with_name('run-cpu-context-qualification.py'));m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class Qualification(unittest.TestCase):
 def test_exact_recall(self):
  import json
  for expected in m.EXPECTED.values():
   self.assertTrue(m.score(json.dumps(expected),expected)['all_correct'])
   for key in expected:
    changed=dict(expected);changed[key]='invented';self.assertFalse(m.score(json.dumps(changed),expected)['all_correct'])
  self.assertFalse(m.score('[]',m.EXPECTED[0])['valid_json'])
  self.assertFalse(m.score('```json\n{}\n```',m.EXPECTED[0])['valid_json'])
 def test_field_and_extra_rejection(self):
  import json
  expected=m.EXPECTED[8];self.assertFalse(m.score(json.dumps({**expected,'other':1}),expected)['all_correct'])
  result=m.score(json.dumps({**expected,'delivery':'Tuesday'}),expected)
  self.assertFalse(result['fields']['delivery']);self.assertTrue(result['fields']['contact'])
 def test_context_reservation_before_request(self):
  t=m.ContextTrial.__new__(m.ContextTrial);t.requests=0;t.context=32768;t.tokens=lambda _:31713
  with self.assertRaisesRegex(RuntimeError,'reservation'):t.request('x',[])
  self.assertEqual(t.requests,0)
 def test_request_bound(self):
  t=m.ContextTrial.__new__(m.ContextTrial);t.requests=15
  with self.assertRaisesRegex(RuntimeError,'Reply count'):t.request('x',[])
 def test_packet_and_noise(self):
  self.assertEqual(len(m.TARGETS),9);self.assertEqual(set(m.EXPECTED),{0,4,8})
  for i in range(800):
   n=m.note(i)
   for name in ['Cedar','Juniper','Mira','LARK','Thursday']:self.assertNotIn(name,n)
if __name__=='__main__':unittest.main()
