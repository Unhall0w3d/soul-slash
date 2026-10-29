#!/usr/bin/env python3
"""CPU-only owned runtime. Parent loss, resource failure or TERM stops the model."""
import importlib.util,pathlib,json,os,subprocess,time,signal,sys
spec=importlib.util.spec_from_file_location('a1',pathlib.Path(__file__).with_name('run-cpu-member-trial.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def main(output,parent):
 os.umask(0o077); output=pathlib.Path(output); proc=None; stopped=False; error=None
 def stop(sig,frame):
  nonlocal stopped
  stopped=True
 signal.signal(signal.SIGINT,stop);signal.signal(signal.SIGTERM,stop)
 def save(name,value):
  temp=output/(name+'.tmp');temp.write_text(json.dumps(value)+'\n');temp.replace(output/name)
 try:
  if os.getuid()==0 or os.getppid()!=parent:raise RuntimeError('Ordinary owned runtime required')
  if not m.closed():raise RuntimeError('CPU port occupied')
  m.validate(m.resources())
  manifest=json.loads((m.ASSETS/'verification.json').read_text())
  for name,sha in manifest['runtime_files'].items():
   if m.digest(m.BUILD/'bin'/name)!=sha:raise RuntimeError('Runtime changed')
  name,sha,size=m.MODELS['gemma'];model=m.ASSETS/name
  if model.stat().st_size!=size or m.digest(model)!=sha:raise RuntimeError('Artifact changed')
  if stopped or os.getppid()!=parent:raise RuntimeError('Canceled before launch')
  argv=[str(m.BUILD/'bin/llama-server'),'-m',str(model),'--alias','gemma-4-e4b-cpu','--host','127.0.0.1','--port',str(m.PORT),'--device','none','--gpu-layers','0','--jinja','--ctx-size','4096','--parallel','1','--threads','6','--threads-batch','6','--batch-size','256','--ubatch-size','64','--no-context-shift','--no-warmup','--fit','off','--reasoning-format','deepseek','--reasoning','off','--slots']
  env={k:v for k,v in os.environ.items() if not k.startswith(('LLAMA_','GGML_','CUDA_','HIP_','ROCR_'))};env['CUDA_VISIBLE_DEVICES']='';env['HIP_VISIBLE_DEVICES']=''
  with open(output/'server.log','xb') as log:proc=subprocess.Popen(argv,stdout=log,stderr=subprocess.STDOUT,env=env,start_new_session=True)
  save('identity.json',{'pid':proc.pid,'parent':parent,'argv':argv})
  count=0;peaks={'cpu_c':0,'rss_bytes':0,'available_bytes':2**63,'gpu_fds':[]}
  while not stopped:
   if os.getppid()!=parent:raise RuntimeError('Parent exited')
   if proc.poll() is not None:raise RuntimeError('Model exited')
   r=m.resources(proc.pid);m.validate(r)
   peaks['cpu_c']=max(peaks['cpu_c'],r['cpu_c']);peaks['rss_bytes']=max(peaks['rss_bytes'],r['rss_bytes']);peaks['available_bytes']=min(peaks['available_bytes'],r['available_bytes'])
   save('status.json',{'state':'running','pid':proc.pid,'sampled_at':time.time(),'resources':r,'peaks':peaks})
   if (output/'server.log').stat().st_size>32*1024**2:raise RuntimeError('Log bound')
   time.sleep(.5)
 except BaseException as e:error=type(e).__name__+': '+str(e)
 finally:
  if proc and proc.poll() is None:
   os.killpg(proc.pid,signal.SIGTERM)
   try:proc.wait(timeout=5)
   except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.wait(timeout=5)
  save('receipt.json',{'state':'failed' if error else 'complete','error':error,'owned_process_exited':proc is None or proc.poll() is not None,'port_closed':m.closed()})
 return 1 if error else 0
if __name__=='__main__':
 if len(sys.argv)!=3:raise SystemExit('Expected private output and parent PID')
 raise SystemExit(main(sys.argv[1],int(sys.argv[2])))
