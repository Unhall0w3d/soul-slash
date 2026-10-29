#!/usr/bin/env ruby
# Freeze old/new CPU journal admissions before the authorized service restart.
require 'json';require 'digest';require 'fileutils';require 'open3'
require_relative '../lib/soul_core/cpu_member_gateway'
root=File.expand_path('..',__dir__);out=File.expand_path(ARGV.fetch(0));raise 'candidate path' unless File.dirname(out)==File.join(root,'Soul/runtime/qualification')&&File.basename(out).start_with?('cpu-member-a5-')
raise 'ordinary user required' if Process.uid.zero?
raise 'activation already attempted' if File.exist?(File.join(out,'activation.json')) || Dir.glob(File.join(out,'preactivation-*')).any?
File.umask(0077);candidate=JSON.parse(File.read(File.join(out,'candidate.json')))
raise 'checks not passed' unless candidate['deterministic_checks_passed']==true
candidate['source_hashes'].each{|f,h|raise 'candidate source changed' unless Digest::SHA256.file(File.join(root,f)).hexdigest==h}
state=File.join(root,'Soul/private/cpu_member_service_v1');locks=[];dirs=[];stopped=false
command=->(*args){text,status=Open3.capture2e('systemctl','--user',*args);raise "service operation failed: #{args.first}" unless status.success?;text}
begin
  parent=SoulCore::CpuMemberGateway::Directory.new(File.join(state,'conversations'));dirs<<parent;parent.lock_initialization!
  parent.children.sort.each do |name|
    raise 'unexpected conversation entry' unless /\A[a-f0-9]{64}\z/.match?(name)
    d=SoulCore::CpuMemberGateway::Directory.new(File.join(parent.path,name));dirs<<d
    f=d.open_file('lock',File::RDWR);locks<<f;raise 'active CPU conversation; no restart' unless f.flock(File::LOCK_EX|File::LOCK_NB)
    records=d.children.grep(/\Ar-\d{6}\.json\z/).sort
    raise 'unfinished CPU conversation; review before restart' if records.any? && %w[cpu_requested cpu_tool_intent].include?(d.read(records.last)['state'])
  end
  # The parent directory lock prevents new journals; every existing writer lock
  # is held. Requests not yet begun can only refuse, never begin model/task work.
  before={}
  %w[tasks conversations runs].each do |name|
    Dir.glob(File.join(state,name,'**','*.json')).each{|f|before[f.delete_prefix(state+'/')]=Digest::SHA256.file(f).hexdigest}
    FileUtils.cp_r(File.join(state,name),File.join(out,'preactivation-'+name),preserve:true)
  end
  File.write(File.join(out,'prior-journal-hashes.json'),JSON.pretty_generate(before)+"\n")
  command.call('stop','soul-cpu-member.service');stopped=true
  raise 'CPU service did not stop' unless command.call('show','soul-cpu-member.service','--property=ActiveState','--value').strip=='inactive'
  before.each{|f,h|raise 'prior journal changed' unless Digest::SHA256.file(File.join(state,f)).hexdigest==h}
  locks.each(&:close);locks=[];dirs.reverse_each(&:close);dirs=[]
  command.call('start','soul-cpu-member.service')
  command.call('restart','soul-dashboard.service')
  status=command.call('show','soul-cpu-member.service','soul-dashboard.service','--property=Id,ActiveState','--no-pager')
  raise 'activation state' unless status.scan('ActiveState=active').length==2
  before.each{|f,h|raise 'prior journal changed after start' unless Digest::SHA256.file(File.join(state,f)).hexdigest==h}
  receipt={'state'=>'complete','prior_journals_unchanged'=>true,'admission_gate'=>'directory creation lock plus every existing CPU journal writer lock','status'=>status}
  File.write(File.join(out,'activation.json'),JSON.pretty_generate(receipt)+"\n");puts JSON.generate(receipt)
rescue StandardError=>e
  File.write(File.join(out,'activation.json'),JSON.generate({'state'=>'failed','error_class'=>e.class.name,'error'=>e.message,'cpu_was_stopped'=>stopped})+"\n");raise
ensure
  locks.each{|f|f.close unless f.closed?};dirs.reverse_each(&:close)
end
