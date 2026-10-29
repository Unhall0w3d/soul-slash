#!/usr/bin/env python3
import unittest,importlib.util,pathlib,io,json
from unittest.mock import patch
s=importlib.util.spec_from_file_location('g',pathlib.Path(__file__).with_name('run-cpu-context8k-grammar.py'));g=importlib.util.module_from_spec(s);s.loader.exec_module(g)
class Grammar(unittest.TestCase):
 def test_converter_has_root_and_no_thought_rule(self):
  text=g.grammar_for(g.schema());self.assertIn('root ::=',text);self.assertNotIn('thought',text);self.assertNotIn('```',text)
 def test_grammar_payload_and_nonthinking_rejection(self):
  for reasoning in ['', 'synthetic diagnostic marker']:
   t=g.PracticalTrial.__new__(g.PracticalTrial);t.requests=0;t.context=8192;t.tokens=lambda _:50;t.candidate_deadline=float('inf');t.started=g.time.monotonic();t.samples=[];t.results=[];t.problem=None;t.active_schema=g.schema();saved={};t.save=lambda k,v:saved.update({k:v})
   event={'choices':[{'delta':{'content':'{}','reasoning_content':reasoning},'finish_reason':'stop'}]}
   with patch.object(g.urllib.request,'urlopen',return_value=io.BytesIO(('data: '+json.dumps(event)+'\ndata: [DONE]\n').encode())):
    if reasoning:
     with self.assertRaisesRegex(RuntimeError,'Unexpected thinking'):t.request('mock',[])
    else:t.request('mock',[])
   self.assertNotIn('response_format',saved['mock-request.json']);self.assertIn('grammar',saved['mock-request.json']);self.assertEqual(saved['mock-result.json']['reasoning_chars'],len(reasoning));self.assertNotIn(reasoning,json.dumps(saved)) if reasoning else None
if __name__=='__main__':unittest.main()
