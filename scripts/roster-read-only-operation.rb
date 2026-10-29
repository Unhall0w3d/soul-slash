#!/usr/bin/env ruby
# frozen_string_literal: true
require 'json'
require_relative '../lib/soul_core/assistant_skill_catalog'
require_relative '../lib/soul_core/repository_inspection_service'
require_relative '../lib/soul_core/host_system_status_collector'
root=File.expand_path('..',__dir__)
# No configured foreign roots or Downloads ancestors enter this bridge.
raise 'canonical project root required' unless File.realpath(root)==root && !root.start_with?('/home/bhones/Downloads/') && root!='/home/bhones/Downloads'
raise 'one operation required' unless ARGV.length==1
result=case ARGV.first
when 'host.status'
  report=SoulCore::HostSystemStatusCollector.new.collect
  {'state'=>report['ok'] ? 'complete' : 'failed','data'=>report.slice('scope','collected_at','collected','claims','not_collected','verification')}
when 'skills.list'
  report=SoulCore::AssistantSkillCatalog.new(root:root).assess
  {'state'=>report['ok'] ? 'complete' : 'failed','data'=>{
    'connected_commands'=>['host status','soul status','list skills','show approved repository roots','inspect repository root project'],
    'registered_skills'=>report.fetch('registry').fetch('skill_ids'),
    'boundary'=>'Other registered skills are not connected through this roster bridge. No arbitrary commands, file browsing, mutations or autonomous tool calls.'}}
when 'repository.roots','repository.inspect'
  service=SoulCore::RepositoryInspectionService.new(root:root,process_env:{'SOUL_REPOSITORY_INSPECT_ROOTS'=>"project=#{root}"})
  report=ARGV.first=='repository.roots' ? service.roots : service.inspect(root_id:'project')
  {'state'=>report.fetch('lifecycle_state'),'data'=>report.slice('message','data')}
else
  raise 'unsupported operation'
end
encoded=JSON.generate(result)
raise 'output bound' if encoded.bytesize>48*1024
puts encoded
