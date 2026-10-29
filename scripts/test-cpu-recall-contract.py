#!/usr/bin/env python3
import unittest,json,copy,importlib.util,pathlib,io
from unittest.mock import patch
from cpu_recall_contract import parse,calculate,assess,schema
s=importlib.util.spec_from_file_location('pilot',pathlib.Path(__file__).with_name('run-cpu-context8k-practical.py'));m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class Contract(unittest.TestCase):
 def test_valid_cases_and_calculation(self):
  for c in [m.SHORT]+m.CASES:
   d=c['expected'];self.assertTrue(assess(json.dumps(d),d,c['sources'],c['project'])['all_correct'])
   wrong={**d,'remaining':d['remaining']+10};a=assess(json.dumps(wrong),d,c['sources'],c['project']);self.assertFalse(a['all_correct']);self.assertTrue(a['assisted_all_correct']);self.assertEqual(wrong['remaining'],d['remaining']+10)
 def test_strict_shape(self):
  d=m.SHORT['expected']
  for text in ['```json\n'+json.dumps(d)+'\n```','[]',json.dumps({**d,'extra':'x'}),json.dumps({k:v for k,v in d.items() if k!='code'}),json.dumps(d)[:-1]+',"code":"duplicate"}']:
   with self.assertRaises(ValueError):parse(text)
 def test_integer_and_size(self):
  d=m.SHORT['expected']
  for value in [True,'407',1.5,1000001,float('nan')]:
   with self.assertRaises(ValueError):parse(json.dumps({**d,'remaining':value}))
  with self.assertRaises(ValueError):parse(' '*4097)
 def test_scope_stale_and_expression_refusal(self):
  c=m.SHORT;d=c['expected']
  for ref in ['other-b','Brook-old','Brook-d','__import__("os").system("id")','missing']:
   with self.assertRaises(ValueError):calculate({**d,'budget_source':ref},c['sources'],c['project'])
 def test_source_types(self):
  c=m.SHORT
  for v in [True,-1,1000001,'583']:
   sources=copy.deepcopy(c['sources']);sources['Brook-b']['value']=v
   with self.assertRaises(ValueError):calculate(c['expected'],sources,c['project'])
 def test_wrong_non_arithmetic_not_repaired(self):
  c=m.SHORT;d={**c['expected'],'contact':'wrong'};self.assertFalse(assess(json.dumps(d),c['expected'],c['sources'],c['project'])['assisted_all_correct'])
 def test_no_answer_in_schema(self):
  text=json.dumps(schema())
  for c in m.CASES:
   for field in ['contact','code','budget_source']:self.assertNotIn(c['expected'][field],text)
 def test_budget_before_inference(self):
  t=m.PracticalTrial.__new__(m.PracticalTrial);t.requests=0;t.context=8192;t.tokens=lambda _:7137
  with self.assertRaisesRegex(RuntimeError,'reservation'):t.request('x',[])
  self.assertEqual(t.requests,0);t.requests=15
  with self.assertRaisesRegex(RuntimeError,'Reply count'):t.request('x',[])
 def test_native_payload_and_raw_control(self):
  for constrained in [False,True]:
   t=m.PracticalTrial.__new__(m.PracticalTrial);t.requests=0;t.context=8192;t.tokens=lambda _:50;t.candidate_deadline=float('inf');t.started=m.time.monotonic();t.samples=[];t.results=[];t.problem=None;t.active_schema=schema() if constrained else None;saved={};t.save=lambda k,v:saved.update({k:v})
   event={'choices':[{'delta':{'content':'{}'},'finish_reason':'stop'}]}
   with patch.object(m.urllib.request,'urlopen',return_value=io.BytesIO(('data: '+json.dumps(event)+'\n\ndata: [DONE]\n').encode())):
    t.request('mock',[])
   p=saved['mock-request.json'];self.assertEqual('response_format' in p,constrained);self.assertFalse(p['chat_template_kwargs']['enable_thinking']);self.assertEqual(p['max_tokens'],1024)
if __name__=='__main__':unittest.main()
