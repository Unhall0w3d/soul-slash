#!/usr/bin/env python3
"""Foreground A2 acceptance owner; no service installation or automatic retry."""
import importlib.util,pathlib,json,os,subprocess,time,threading,urllib.request,signal
spec=importlib.util.spec_from_file_location('a1',pathlib.Path(__file__).with_name('run-cpu-member-trial.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
t=m.Trial('integration');child=None;state='failed';error=None;thread=None
configs={str(p.relative_to(m.ROOT)):m.digest(p) for p in (m.ROOT/'config').rglob('*') if p.is_file() and not p.is_symlink()}
def cancel(sig,frame):raise KeyboardInterrupt('Canceled')
signal.signal(signal.SIGINT,cancel);signal.signal(signal.SIGTERM,cancel)
try:
 if os.getuid()==0:raise RuntimeError('Root inference refused')
 if not m.closed():raise RuntimeError('Trial port occupied')
 m.validate(m.resources())
 manifest=json.loads((m.ASSETS/'verification.json').read_text())
 for name,sha in manifest['runtime_files'].items():
  if m.digest(m.BUILD/'bin'/name)!=sha:raise RuntimeError('Runtime changed')
 file,sha,size=m.MODELS['gemma'];model=m.ASSETS/file
 if model.stat().st_size!=size or m.digest(model)!=sha:raise RuntimeError('Artifact changed')
 argv=[str(m.BUILD/'bin/llama-server'),'-m',str(model),'--alias','gemma-4-e4b-cpu','--host','127.0.0.1','--port',str(m.PORT),'--device','none','--gpu-layers','0','--jinja','--ctx-size','4096','--parallel','1','--threads','6','--threads-batch','6','--batch-size','256','--ubatch-size','64','--no-context-shift','--no-warmup','--fit','off','--reasoning-format','deepseek','--reasoning','off','--slots']
 t.save('intent.json',{'argv':argv,'config_hashes':configs,'overall_seconds':600,'source_hashes':{name:m.digest(m.ROOT/name) for name in ['scripts/run-cpu-member-integration.py','scripts/verify-cpu-member-integration.rb','lib/soul_core/cpu_member_gateway.rb','lib/soul_core/cpu_member_adapter.rb','lib/soul_core/cpu_member_loopback_client.rb']}})
 env={k:v for k,v in os.environ.items() if not k.startswith(('LLAMA_','GGML_','CUDA_','HIP_','ROCR_'))};env['CUDA_VISIBLE_DEVICES']='';env['HIP_VISIBLE_DEVICES']=''
 t.candidate_deadline=t.started+600
 with open(t.out/'server.log','xb') as log:t.proc=subprocess.Popen(argv,stdout=log,stderr=subprocess.STDOUT,env=env,start_new_session=True)
 t.save('owned-process.json',{'pid':t.proc.pid})
 thread=threading.Thread(target=t.monitor,daemon=True);thread.start()
 while True:
  if t.problem:raise RuntimeError(t.problem)
  if t.proc.poll() is not None:raise RuntimeError('Runtime exited')
  if time.monotonic()>t.started+180:raise RuntimeError('Startup timeout')
  try:
   with urllib.request.urlopen(m.BASE+'/health',timeout=1) as r:
    if r.status==200:break
  except OSError:time.sleep(.25)
 with open(t.out/'gateway.log','xb') as log:
  child=subprocess.Popen(['/home/bhones/.rbenv/versions/4.0.7/bin/ruby',str(m.ROOT/'scripts/verify-cpu-member-integration.rb'),str(t.out),str(t.proc.pid)],stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
 while child.poll() is None:
  if t.problem:raise RuntimeError(t.problem)
  if time.monotonic()>t.started+600:raise RuntimeError('Overall deadline')
  time.sleep(.1)
 if child.returncode!=0:raise RuntimeError('Gateway acceptance failed; see retained receipt')
 state='complete_pending_review'
except BaseException as e:error=f'{type(e).__name__}: {e}'
finally:
 if child and child.poll() is None:t.terminate(child)
 t.stop.set();t.terminate()
 if thread:thread.join(timeout=6)
 after={str(p.relative_to(m.ROOT)):m.digest(p) for p in (m.ROOT/'config').rglob('*') if p.is_file() and not p.is_symlink()}
 clean=(t.proc is None or t.proc.poll() is not None) and m.closed() and (child is None or child.poll() is not None)
 if not clean or configs!=after:state='failed';error=error or 'Cleanup/protected state failed'
 t.save('samples.json',t.samples);t.save('receipt.json',{'state':state,'error':error,'elapsed_s':time.monotonic()-t.started,'cleanup':clean,'config_unchanged':configs==after,'port_closed':m.closed()})
 print(json.dumps({'state':state,'error':error,'output':str(t.out)}),flush=True)
raise SystemExit(0 if state=='complete_pending_review' else 1)
