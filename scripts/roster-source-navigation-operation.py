#!/usr/bin/env python3
"""Exact enrolled source snapshot; reuse the qualified isolated runner."""
import importlib.util,pathlib,json,signal,sys
spec=importlib.util.spec_from_file_location('existing',pathlib.Path(__file__).with_name('roster-ruby-navigation-operation.py'))
helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
p=helper.p
p.FIXTURE=p.ROOT/'Soul/knowledge_snapshots/soul-workflows-a1'
p.ALLOWED_FILES=frozenset({'workflow_handler_registry.rb','workflow_intent_handler_dispatch.rb','workflow_session_handler_dispatch.rb'})
def run(args):
    result=helper.run(args)
    result['data']['snapshot']='soul-workflows-a1'
    result['data']['file']=args[1]
    result['data']['scope']='reviewed frozen Soul workflow source; omitted dependencies unavailable'
    return result
if __name__=='__main__':
    signal.signal(signal.SIGTERM,lambda *_:(_ for _ in ()).throw(p.Stopped('canceled')))
    try:print(json.dumps(run(sys.argv[1:])))
    except Exception as e:
        print(json.dumps({'state':'failed','data':{'error_class':type(e).__name__,'requires_review':True}}));sys.exit(1)
