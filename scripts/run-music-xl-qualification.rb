#!/usr/bin/env ruby
# Isolated, foreground feasibility: one shared composition plan, two synthesizers.
require 'json'
require 'digest'
require 'tmpdir'
require 'time'
require_relative '../lib/soul_core/shared_compute_service'
require_relative '../lib/soul_core/creative_compute_handoff'
require_relative '../lib/soul_core/music_generation_service'
require_relative 'support/music_qualification_guard'
require_relative '../lib/soul_core/music_render_guard'
abort 'Usage: --plan|--run [acoustic|electronic|vocal|long-vocal]' unless (1..2).cover?(ARGV.size) && %w[--plan --run].include?(ARGV.first) && %w[acoustic electronic vocal long-vocal].include?(ARGV[1] || 'acoustic')
case_id=ARGV[1] || 'acoustic'
root=File.expand_path('..',__dir__)
File.umask(0077)
dir=Dir.mktmpdir('music-xl-qualification-',File.join(root,'Soul/runtime/qualification'))
manifest_path=File.join(root,'config/music_vulkan_models.json')
manifest=JSON.parse(File.read(manifest_path))
asset=JSON.parse(File.read(File.join(root,'Soul/runtime/qualification/music-xl-assets-20261027/receipt.json')))
revision=manifest.fetch('runtime').fetch('revision')
install=File.join(Dir.home,'.local/share/soul/music/acestep-cpp',revision)
control=SoulCore::SharedComputeService.new
coordinator=SoulCore::MusicResourceCoordinator.new(root:root,lane:'amd-music',shared_compute:true)
runner=SoulCore::BoundedCommandRunner.new
backend=SoulCore::MusicVulkanGenerationBackend.new(music_root:File.join(Dir.home,'.local/share/soul/music'),manifest:manifest,runner:runner)
input={'caption'=>'Warm acoustic instrumental with fingerpicked guitar, soft piano and restrained brushed drums. Begin sparsely, introduce a gentle melodic answer, and finish with a resolved chord. No singing or spoken words.',
 'lyrics'=>'[Instrumental]','bpm'=>90,'keyscale'=>'C major','timesignature'=>'4','language'=>'en','duration'=>30,'seed'=>42627,'batch_size'=>1,'inference_steps'=>8}
icd='/usr/share/vulkan/icd.d/radeon_icd.json'
if case_id=='electronic'
 input.merge!('caption'=>'Instrumental electronic groove with a steady dance beat, rounded bass, crisp hi-hats and a bright repeating synthesizer motif. Begin with drums, add the bass and melody, then end cleanly. No vocals or speech.','bpm'=>120,'keyscale'=>'A minor','seed'=>42628)
elsif %w[vocal long-vocal].include?(case_id)
 input.merge!('caption'=>'Gentle folk song with clear solo vocals, acoustic guitar, warm bass and soft brushed drums. Intimate natural delivery; clear English lyrics, no spoken introduction.','bpm'=>88,'keyscale'=>'D major','seed'=>42629,'lyrics'=>"[Verse]\nLanterns glow beside the door\nFootsteps cross the wooden floor\nRain is tapping on the pane\nWe are home again\n[Chorus]\nLet the evening settle slow\nThere is nowhere else to go\n")
end
if case_id=='long-vocal'
 input['duration']=180
 input['seed']=42630
 input['caption']='Warm melodic folk song with clear solo English vocals, fingerpicked acoustic guitar, bass, light brushed drums and subtle piano. Gentle verses build into a memorable chorus, with an instrumental bridge and a resolved ending.'
 input['lyrics']=<<~LYRICS
 [Intro]
 [Verse 1]
 Lanterns glow beside the door
 Footsteps cross the wooden floor
 Rain is tapping on the pane
 We are home again
 [Chorus]
 Let the evening settle slow
 There is nowhere else to go
 Set the heavy day aside
 There is room for you inside
 [Verse 2]
 Kettle singing on the stove
 Stories of the roads we drove
 Every mile and every bend
 Brought us home again
 [Chorus]
 Let the evening settle slow
 There is nowhere else to go
 Set the heavy day aside
 There is room for you inside
 [Instrumental Bridge]
 [Verse 3]
 Morning waits beyond the hill
 For a moment all is still
 Leave tomorrow where it lies
 Watch the fire in your eyes
 [Final Chorus]
 Let the evening settle slow
 There is nowhere else to go
 Set the heavy day aside
 There is room for you inside
 [Outro]
 We are home again
 LYRICS
