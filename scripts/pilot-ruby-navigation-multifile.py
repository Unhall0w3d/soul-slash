#!/usr/bin/env python3
"""A2 qualification only; exact reviewed snapshot, no live tool registration."""
import importlib.util,json,os,pathlib,sys,time,hashlib
HERE=pathlib.Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('navigation_a1',HERE/'pilot-ruby-navigation.py')
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
p.FIXTURE=p.ROOT/'test/fixtures/ruby_navigation_a2'
p.ALLOWED_FILES=frozenset({'alpha.rb','beta.rb','location.rb','child.rb','calls.rb'})

def verify_snapshot():
    if p.FIXTURE.is_symlink():raise p.Refused('snapshot root symlink')
    actual=p.files_hash(p.FIXTURE)
    manifest=json.loads((p.FIXTURE/'snapshot.json').read_text())
    actual.pop('snapshot.json',None)
    if actual!=manifest:raise p.Refused('reviewed snapshot changed')
    return actual

def normalize_locations(raw):
    p.check_result(raw)
    out=[]
    for x in raw or []:
        uri=x.get('targetUri',x.get('uri'))
        path=p.urllib.parse.unquote(p.urllib.parse.urlsplit(uri).path)
        pos=x.get('targetSelectionRange',x.get('range'))['start']
        out.append([pathlib.PurePosixPath(path).name,pos['line']])
    return sorted({tuple(x) for x in out})

def symbols(raw,prefix=''):
    out=[]
    for x in raw or []:
        name=prefix+x['name']
        out.append([name,x['kind'],x['selectionRange']['start']['line']])
        out.extend(symbols(x.get('children',[]),name+'::'))
    return sorted(out)

def main(out):
    os.umask(0o077);out=pathlib.Path(out);out.mkdir(mode=0o700,parents=True,exist_ok=False)
    result={'state':'starting','cases':[]};server=None;before=None;t=time.monotonic()
    try:
        before=verify_snapshot();p.verify_dependencies()
        packet=json.loads((p.FIXTURE/'cases.json').read_text())
        identity={'a1_harness':hashlib.sha256((HERE/'pilot-ruby-navigation.py').read_bytes()).hexdigest(),
                  'a2_harness':hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
                  'dependency_pin':json.loads((p.FIXTURE/'dependencies.json').read_text()),'snapshot':before}
        (out/'frozen-packet.json').write_text(json.dumps({'cases':packet,'identity':identity},indent=2))
        server=p.Server();server.initialize()
        for i,case in enumerate(packet):
            verify_snapshot();q=case['query'];start=time.monotonic()
            receipt=p.invoke(out/'requests',p.MEMBERS[i%3],case['id'],q,identity,server.query)
            replay=p.invoke(out/'requests',p.MEMBERS[i%3],case['id'],q,identity,
                            lambda _:(_ for _ in ()).throw(AssertionError('replay executed')))
            raw=receipt['output']
            actual=symbols(raw) if q['method']==p.METHODS[2] else [list(x) for x in normalize_locations(raw)]
            result['cases'].append({'id':case['id'],'expected':case.get('expected'),'actual':actual,
                'matches_expected':actual==sorted(case['expected']) if 'expected' in case else None,
                'label':receipt['result_label'],'raw':raw,'replay_exact':raw==replay['output'],
                'seconds':round(time.monotonic()-start,4)})
        result['state']='complete_pending_review'
    except Exception as e:result.update(state='failed',error_class=type(e).__name__,error=str(e))
    finally:
        if server:
            pid=server.p.pid;result['process_reaped']=server.close();result['pid']=pid
            try:os.killpg(pid,0);result['process_group_gone']=False
            except ProcessLookupError:result['process_group_gone']=True
            result['messages']=server.messages;result['stderr']=server.stderr.decode(errors='replace')
        try:result['snapshot_unchanged']=before is not None and before==verify_snapshot()
        except Exception:result['snapshot_unchanged']=False
        result['seconds']=round(time.monotonic()-t,3)
        (out/'receipt.json').write_text(json.dumps(result,indent=2))
        print(json.dumps({k:v for k,v in result.items() if k not in ('messages','cases','stderr')}))
    return 1 if result['state']=='failed' else 0
if __name__=='__main__':sys.exit(main(sys.argv[1]))
