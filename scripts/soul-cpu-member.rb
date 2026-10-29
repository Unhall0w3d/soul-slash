#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative '../lib/soul_core/cpu_member_service'
require_relative '../lib/soul_core/roster_chat_server'
require_relative 'continuity-lab-chat'
raise 'ordinary user only' if Process.uid.zero?
abort 'Expected --serve PRIVATE_ROOT' unless ARGV.length==2&&ARGV[0]=='--serve'
File.umask(0077)
root=File.expand_path(ARGV[1]);parent=SoulCore::CpuMemberGateway::Directory.new(File.dirname(root))
Dir.mkdir(parent.anchor(File.basename(root)),0700) unless parent.children.include?(File.basename(root));parent.close
backend=SoulCore::CpuMemberService.new(path:root,assistance:true,scoped_memory:true,operations:true,creative_previews:true,creative_execution:true,references:true)
token=SoulCore::ContinuityLab::ChatCLI.read_key('/home/bhones/.config/soul/continuity-a24.key')
app=SoulCore::CpuMemberApplication.new(backend:backend,bearer_token:token);token.clear
server=SoulCore::RosterChatServer.new(host:'127.0.0.1',port:8097,application:app)
stopping=false
monitor=Thread.new do
  until stopping
    sleep 0.5
    backend.tick
  end
rescue StandardError=>e
  warn JSON.generate(state:'failed',error_class:e.class.name);server.stop
end
begin
  server.run
ensure
  stopping=true;server.stop;monitor.join(3);backend.close
end
