#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative '../lib/soul_core/cpu_member_gateway'
# Explicit local user commands only. No model proposal is passed to this CLI.
command,path=ARGV
raise ArgumentError,'usage: cpu-member-tasks.rb init|add|list|cancel|recover PRIVATE_ROOT' unless ARGV.length==2&&%w[init add list cancel recover].include?(command)
g=nil
if command=='init'
  SoulCore::CpuMemberGateway.create(path:path,owner:SoulCore::CpuMemberAdapter.new)
  puts JSON.generate('state'=>'created','path'=>path)
else
  g=SoulCore::CpuMemberGateway.new(path:path)
  if command=='list'
    result={'state'=>'complete','tasks'=>g.tasks}
  else
    bytes=STDIN.read(8193);raise ArgumentError,'input bound' if bytes.bytesize>8192
    input=JSON.parse(bytes,allow_duplicate_key:false);keys={'add'=>%w[request_id title detail member],'cancel'=>%w[request_id task_id],'recover'=>%w[request_id]}.fetch(command)
    raise ArgumentError,'exact command fields required' unless input.is_a?(Hash)&&input.keys.sort==keys.sort
    result=g.public_send({'add'=>:add_task,'cancel'=>:cancel_task,'recover'=>:recover}.fetch(command),**input.transform_keys(&:to_sym))
  end
  puts JSON.generate(result)
end
g&.close
