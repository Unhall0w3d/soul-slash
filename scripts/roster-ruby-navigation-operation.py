#!/usr/bin/env python3
"""Foreground helper; caller owns attribution and durable replay."""
import importlib.util,json,pathlib,sys,tempfile,os,hashlib,signal
spec=importlib.util.spec_from_file_location('a2',pathlib.Path(__file__).with_name('pilot-ruby-navigation-multifile.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
p=m.p

def run(args):
    if len(args)!=4:raise p.Refused('query arity')
    action,name,line,char=args
    methods={'definition':p.METHODS[0],'symbols':p.METHODS[2],'references':p.METHODS[1]}
    if action not in methods or not line.isdecimal() or not char.isdecimal():raise p.Refused('query selector')
    q={'method':methods[action],'file':name,'line':int(line),'character':int(char)}
    p.validate(q);before=m.verify_snapshot();server=None;source=p.FIXTURE
    stage=tempfile.TemporaryDirectory(prefix='soul-ruby-snapshot-')
    try:
        # The server sees a verified private copy, never mutable live project files.
        for name,expected in dict(before,**{'snapshot.json':hashlib.sha256((source/'snapshot.json').read_bytes()).hexdigest()}).items():
            fd=os.open(source/name,os.O_RDONLY|os.O_NOFOLLOW)
            with os.fdopen(fd,'rb') as f:content=f.read(262145)
            if len(content)>262144 or hashlib.sha256(content).hexdigest()!=expected:raise p.Refused('snapshot copy mismatch')
            dest=pathlib.Path(stage.name)/name
            with dest.open('xb') as f:f.write(content)
            dest.chmod(0o400)
        p.FIXTURE=pathlib.Path(stage.name)
        if before!=m.verify_snapshot():raise p.Refused('staged snapshot changed')
        server=p.Server();server.initialize();raw=server.query(q)
        if before!=m.verify_snapshot():raise p.Refused('snapshot changed during query')
        data={'snapshot':'navigation-a2','snapshot_sha256':p.digest(before),
              'scope':'reviewed synthetic snapshot only','file':name,'line':int(line)+1,'character':int(char)+1,
              'label':'possible matches; not an exhaustive caller list' if action=='references' else 'navigation candidates',
              'locations':m.symbols(raw) if action=='symbols' else [list(x) for x in m.normalize_locations(raw)],
              'location_convention':'zero-based source lines in locations',
              'evidence':raw,'source_is_untrusted_data':True}
        return {'state':'complete','data':data}
    finally:
        try:
            if server:server.close()
        finally:
            p.FIXTURE=source
            stage.cleanup()
if __name__=='__main__':
    signal.signal(signal.SIGTERM,lambda *_:(_ for _ in ()).throw(p.Stopped('canceled')))
    try:print(json.dumps(run(sys.argv[1:])))
    except Exception as e:
        print(json.dumps({'state':'failed','data':{'error_class':type(e).__name__,'requires_review':True}}));sys.exit(1)
