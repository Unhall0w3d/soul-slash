#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative 'activate-continuity-librechat-a24'
module CpuMemberA4LibreChat
  OLD_DESCRIPTION='CPU-only chat and scoped read-only tools. Type /task help for explicit task add/list/cancel commands. Pending tasks are recorded, not scheduled. No automatic GPU dispatch or shared-memory import. Stays in RAM after first use until stopped or a resource guard requires unloading.'
  def merge(original,staged)
    desired=staged.fetch('modelSpecs').fetch('list').fetch(0)
    raise ArgumentError unless desired['name']=='soul-member-gemma-cpu'&&desired.dig('preset','endpoint')=='SoulCPU'&&desired.dig('preset','model')=='gemma-4-e4b-cpu'&&desired.dig('preset','maxContextTokens')==4096
    expected=Marshal.load(Marshal.dump(desired));expected['description']=OLD_DESCRIPTION;expected['preset']['maxContextTokens']=65536
    copy=Marshal.load(Marshal.dump(original));rows=copy.fetch('modelSpecs').fetch('list');matches=rows.select{|r|r['name']==desired['name']}
    raise ArgumentError,'CPU preset drift' unless matches.length==1&&[expected,desired].include?(matches.first)
    rows[rows.index(matches.first)]=desired
    super(copy,staged)
  end
end
ContinuityLibreChatA24.singleton_class.prepend(CpuMemberA4LibreChat)
if $PROGRAM_NAME==__FILE__
  exit ContinuityLibreChatA24.run(staged_path:File.join(ContinuityLibreChatA24::ROOT,'docs/examples/cpu-member-librechat.yaml'))
end