end
protected=[icd,manifest_path,File.join(root,'config/visual_studio_models.json'),'/etc/lact/config.yaml']
hashes=protected.to_h { |p| [p,Digest::SHA256.file(p).hexdigest] }
raise 'LACT settings drift' unless hashes['/etc/lact/config.yaml']=='6c5be5814c9d10a79daa687249f23c5edf9400cfcb2b9d570e61afcf8df9f5e8'
receipt={'state'=>'preparing','started_at'=>Time.now.utc.iso8601,'pid'=>Process.pid,'maximum_seconds'=>900,'maximum_lm_attempts'=>1,'maximum_syntheses'=>2,'automatic_retries'=>0,'protected_hashes'=>hashes,'case'=>case_id,'input'=>input,'results'=>[]}
write=-> { File.write(File.join(dir,'receipt.json'),JSON.pretty_generate(receipt)+"\n") }
puts JSON.generate(state:'preparing',output:dir)
write.call
begin
 raise 'asset not verified' unless asset['state']=='verified_not_loaded' && asset['filename']=='acestep-v15-xl-turbo-Q8_0.gguf'
 raise 'candidate drift' unless File.size(asset.fetch('path'))==asset.fetch('bytes') && Digest::SHA256.file(asset.fetch('path')).hexdigest==asset.fetch('sha256')
 backend.verify_checkpoints!
 identity=runner.run('vulkaninfo','--summary',env:{'VK_DRIVER_FILES'=>icd,'DISPLAY'=>nil,'WAYLAND_DISPLAY'=>nil},timeout_seconds:10,max_output_bytes:32768)
 raise 'AMD-only Vulkan identity unavailable' unless identity.success? && identity.stdout.scan(/deviceName\s*=\s*(.+)/).map(&:first)==['AMD Radeon RX 6900 XT (RADV NAVI21)']
 receipt['vulkan_identity']=identity.stdout
 binaries=%w[ace-lm ace-synth].to_h { |n| p=File.join(install,'build',n);[p,Digest::SHA256.file(p).hexdigest] }
 models=File.join(dir,'models');Dir.mkdir(models)
 manifest.fetch('models').fetch('files').each { |f| File.symlink(File.join(install,'models',f.fetch('filename')),File.join(models,f.fetch('filename'))) }
 File.symlink(asset.fetch('path'),File.join(models,asset.fetch('filename')))
 receipt['packet']={'runner_sha256'=>Digest::SHA256.file(__FILE__).hexdigest,'guard'=>'production_music_render_guard' ,'input'=>input,'baseline'=>'acestep-v15-turbo-Q8_0.gguf','candidate'=>asset,'runtime_revision'=>revision,'binaries'=>binaries,'steps'=>8,'vae_chunk'=>256,'composition'=>'same retained LM codes; no extra candidate LM attempt','quality_gate'=>'human listening; no automatic model promotion','admission'=>'existing music handoff plus production AMD resource/thermal validator','power_w'=>281,'driver_file'=>icd,'paging'=>'diagnostic_only'}
 File.write(File.join(dir,'frozen-packet.json'),JSON.pretty_generate(receipt['packet'])+"\n")
 receipt['packet_sha256']=Digest::SHA256.file(File.join(dir,'frozen-packet.json')).hexdigest
 if ARGV.first=='--plan'
  receipt['state']='prepared_not_started'
 else
  deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+900
  candidate='candidate_'+SecureRandom.hex(8);project='music_'+SecureRandom.hex(8)
  digest=Digest::SHA256.hexdigest(JSON.generate(receipt['packet']))
  handoff=SoulCore::CreativeComputeHandoff.new(control:control)
  result=handoff.run(provider_id:'amd-music',request_id:candidate,project_id:project,input_digest:digest) do
   lease=nil
   begin
    lease=coordinator.acquire(project_id:project,candidate_id:candidate,input_digest:digest,ttl_seconds:1020)
    monitor_before=Dir.glob(File.join(root,'Soul/runtime/qualification/music-monitor/*.json'))
    production_guard=SoulCore::MusicRenderGuard.new(root:root,control:control)
    owned=[]
    guard=Object.new
    guard.define_singleton_method(:pids) {owned}
    guard.define_singleton_method(:samples) {
      (Dir.glob(File.join(root,'Soul/runtime/qualification/music-monitor/*.json'))-monitor_before).sort.flat_map { |p| JSON.parse(File.read(p)).fetch('samples') }
    }
    guard.define_singleton_method(:run) { |command,**options|
      production_guard.run(command,**options,on_spawn:->(pid,pgid) {owned<<pid;coordinator.attach_child(lease_id:lease.fetch('lease_id'),child_pid:pid,process_group_id:pgid)},canceled:-> {coordinator.cancellation_requested?(lease.fetch('lease_id'))})
    }
    execute=->(command,timeout,env,chdir) {
     raise 'unknown executable' unless binaries.key?(command.first)
     raise 'binary changed' unless Digest::SHA256.file(command.first).hexdigest==binaries.fetch(command.first)
     hashes.each { |p,h| raise 'protected settings changed' unless Digest::SHA256.file(p).hexdigest==h }
     left=deadline-Process.clock_gettime(Process::CLOCK_MONOTONIC);raise 'overall deadline' unless left>1
     started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
     r=guard.run(command,env:env.merge('VK_DRIVER_FILES'=>icd),chdir:chdir,timeout_seconds:[timeout,left].min,max_output_bytes:2*1024*1024)
     record={'command'=>command,'status'=>r.status,'elapsed_seconds'=>Process.clock_gettime(Process::CLOCK_MONOTONIC)-started,'exit_status'=>r.exit_status}
     receipt['results']<<record
     File.write(File.join(dir,"process-#{receipt['results'].size}.json"),JSON.pretty_generate(r.to_h))
     write.call
     r
    }
    # Restrict qualification to one LM attempt; production retry policy unchanged.
    probe_manifest=Marshal.load(Marshal.dump(manifest));probe_manifest['profile']['max_lm_attempts']=1
    probe=SoulCore::MusicVulkanGenerationBackend.new(music_root:File.join(Dir.home,'.local/share/soul/music'),manifest:probe_manifest,runner:runner)
    baseline=File.join(dir,'baseline');Dir.mkdir(baseline)
    first=probe.run(input:input,staging:baseline,execute:execute)
    raise "baseline failed: #{first.status}: #{first.stderr}" unless first.success?
    receipt['baseline_wav']=first.wav_path
    # Exact same LM-selected plan; only synthesis model and registry differ.
    xl=File.join(dir,'xl');Dir.mkdir(xl)
    request=JSON.parse(File.read(File.join(baseline,'selected-request.json')))
    request['synth_model']=asset.fetch('filename')
    request_path=File.join(xl,'request.json');File.write(request_path,JSON.pretty_generate(request)+"\n")
    env={'GGML_VK_VISIBLE_DEVICES'=>'0','LD_LIBRARY_PATH'=>File.join(install,'build')}
    second=execute.call([File.join(install,'build/ace-synth'),'--models',models,'--vae-chunk','256','--request',request_path],600,env,xl)
    raise "XL failed: #{second.status}" unless second.success?
    wavs=Dir.glob(File.join(xl,'*.wav'));raise 'expected one XL WAV' unless wavs.one?
    receipt['candidate_wav']=wavs.first
    receipt['audio']=[first.wav_path,wavs.first].map { |p|
      probe=runner.run('ffprobe','-v','error','-show_streams','-show_format','-of','json',p,timeout_seconds:10,max_output_bytes:32768)
      raise 'audio probe failed' unless probe.success?
      data=JSON.parse(probe.stdout); streams=data.fetch('streams');s=streams.first
      raise 'audio format/duration failed' unless streams.one? && s['sample_rate']=='48000' && s['channels']==2 && (Float(data.fetch('format').fetch('duration'))-input.fetch('duration')).abs<2
      {'path'=>p,'sha256'=>Digest::SHA256.file(p).hexdigest,'duration'=>data['format']['duration'],'sample_rate'=>s['sample_rate'],'channels'=>s['channels']}
    }
    {'ok'=>true,'lifecycle_state'=>'complete','reason'=>'audio generated; listening review required'}
   rescue StandardError => e
    receipt['error']="#{e.class}: #{e.message}"
    {'ok'=>false,'lifecycle_state'=>'failed','reason'=>receipt['error']}
   ensure
    if guard
     receipt['owned_pids']=guard.pids
     File.write(File.join(dir,'telemetry.json'),JSON.pretty_generate(guard.samples))
     receipt['owned_processes_gone']=guard.pids.all? { |pid| begin Process.kill(0,pid);false;rescue Errno::ESRCH;true;end }
    end
    if lease
     raise 'owned child remains; retain lease' unless receipt['owned_processes_gone']!=false
     receipt['lease_released']=coordinator.release(lease.fetch('lease_id'))
     raise 'lease release not confirmed' unless receipt['lease_released']
    end
   end
  end
  receipt['result']=result
  receipt['state']=result['ok'] ? 'generated_pending_listening_review' : 'failed'
 end
rescue StandardError => e
 receipt['state']='failed';receipt['error']="#{e.class}: #{e.message}"
ensure
 receipt['protected_unchanged']=hashes.all? { |p,h| Digest::SHA256.file(p).hexdigest==h }
 receipt['finished_at']=Time.now.utc.iso8601
 write.call
 puts JSON.generate(receipt.slice('state','error','protected_unchanged').merge('output'=>dir))
end
exit(receipt['state']=='failed' ? 1 : 0)
