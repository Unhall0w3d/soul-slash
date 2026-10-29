#!/usr/bin/env python3
"""Isolated qualification harness; no production endpoint or model authority."""
import hashlib,json,os,pathlib,select,signal,subprocess,sys,time,uuid,urllib.parse
ROOT=pathlib.Path(__file__).resolve().parents[1]
FIXTURE=ROOT/'test/fixtures/ruby_navigation_a1'
ALLOWED_FILES=frozenset({'sample.rb'})
DEPS=ROOT/'Soul/runtime/qualification/ruby-navigation-deps/src'
RUBY=pathlib.Path('/home/bhones/.rbenv/versions/4.0.7')
MEMBERS=('gpt-oss-20b','gemma-4-26b-a4b','qwen3.8-27b')
METHODS=('textDocument/definition','textDocument/references','textDocument/documentSymbol')
MAX=262144
class Refused(Exception): pass
class Stopped(Exception): pass
def digest(x): return hashlib.sha256(json.dumps(x,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def files_hash(root):
    out={}
    for p in sorted(root.rglob('*')):
        if p.is_symlink(): raise Refused('symlink fixture')
        if p.is_file(): out[str(p.relative_to(root))]=hashlib.sha256(p.read_bytes()).hexdigest()
    return out
def validate(q):
    if not isinstance(q,dict) or set(q)!={'method','file','line','character'}: raise Refused('query schema')
    if q['method'] not in METHODS or q['file'] not in ALLOWED_FILES: raise Refused('operation or path')
    if any(type(q[k]) is not int or not 0<=q[k]<10000 for k in ('line','character')): raise Refused('position')
    p=FIXTURE/q['file']
    if p.is_symlink() or FIXTURE.is_symlink() or p.resolve().parent!=FIXTURE.resolve(): raise Refused('fixture path')
    return q

def verify_dependencies():
    expected=json.loads((FIXTURE/'dependencies.json').read_text())
    if digest(files_hash(DEPS))!=expected['source_tree_sha256']:raise Refused('dependency source changed')
    for name,sha in expected['gems'].items():
        if hashlib.sha256((DEPS.parent/name).read_bytes()).hexdigest()!=sha:raise Refused('dependency artifact changed')

def command():
    # No actual home, repository, devices or network are available to the server.
    return ['/usr/bin/bwrap','--unshare-all','--die-with-parent','--new-session',
      '--ro-bind','/usr','/usr','--symlink','usr/lib','/lib','--symlink','usr/lib','/lib64',
      '--proc','/proc','--dev','/dev','--tmpfs','/tmp','--dir','/home/pilot',
      '--ro-bind',str(RUBY),str(RUBY),'--ro-bind',str(DEPS),'/deps',
      '--ro-bind',str(FIXTURE),'/fixture','--chdir','/fixture','--clearenv',
      '--setenv','HOME','/home/pilot','--setenv','PATH',str(RUBY/'bin')+':/usr/bin',
      '--setenv','LANG','C.UTF-8',str(RUBY/'bin/ruby'),
      '-I/deps/ruby-lsp-0.26.11/lib','-I/deps/language_server-protocol-3.17.0.5/lib',
      '-e',"require 'ruby_lsp/internal'; server=RubyLsp::Server.new; $>=$stderr; server.start"]
class Server:
    def __init__(self,cancel=lambda:False):
        verify_dependencies()
        self.started=time.monotonic(); self.cancel=cancel; self.deadline=time.monotonic()+30; self.buffer=b'';self.messages=[];self.seq=0
        self.p=subprocess.Popen(command(),stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
          env={'PATH':'/usr/bin:/bin'},start_new_session=True)
        self.stderr=b'';self.total=0
    def check(self):
        if self.cancel() or time.monotonic()>=self.deadline or time.monotonic()-self.started>600: raise Stopped('canceled or deadline')
    def send(self,method,params=None,request=True):
        self.check();m={'jsonrpc':'2.0','method':method,'params':params or {}}
        if request:self.seq+=1;m['id']=self.seq
        b=json.dumps(m).encode();self.p.stdin.write(f'Content-Length: {len(b)}\r\n\r\n'.encode()+b);self.p.stdin.flush()
        return m.get('id')
    def receive(self):
        while True:
            self.check()
            if b'\r\n\r\n' in self.buffer:
                head,body=self.buffer.split(b'\r\n\r\n',1)
                size=int(head.decode().split('Content-Length: ')[1].split('\r\n')[0])
                if size>MAX:raise Refused('message bound')
                if len(body)>=size:
                    self.buffer=body[size:];return json.loads(body[:size])
            ready,_,_=select.select([self.p.stdout,self.p.stderr],[],[],.05)
            for stream in ready:
                b=os.read(stream.fileno(),65536)
                if not b and self.p.poll() is not None:raise Refused('server exited: '+self.stderr.decode(errors='replace')[-1500:])
                self.total+=len(b)
                if self.total>MAX:raise Refused('output bound')
                if stream is self.p.stdout:self.buffer+=b
                else:self.stderr+=b
    def response(self,id):
        while True:
            m=self.receive();self.messages.append(m)
            if m.get('id')==id and ('result' in m or 'error' in m):
                if 'error' in m:raise Refused('LSP error '+json.dumps(m['error']))
                return m['result']
            if 'method' in m and 'id' in m:
                b=json.dumps({'jsonrpc':'2.0','id':m['id'],'error':{'code':-32601,'message':'client operation disabled'}}).encode()
                self.p.stdin.write(f'Content-Length: {len(b)}\r\n\r\n'.encode()+b);self.p.stdin.flush()
    def initialize(self):
        self.response(self.send('initialize',{'processId':None,'rootUri':'file:///fixture',
          'workspaceFolders':[{'uri':'file:///fixture','name':'pilot'}],
          'capabilities':{'window':{'workDoneProgress':True}},
          'initializationOptions':{'enabledFeatures':['definition','references','documentSymbols'],
            'formatter':'none','linters':[],'indexing':{'excludedGems':[p.name.removesuffix('.rb') for p in (RUBY/'lib/ruby/4.0.0').iterdir()]}}}))
        self.send('initialized',request=False)
        # Wait for indexing completion, never infer readiness from an idle pipe.
        while True:
            m=self.receive();self.messages.append(m)
            if m.get('method')=='window/showMessage' and m.get('params',{}).get('type')==1: raise Refused('indexing error: '+m['params']['message'])
            if m.get('method')=='$/progress' and m.get('params',{}).get('value',{}).get('kind')=='end':break
            if 'id' in m and 'method' in m:
                b=json.dumps({'jsonrpc':'2.0','id':m['id'],'result':None}).encode()
                self.p.stdin.write(f'Content-Length: {len(b)}\r\n\r\n'.encode()+b);self.p.stdin.flush()
        for name in sorted(ALLOWED_FILES):
            validate({'method':METHODS[2],'file':name,'line':0,'character':0})
            text=(FIXTURE/name).read_text()
            self.send('textDocument/didOpen',{'textDocument':{'uri':'file:///fixture/'+name,'languageId':'ruby','version':1,'text':text}},False)
    def query(self,q):
        validate(q);self.deadline=time.monotonic()+30
        p={'textDocument':{'uri':'file:///fixture/'+q['file']}}
        if q['method']!='textDocument/documentSymbol':p['position']={'line':q['line'],'character':q['character']}
        if q['method']=='textDocument/references':p['context']={'includeDeclaration':False}
        r=self.response(self.send(q['method'],p));check_result(r);return r
    def close(self):
        try:os.killpg(self.p.pid,signal.SIGKILL)
        except ProcessLookupError:pass
        self.p.wait(timeout=5)
        for s in (self.p.stdin,self.p.stdout,self.p.stderr):s.close()
        return self.p.returncode is not None

def check_result(r):
    if len(json.dumps(r).encode())>MAX: raise Refused('result bound')
    if isinstance(r,dict):
        for k,v in r.items():
            if k in ('uri','targetUri'):
                u=urllib.parse.urlsplit(v); path=urllib.parse.unquote(u.path)
                if u.scheme!='file' or u.netloc or u.query or u.fragment or '..' in path.split('/') or str(pathlib.PurePosixPath(path)) not in {'/fixture/'+name for name in ALLOWED_FILES}:raise Refused('foreign result URI')
            check_result(v)
    elif isinstance(r,list):
        for x in r:check_result(x)

def invoke(directory,member,request,q,identity,execute,cancel=lambda:False):
    validate(q)
    if member not in MEMBERS:raise Refused('member')
    if not isinstance(request,str) or not request.isalnum() or len(request)>64:raise Refused('request identity')
    if directory.is_symlink():raise Refused('receipt directory')
    directory.mkdir(mode=0o700,parents=True,exist_ok=True)
    inp={'member':member,'query':q,'candidate':identity,'fixture':files_hash(FIXTURE)}
    path=directory/(request+'.json');binding=digest(inp)
    if path.is_symlink():raise Refused('receipt symlink')
    if path.exists():
        r=json.loads(path.read_text())
        if r.get('binding')!=binding or r.get('state')!='complete' or r.get('output_sha256')!=digest(r.get('output')):raise Refused('changed or unfinished replay')
        return dict(r,replayed=True)
    if cancel():raise Stopped('pre-canceled')
    with path.open('x') as f:json.dump({'state':'started','binding':binding},f);f.flush();os.fsync(f.fileno())
    try:
        output=execute(q)
        if cancel():raise Stopped('canceled')
        check_result(output)
        r={'state':'complete','binding':binding,'member':member,'query':q,'candidate':identity,
          'result_label':'possible references' if q['method']=='textDocument/references' else 'navigation candidates',
          'provider':'ruby-lsp','model_invoked':False,'untrusted_reference_data':True,
          'output':output,'output_sha256':digest(output),'replayed':False}
    except Exception as e:
        path.write_text(json.dumps({'state':'canceled' if isinstance(e,Stopped) else 'failed','binding':binding,'error_class':type(e).__name__}))
        raise
    temp=directory/(request+'.tmp')
    with temp.open('x') as f:json.dump(r,f);f.flush();os.fsync(f.fileno())
    os.replace(temp,path);return r

def main():
    os.umask(0o077)
    out=pathlib.Path(sys.argv[1]);out.mkdir(mode=0o700,parents=True,exist_ok=False)
    result={'state':'starting'};server=None;before=files_hash(FIXTURE);started=time.monotonic()
    try:
        packet=json.loads((ROOT/'test/fixtures/ruby_navigation_a1/cases.json').read_text())
        identity={'dependencies':files_hash(DEPS),'harness':hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()}
        (out/'frozen-packet.json').write_text(json.dumps({'cases':packet,'identity':identity,'fixture':before},indent=2))
        server=Server();server.initialize()
        result['symbols']=server.query({'method':METHODS[2],'file':'sample.rb','line':0,'character':0})
        result['cases']=[]
        for i,case in enumerate(packet):
            q=case['query']; t=time.monotonic()
            try:
                r=invoke(out/'requests',MEMBERS[i%3],f'case{i}',q,identity,server.query)
            except Refused as e:
                result['cases'].append({'id':case['id'],'state':'blocked','error':str(e),'expected':case['expected']})
                continue
            replay=invoke(out/'requests',MEMBERS[i%3],f'case{i}',q,identity,lambda q:(_ for _ in ()).throw(AssertionError('replay executed')))
            locations=r['output'] or []
            if not isinstance(locations,list):locations=[locations]
            actual=[x.get('range',x.get('targetSelectionRange',{})).get('start',{}).get('line') for x in locations]
            text=(FIXTURE/'sample.rb').read_text().splitlines()
            baseline=[{'line':j,'text':line} for j,line in enumerate(text) if case['needle'] in line]
            result['cases'].append({'id':case['id'],'locations':actual,'expected':case['expected'],
              'matches_expected':sorted(set(actual))==sorted(case['expected']),'duplicate_locations':len(actual)-len(set(actual)),'reply':r['output'],
              'exact_replay':replay['output']==r['output'],'baseline_candidates':baseline,
              'lsp_output_bytes':len(json.dumps(r['output']).encode()),'baseline_output_bytes':len(json.dumps(baseline).encode()),
              'seconds':round(time.monotonic()-t,4)})
        result['state']='complete_pending_review'
    except Exception as e:result.update(state='failed',error_class=type(e).__name__,error=str(e))
    finally:
        if server:result['cleanup']=server.close();result['messages']=server.messages;result['stderr']=server.stderr.decode(errors='replace')
        result['fixture_unchanged']=before==files_hash(FIXTURE);result['seconds']=round(time.monotonic()-started,3)
        (out/'receipt.json').write_text(json.dumps(result,indent=2));print(json.dumps({k:v for k,v in result.items() if k not in ('messages','symbols','stderr','cases')}))
    return 1 if result['state']=='failed' else 0
if __name__=='__main__':sys.exit(main())
