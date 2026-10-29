#!/usr/bin/env ruby
# frozen_string_literal: true
require 'json'
require 'digest'
require 'fileutils'
require 'tmpdir'
require 'securerandom'
require 'rexml/document'
require_relative '../lib/soul_core/bounded_command_runner'

class VideoEditingPilot
  ROOT=File.expand_path('..',__dir__)
  FONT='/usr/share/fonts/TTF/DejaVuSans.ttf'
  FPS=30
  OVERALL_SECONDS=600
  CHILD_SECONDS=120
  CHILD_CPU_SECONDS=120
  OUTPUTS=%w[pilot.kdenlive preview.mp4 reference.mkv contact-sheet.png verification.json].freeze
  class Refused < StandardError;end
  def self.digest(path)=Digest::SHA256.file(path).hexdigest
  def self.validate_plan!(p)
    raise Refused,'plan shape' unless p.is_a?(Hash)&&p.keys.sort==%w[cuts fps source source_sha256 version]&&p['version']==1&&p['source']=='original.mkv'&&p['fps']==FPS&&p['source_sha256'].is_a?(String)&&p['source_sha256'].match?(/\A[0-9a-f]{64}\z/)
    raise Refused,'cut count' unless p['cuts'].is_a?(Array)&&p['cuts'].size==2
    p['cuts'].each do |c|
      raise Refused,'cut shape' unless c.is_a?(Hash)&&c.keys.sort==%w[in out title]&&[c['in'],c['out']].all?{|x|x.is_a?(Integer)}&&c['in']>=0&&c['out']>c['in']&&c['out']<=360&&c['title'].is_a?(String)&&c['title'].match?(/\A[A-Za-z0-9 |:.\-]{1,64}\z/)
    end
    raise Refused,'duration bound' unless p['cuts'].sum{|c|c['out']-c['in']}==240
    p
  end
  def initialize(root,runner:SoulCore::BoundedCommandRunner.new)
    @root=File.expand_path(root);raise Refused,'unsafe root' unless File.realpath(@root)==@root&&File.stat(@root).uid==Process.uid&&(File.stat(@root).mode&0077).zero?
    @runner=runner;@deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+self.class::OVERALL_SECONDS;@commands=[]
  end
  def path(name)
    raise Refused,'fixed filename required' unless name.is_a?(String)&&!%w[. ..].include?(name)&&name.match?(/\A[a-zA-Z0-9_.-]+\z/)
    p=File.join(@root,name);raise Refused,'symlink refused' if File.symlink?(p);p
  end
  def write(name,body)
    File.open(path(name),File::WRONLY|File::CREAT|File::EXCL,0600){|f|f.write(body)}
  end
  def json(name,data)=write(name,JSON.pretty_generate(data))
  def command(*args)
    remaining=@deadline-Process.clock_gettime(Process::CLOCK_MONOTONIC);raise Refused,'pilot deadline' unless remaining>0
    env={'QT_QPA_PLATFORM'=>'offscreen','QT_QUICK_BACKEND'=>'software','LIBGL_ALWAYS_SOFTWARE'=>'1','CUDA_VISIBLE_DEVICES'=>'','DISPLAY'=>nil,'WAYLAND_DISPLAY'=>nil,'MLT_REPOSITORY'=>File.join(@root,'mlt-plugins'),'MLT_DATA'=>'/usr/share/mlt-7','XDG_CONFIG_HOME'=>File.join(@root,'config'),'XDG_CACHE_HOME'=>File.join(@root,'cache'),'LC_ALL'=>'C','OMP_NUM_THREADS'=>'2'}
    peak_kib=0
    monitor=lambda do |pid|
      begin
        status=File.read("/proc/#{pid}/status")
      rescue Errno::ENOENT
        next
      end
      next if status.match?(/^State:\s+[ZX]/)
      rss=status[/^VmRSS:\s+(\d+)/,1];raise Refused,'child memory telemetry unavailable' unless rss
      peak_kib=[peak_kib,rss.to_i].max;raise Refused,'child memory bound' if peak_kib>1_048_576
    end
    result=@runner.run('/usr/bin/prlimit','--core=0','--fsize=268435456',"--cpu=#{self.class::CHILD_CPU_SECONDS}",'--','/usr/bin/nice','-n','10',*args,timeout_seconds:[self.class::CHILD_SECONDS,remaining].min,max_output_bytes:262144,chdir:@root,env:env,monitor:monitor)
    index=@commands.length;@commands<<{argv:args,status:result.status,exit_status:result.exit_status,truncated:result.truncated,peak_rss_kib:peak_kib}
    write("command-#{index}.log",result.stdout+"\n"+result.stderr)
    raise Refused,"command #{index} #{result.status}" unless result.success?&&!result.truncated
    result
  end
  def record_failure(error)
    json('failure.json',{'state'=>error.is_a?(SignalException) ? 'canceled' : 'failed','error_class'=>error.class.name,'reason'=>error.message,'commands'=>@commands}) unless File.exist?(path('failure.json'))
  end
  def run
    setup
    result=render
    raise Refused,'replay verification failed' unless render['replayed']
    result
  rescue StandardError,SignalException=>error
    record_failure(error)
    raise
  end
  def setup
    %w[mlt-plugins config cache].each{|d|Dir.mkdir(File.join(@root,d),0700)}
    %w[avformat core plus qt6 resample xml kdenlive].each do |n|
      target="/usr/lib/mlt-7/libmlt#{n}.so";raise Refused,'missing native MLT plugin' unless File.file?(target)
      File.symlink(target,File.join(@root,'mlt-plugins',File.basename(target)))
    end
    video="color=c=0x142a44:s=640x360:r=30:d=12,drawbox=x=0:y=0:w=iw:h=ih:color=0x155e63:t=fill:enable='between(t,4,7.999)',drawbox=x=0:y=0:w=iw:h=ih:color=0x684324:t=fill:enable='gte(t,8)',drawtext=fontfile=#{FONT}:text='SOUL  |  EDITING PILOT':x=32:y=55:fontsize=29:fontcolor=white,drawtext=fontfile=#{FONT}:text='SOURCE FRAME %{n}':x=32:y=110:fontsize=24:fontcolor=white,drawtext=fontfile=#{FONT}:text='12 seconds - 30 fps - synthetic footage':x=32:y=160:fontsize=20:fontcolor=white,drawbox=x=0:y=0:w=24:h=24:color=white:t=fill:enable='lt(mod(t,1),0.1)'"
    audio='aevalsrc=if(lt(mod(t\,1)\,0.1)\,0.15*sin(2*PI*1000*t)\,0):s=48000:d=12'
    command('/usr/bin/ffmpeg','-hide_banner','-loglevel','error','-nostdin','-n','-filter_threads','1','-f','lavfi','-i',video,'-f','lavfi','-i',audio,'-map','0:v','-map','1:a','-c:v','ffv1','-threads','2','-pix_fmt','yuv420p','-c:a','pcm_s16le','-t','12',path('original.mkv'))
    File.open(path('original-backup.mkv'),File::WRONLY|File::CREAT|File::EXCL,0600){|out|File.open(path('original.mkv'),'rb'){|input|IO.copy_stream(input,out)}};hash=self.class.digest(path('original.mkv'));raise Refused,'backup mismatch' unless self.class.digest(path('original-backup.mkv'))==hash
    %w[original.mkv original-backup.mkv].each{|n|File.chmod(0444,path(n))}
    plan={'version'=>1,'source'=>'original.mkv','source_sha256'=>hash,'fps'=>30,'cuts'=>[{'in'=>30,'out'=>150,'title'=>'CUT 1 | SOURCE 01-05 SECONDS'},{'in'=>210,'out'=>330,'title'=>'CUT 2 | SOURCE 07-11 SECONDS'}]}
    self.class.validate_plan!(plan);json('plan.json',plan);json('manifest.json',{'source_sha256'=>hash,'plan_sha256'=>self.class.digest(path('plan.json'))})
  end
  def checked_plan
    m=JSON.parse(File.read(path('manifest.json')));p=self.class.validate_plan!(JSON.parse(File.read(path('plan.json'))))
    raise Refused,'stale plan or source' unless self.class.digest(path('plan.json'))==m['plan_sha256']&&p['source_sha256']==m['source_sha256']&&%w[original.mkv original-backup.mkv].all?{|n|self.class.digest(path(n))==m['source_sha256']}
    p
  end
  def replay
    checked_plan
    r=JSON.parse(File.read(path('receipt.json')))
    raise Refused,'receipt or artifact drift' unless r['state']=='complete'&&r['plan_sha256']==self.class.digest(path('plan.json'))&&r.fetch('outputs').keys.sort==OUTPUTS.sort&&r.fetch('outputs').all?{|n,h|self.class.digest(path(n))==h}
    r.merge('replayed'=>true)
  end
  def project(plan, filename: 'pilot.kdenlive')
    doc=REXML::Document.new;doc<<REXML::XMLDecl.new('1.0','UTF-8');mlt=doc.add_element('mlt',{'producer'=>'main_bin','version'=>'7.42.0','LC_NUMERIC'=>'C','root'=>@root})
    mlt.add_element('profile',{'description'=>'Soul 360p30 pilot','width'=>'640','height'=>'360','frame_rate_num'=>'30','frame_rate_den'=>'1','progressive'=>'1','sample_aspect_num'=>'1','sample_aspect_den'=>'1','display_aspect_num'=>'16','display_aspect_den'=>'9','colorspace'=>'709'})
    prop=->(e,n,v){e.add_element('property',{'name'=>n}).text=v.to_s}
    black=mlt.add_element('producer',{'id'=>'black_track','in'=>'0','out'=>'239'});prop.call(black,'mlt_service','color');prop.call(black,'resource','0');prop.call(black,'length',240);prop.call(black,'kdenlive:playlistid','black_track')
    # Kdenlive excludes its background by this marker; otherwise it treats color 0 as an orphan clip.
    source_control_uuid='{'+SecureRandom.uuid+'}'
    %w[source clip0 clip1].each do |id|
      e=mlt.add_element('chain',{'id'=>id,'in'=>'0','out'=>'359'});{'mlt_service'=>'avformat','resource'=>'original.mkv','kdenlive:id'=>'1','kdenlive:clipname'=>'Original synthetic source','kdenlive:control_uuid'=>source_control_uuid,'audio_index'=>'1','video_index'=>'0','threads'=>'2','hwaccel'=>'none'}.each{|k,v|prop.call(e,k,v)}
      next if id=='source'
      cut=plan['cuts'][id[-1].to_i];f=e.add_element('filter',{'in'=>cut['in'].to_s,'out'=>(cut['out']-1).to_s})
      {'mlt_service'=>'dynamictext','kdenlive:id'=>'dynamictext','argument'=>cut['title'],'geometry'=>'24 290 592 50','family'=>'DejaVu Sans','size'=>'22','weight'=>'700','fgcolour'=>'#ffffffff','bgcolour'=>'#90000000','outlinewidth'=>'0','halign'=>'center','valign'=>'middle'}.each{|k,v|prop.call(f,k,v)}
    end
    %w[a v].each do |type|
      list=mlt.add_element('playlist',{'id'=>"#{type}0"})
      plan['cuts'].each_with_index{|c,i|e=list.add_element('entry',{'producer'=>type=='a' ? 'source' : "clip#{i}",'in'=>c['in'].to_s,'out'=>(c['out']-1).to_s});prop.call(e,'kdenlive:id',1)}
      mlt.add_element('playlist',{'id'=>"#{type}1"})
      track=mlt.add_element('tractor',{'id'=>"#{type}track",'in'=>'0','out'=>'239'});prop.call(track,'kdenlive:track_name',type=='a' ? 'A1 - sync tone' : 'V1 - edited footage');prop.call(track,'kdenlive:audio_track',1) if type=='a'
      2.times{|i|track.add_element('track',{'producer'=>"#{type}#{i}",'hide'=>type=='a' ? 'video' : 'audio'})}
    end
    uuid='{'+SecureRandom.uuid+'}';seq=mlt.add_element('tractor',{'id'=>'sequence','in'=>'0','out'=>'239'})
    {'kdenlive:uuid'=>uuid,'kdenlive:control_uuid'=>'{'+SecureRandom.uuid+'}','kdenlive:id'=>'2','kdenlive:clipname'=>'Soul eight-second edit','kdenlive:duration'=>'240','kdenlive:maxduration'=>'240','kdenlive:sequenceproperties.activeTrack'=>'1','kdenlive:sequenceproperties.groups'=>'[]'}.each{|k,v|prop.call(seq,k,v)}
    seq.add_element('track',{'producer'=>'black_track'});seq.add_element('track',{'producer'=>'atrack','hide'=>'video'});seq.add_element('track',{'producer'=>'vtrack','hide'=>'audio'})
    [['mix',1],['qtblend',2]].each{|service,b|t=seq.add_element('transition',{'in'=>'0','out'=>'239'});{'mlt_service'=>service,'a_track'=>0,'b_track'=>b,'always_active'=>1,'sum'=>1,'internal_added'=>237}.each{|k,v|prop.call(t,k,v)}}
    # The editor retrieves its bin from MLT's retained services, not just XML nodes.
    bin=mlt.add_element('playlist',{'id'=>'main_bin'});{'xml_retain'=>1,'kdenlive:docproperties.version'=>'1.1','kdenlive:docproperties.kdenliveversion'=>'26.08.2','kdenlive:docproperties.documentid'=>Time.now.to_i,'kdenlive:docproperties.activeTimeline'=>uuid,'kdenlive:docproperties.uuid'=>'{'+SecureRandom.uuid+'}','kdenlive:docproperties.profile'=>'','kdenlive:docproperties.groups'=>'[]'}.each{|k,v|prop.call(bin,k,v)}
    bin.add_element('entry',{'producer'=>'source','in'=>'0','out'=>'359'});bin.add_element('entry',{'producer'=>'sequence','in'=>'0','out'=>'239'})
    wrapper=mlt.add_element('tractor',{'id'=>'maintractor','in'=>'0','out'=>'239'});prop.call(wrapper,'kdenlive:projectTractor',1);wrapper.add_element('track',{'producer'=>'sequence'})
    out=+'';REXML::Formatters::Default.new.write(doc,out);write(filename,out)
  end
  def render
    p=checked_plan;return replay if File.exist?(path('receipt.json'))
    raise Refused,'attempt consumed; no automatic retry' if File.exist?(path('intent.json'))
    %w[pilot.kdenlive preview.mp4 reference.mkv].each{|n|raise Refused,'output exists' if File.exist?(path(n))}
    json('intent.json',{'plan_sha256'=>self.class.digest(path('plan.json')),'started_at'=>Time.now.utc.to_s});project(p)
    cuts=p['cuts'];f="[0:v]split=2[v0][v1];[0:a]asplit=2[a0][a1];"
    cuts.each_with_index{|c,i|f+="[v#{i}]trim=start_frame=#{c['in']}:end_frame=#{c['out']},setpts=PTS-STARTPTS[x#{i}];[a#{i}]atrim=start_sample=#{c['in']*1600}:end_sample=#{c['out']*1600},asetpts=PTS-STARTPTS[y#{i}];"}
    f+='[x0][y0][x1][y1]concat=n=2:v=1:a=1[v][a]'
    command('/usr/bin/ffmpeg','-hide_banner','-loglevel','error','-nostdin','-n','-hwaccel','none','-threads','2','-i',path('original.mkv'),'-filter_complex_threads','1','-filter_complex',f,'-map','[v]','-map','[a]','-c:v','ffv1','-threads','2','-c:a','pcm_s16le',path('reference.mkv'))
    command('/usr/bin/melt',path('pilot.kdenlive'),'-consumer',"avformat:#{path('preview.mp4')}",'vcodec=libx264','acodec=aac','crf=18','preset=fast','threads=2','real_time=-2','pix_fmt=yuv420p','ar=48000','channels=1','movflags=+faststart','-silent')
    verification=verify
    checked_plan
    command('/usr/bin/ffmpeg','-hide_banner','-loglevel','error','-nostdin','-n','-hwaccel','none','-threads','2','-i',path('preview.mp4'),'-filter_threads','1','-vf','select=eq(n\,30)+eq(n\,100)+eq(n\,140)+eq(n\,200),tile=2x2','-frames:v','1','-threads','1',path('contact-sheet.png'))
    json('verification.json',verification)
    outputs=OUTPUTS.to_h{|n|[n,self.class.digest(path(n))]}
    r={'state'=>'complete','plan_sha256'=>self.class.digest(path('plan.json')),'replayed'=>false,'human_review'=>'pending','kdenlive_gui_editing'=>'not_verified','outputs'=>outputs,'source_unchanged'=>true,'commands'=>@commands};json('receipt.json',r);r
  rescue StandardError,SignalException=>e
    record_failure(e)
    raise
  end
  def verify
    probe=JSON.parse(command('/usr/bin/ffprobe','-v','error','-count_frames','-show_streams','-show_format','-of','json',path('preview.mp4')).stdout)
    v=probe['streams'].find{|s|s['codec_type']=='video'};a=probe['streams'].find{|s|s['codec_type']=='audio'}
    raise Refused,'frame/profile mismatch' unless v&&a&&v['nb_read_frames']=='240'&&v['width']==640&&v['height']==360&&v['avg_frame_rate']=='30/1'&&(a['duration'].to_f-8).abs<=1.0/30
    ssim=command('/usr/bin/ffmpeg','-hide_banner','-nostdin','-threads','2','-i',path('reference.mkv'),'-threads','2','-i',path('preview.mp4'),'-filter_complex_threads','1','-filter_complex','[0:v]crop=640:270:0:0[r];[1:v]crop=640:270:0:0[p];[r][p]ssim','-an','-f','null','-').stderr[/All:([0-9.]+)/,1].to_f
    raise Refused,'reference image mismatch' unless ssim>=0.97
    command('/usr/bin/ffmpeg','-hide_banner','-loglevel','error','-nostdin','-n','-threads','2','-i',path('preview.mp4'),'-filter_threads','1','-vf','crop=24:24:0:0,scale=1:1','-an','-pix_fmt','rgb24','-f','rawvideo',path('flashes.rgb'))
    command('/usr/bin/ffmpeg','-hide_banner','-loglevel','error','-nostdin','-n','-threads','2','-i',path('preview.mp4'),'-vn','-ac','1','-ar','48000','-c:a','pcm_s16le','-f','s16le',path('audio.pcm'))
    flashes=File.binread(path('flashes.rgb')).bytes.each_slice(3).map{|rgb|rgb.sum/3.0>220}
    audio=File.binread(path('audio.pcm')).unpack('s<*').each_slice(1600).map{|s|Math.sqrt(s.sum{|x|x*x}.to_f/s.length)/32768>0.025}
    starts=->(xs){xs.each_index.select{|i|xs[i]&&(i==0||!xs[i-1])}}
    vs=starts.call(flashes);as=starts.call(audio)
    raise Refused,'A/V marker mismatch' unless vs==(0...240).step(30).to_a&&as.length==8&&vs.zip(as).all?{|x,y|(x-y).abs<=1}
    {'frames'=>240,'fps'=>30,'video_seconds'=>v['duration'].to_f,'audio_seconds'=>a['duration'].to_f,'reference_ssim_top_270_rows'=>ssim,'video_marker_frames'=>vs,'audio_marker_frames'=>as,'maximum_marker_offset_frames'=>vs.zip(as).map{|x,y|(x-y).abs}.max}
  end
end
if $PROGRAM_NAME==__FILE__
  abort 'usage: run-video-editing-pilot.rb --run' unless ARGV==['--run']
  File.umask(0077);root=Dir.mktmpdir('video-editing-a1-',File.join(VideoEditingPilot::ROOT,'Soul/runtime/qualification'));puts JSON.generate(state:'starting',output:root);$stdout.flush
  begin
    result=VideoEditingPilot.new(root).run
    puts JSON.generate(state:result['state'],output:root,human_review:'pending')
  rescue StandardError,SignalException=>error
    puts JSON.generate(state:error.is_a?(SignalException) ? 'canceled' : 'failed',error_class:error.class.name,reason:error.message,output:root)
    exit(error.is_a?(SignalException) ? 130 : 1)
  end
end
