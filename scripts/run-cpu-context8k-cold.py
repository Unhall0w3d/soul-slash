#!/usr/bin/env python3
"""One cold-history request in a fresh CPU process; no slot persistence enabled."""
import importlib.util,pathlib,json,signal
spec=importlib.util.spec_from_file_location('grammar_trial',pathlib.Path(__file__).with_name('run-cpu-context8k-grammar.py'))
g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
REQUEST=g.m.ROOT/'Soul/runtime/qualification/cpu-member-context8k-grammar-uung24gh/heldout-1-repeat-request.json'
REQUEST_SHA='1bde8e9198430077ce78e5c2a0b4872129b6cd956bd03e853fc990867bb96404'
class ColdTrial(g.PracticalTrial):
 def save(self,name,value):
  if name=='frozen-packet.json':
   value['source_hashes']['scripts/run-cpu-context8k-cold.py']=g.m.digest(__file__)
   value.update(condition='one fresh-process cold request; same final history as grammar pilot; no slot save or restore',retained_request_sha256=REQUEST_SHA,reply_limit=1)
  super().save(name,value)
 def cases(self):
  if g.m.digest(REQUEST)!=REQUEST_SHA:raise RuntimeError('Retained input changed')
  payload=json.loads(REQUEST.read_text())
  self.checked('cold-full-history',payload['messages'],g.CASES[-1],seed=73,cache=False)
if __name__=='__main__':
 def cancel(sig,frame):raise KeyboardInterrupt('Canceled')
 signal.signal(signal.SIGINT,cancel);signal.signal(signal.SIGTERM,cancel)
 trial=ColdTrial();print(json.dumps({'state':'starting','output':str(trial.out)}),flush=True);raise SystemExit(trial.run())
