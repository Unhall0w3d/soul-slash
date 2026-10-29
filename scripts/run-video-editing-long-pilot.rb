#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative 'run-video-editing-pilot'

# A separate fixed synthetic workload; A1's duration and command bounds stay fixed.
class VideoEditingLongPilot < VideoEditingPilot
  OVERALL_SECONDS=1200
  CHILD_SECONDS=600
  CHILD_CPU_SECONDS=1200
  SECONDS=960
  FRAMES=28_800
  INPUT=File.join(ROOT,'Soul/runtime/qualification/video-native-review-kv2l2k6y')
  def property(element,name,value)
    item=element.elements["property[@name='#{name}']"] || element.add_element('property',{'name'=>name})
    item.text=value.to_s
  end
  def self.frame(value)
    return Integer(value,10) if value.match?(/\A\d+\z/)
    raise Refused,'invalid time' unless value.match?(/\A\d\d:\d\d:\d\d\.\d{3}\z/)
    h,m,s=value.split(':');((h.to_i*3600+m.to_i*60+s.to_f)*30).round
  end
  def self.validate_template!(doc)
    p=doc.root.elements['profile']
    raise Refused,'profile changed' unless %w[width height frame_rate_num frame_rate_den colorspace].map{|k|p.attributes[k]}==%w[640 360 30 1 709]
    bin=doc.root.elements["playlist[@id='main_bin']"]
    raise Refused,'native mixer changed' unless bin.elements["property[@name='kdenlive:docproperties.audioChannels']"].text=='2'
    %w[playlist0 playlist4].each do |id|
      list=doc.root.elements["playlist[@id='#{id}']"]
      raise Refused,'timeline gap' unless list.get_elements('blank').empty?
      raise Refused,'cut ranges changed' unless list.get_elements('entry').map{|e|[frame(e.attributes['in']),frame(e.attributes['out'])]}==[[30,149],[210,329]]
    end
    clips=%w[review_clip0 review_clip1].map{|id|doc.root.elements["chain[@id='#{id}']"]}
    raise Refused,'caption identities merged' unless clips.map{|c|c.elements["property[@name='kdenlive:id']"].text}.uniq.length==2
    raise Refused,'caption changed' unless clips.map{|c|c.elements["filter/property[@name='argument']"].text}==['CUT 1 | SOURCE 01-05 SECONDS','CUT 2 | SOURCE 07-11 SECONDS']
    doc.root.get_elements('chain').each do |c|
      raise Refused,'unexpected media resource' unless c.elements["property[@name='resource']"].text=='original.mkv'
    end
    true
  end
  def run
    raise Refused,'existing attempt' if File.exist?(path('intent.json'))
    inputs=%w[pilot.kdenlive original.mkv original-backup.mkv reference.mkv]
    @input_hashes=inputs.to_h do |n|
      source=File.join(INPUT,n)
      raise Refused,'unsafe source' unless File.file?(source)&&!File.symlink?(source)
      [n,self.class.digest(source)]
    end
    manifest=JSON.parse(File.read(File.join(INPUT,'manifest.json')))
    raise Refused,'source backup mismatch' unless @input_hashes['original.mkv']==manifest['source_sha256']&&@input_hashes['original-backup.mkv']==manifest['source_sha256']
    doc=REXML::Document.new(File.read(File.join(INPUT,'pilot.kdenlive')))
    self.class.validate_template!(doc)
    json('intent.json',{'state'=>'consumed','input_hashes'=>@input_hashes,'seconds'=>SECONDS,'frames'=>FRAMES,'cuts'=>240,'automatic_retry'=>false})
    %w[config cache mlt-plugins].each{|n|Dir.mkdir(path(n),0700)}
    Dir.children(File.join(INPUT,'mlt-plugins')).each do |n|
      source=File.realpath(File.join(INPUT,'mlt-plugins',n))
      raise Refused,'unexpected plugin' unless source.start_with?('/usr/lib/mlt-7/')
      File.symlink(source,File.join(path('mlt-plugins'),n))
    end
    %w[original.mkv original-backup.mkv reference.mkv].each do |n|
      write(n,File.binread(File.join(INPUT,n)))
      File.chmod(0444,path(n))
    end
    doc.root.attributes['root']=@root
    bin=doc.root.elements["playlist[@id='main_bin']"]
    sequence=doc.root.get_elements('tractor').find{|t|t.elements["property[@name='kdenlive:uuid']"]}
    old=sequence.attributes['id'];uuid='{'+SecureRandom.uuid+'}'
    doc.root.each_recursive do |e|
      e.attributes['producer']=uuid if e.attributes['producer']==old
      e.text=uuid if e.name=='property'&&e.text==old
    end
    sequence.attributes['id']=uuid
    property(bin,'kdenlive:docproperties.documentid',Time.now.to_i)
    property(sequence,'kdenlive:clipname','Soul sixteen-minute synthetic edit')
    %w[kdenlive:maxduration kdenlive:zone_out kdenlive:sequenceproperties.zoneout].each{|k|property(sequence,k,FRAMES)}
    property(sequence,'kdenlive:duration','00:16:00.000')
    %w[playlist0 playlist4].each do |id|
      list=doc.root.elements["playlist[@id='#{id}']"]
      entries=list.get_elements('entry').map(&:deep_clone)
      list.get_elements('entry').each{|e|list.delete_element(e)}
      120.times{entries.each{|e|list.add_element(e.deep_clone)}}
    end
    [sequence,doc.root.elements['producer'],doc.root.get_elements('tractor').last,doc.root.get_elements('tractor').last.elements['track'],bin.get_elements('entry').find{|e|e.attributes['producer']==uuid}].each{|e|e.attributes['out']=(FRAMES-1).to_s}
    serialized=String.new;REXML::Formatters::Default.new.write(doc,serialized);write('pilot.kdenlive',serialized)
    command('/usr/bin/melt',path('pilot.kdenlive'),'-consumer',"avformat:#{path('preview.mp4')}",'vcodec=libx264','acodec=aac','crf=18','preset=fast','threads=2','real_time=-2','pix_fmt=yuv420p','ar=48000','channels=1','movflags=+faststart','-silent')
    probe=JSON.parse(command('/usr/bin/ffprobe','-v','error','-count_frames','-show_streams','-of','json',path('preview.mp4')).stdout)
    v=probe['streams'].find{|x|x['codec_type']=='video'};a=probe['streams'].find{|x|x['codec_type']=='audio'}
    raise Refused,'long duration/profile mismatch' unless v&&a&&v['nb_read_frames']==FRAMES.to_s&&v['width']==640&&v['height']==360&&v['avg_frame_rate']=='30/1'&&(v['duration'].to_f-SECONDS).abs<=1.0/30&&(a['duration'].to_f-SECONDS).abs<=1.0/30
    samples=[0,472,952].map do |offset|
      score=command('/usr/bin/ffmpeg','-hide_banner','-nostdin','-threads','2','-i',path('reference.mkv'),'-ss',offset.to_s,'-threads','2','-i',path('preview.mp4'),'-filter_complex_threads','1','-filter_complex','[0:v]crop=640:270:0:0[r];[1:v]crop=640:270:0:0[p];[r][p]ssim','-t','8','-an','-f','null','-').stderr[/All:([0-9.]+)/,1].to_f
      raise Refused,'sample reference mismatch' unless score>=0.97
      command('/usr/bin/ffmpeg','-hide_banner','-loglevel','error','-nostdin','-n','-ss',offset.to_s,'-threads','2','-i',path('preview.mp4'),'-t','8','-filter_threads','1','-vf','crop=24:24:0:0,scale=1:1','-an','-pix_fmt','rgb24','-f','rawvideo',path("flashes-#{offset}.rgb"))
      command('/usr/bin/ffmpeg','-hide_banner','-loglevel','error','-nostdin','-n','-ss',offset.to_s,'-threads','2','-i',path('preview.mp4'),'-t','8','-vn','-ac','1','-ar','48000','-c:a','pcm_s16le','-f','s16le',path("audio-#{offset}.pcm"))
      flash=File.binread(path("flashes-#{offset}.rgb")).bytes.each_slice(3).map{|rgb|rgb.sum/3.0>220}
      audio=File.binread(path("audio-#{offset}.pcm")).unpack('s<*').each_slice(1600).map{|xs|Math.sqrt(xs.sum{|x|x*x}.to_f/xs.length)/32768>0.025}
      starts=->(xs){xs.each_index.select{|i|xs[i]&&(i==0||!xs[i-1])}}
      vs=starts.call(flash);as=starts.call(audio)
      raise Refused,'sample A/V alignment' unless vs==(0...240).step(30).to_a&&as.length==8&&vs.zip(as).all?{|x,y|(x-y).abs<=1}
      {offset_seconds:offset,ssim:score,maximum_marker_offset_frames:vs.zip(as).map{|x,y|(x-y).abs}.max}
    end
    command('/usr/bin/ffmpeg','-hide_banner','-loglevel','error','-nostdin','-n','-threads','2','-i',path('preview.mp4'),'-filter_threads','1','-vf','select=eq(n\,30)+eq(n\,150)+eq(n\,14190)+eq(n\,14310)+eq(n\,28590)+eq(n\,28710),tile=2x3','-frames:v','1','-threads','1',path('contact-sheet.png'))
    raise Refused,'input changed during run' unless @input_hashes.all?{|n,h|self.class.digest(File.join(INPUT,n))==h}
    json('receipt.json',{'state'=>'complete','human_review'=>'pending','seconds'=>SECONDS,'frames'=>FRAMES,'samples'=>samples,'source_unchanged'=>true,'commands'=>@commands,'outputs'=>%w[pilot.kdenlive preview.mp4 contact-sheet.png].to_h{|n|[n,self.class.digest(path(n))]}})
  rescue StandardError,SignalException=>error
    record_failure(error);raise
  end
end
if $PROGRAM_NAME==__FILE__
  abort 'usage: run-video-editing-long-pilot.rb --run' unless ARGV==['--run']
  File.umask(0077);root=Dir.mktmpdir('video-editing-a2-',File.join(VideoEditingPilot::ROOT,'Soul/runtime/qualification'))
  puts JSON.generate(state:'starting',output:root);$stdout.flush
  begin
    VideoEditingLongPilot.new(root).run
    puts JSON.generate(state:'complete',output:root,human_review:'pending')
  rescue StandardError,SignalException=>error
    puts JSON.generate(state:'failed',error_class:error.class.name,reason:error.message,output:root);exit 1
  end
end
