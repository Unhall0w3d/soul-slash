#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "run-qwen38-adapter-trial"

# Cancel a live in-flight HTTP request, then return through the inherited
# stop/reap/lease-release path. No reply is committed and no retry follows.
class Qwen38CancellationTrial < Qwen38AdapterTrial
  def create_output = Dir.mktmpdir("qwen38-cancellation-trial-", QUALIFICATION)
  def max_generations = 1
  def extra_preflight
    super.merge("cancellation_source_sha256"=>Digest::SHA256.file(__FILE__).hexdigest,
      "cancellation_scope"=>"interrupt in-flight completion after 0.5 seconds; verify teardown separately",
      "messages"=>[{"role"=>"user","content"=>"List the integers from 1 to 1000, one per line. Do not abbreviate."}])
  end
  def probe
    adapter=SoulCore::RosterChatAdapter.new(model:@candidate,isolated:true)
    request_thread=Thread.current
    client=RosterAdapterTrial::Client.new(self)
    wrapper=Object.new
    watcher=nil
    canceled=false
    wrapper.define_singleton_method(:request) do |method,path,payload,deadline:|
      if path=="/v1/chat/completions"
        watcher=Thread.new do
          sleep 0.5
          canceled=true
          request_thread.raise(SoulCore::RosterChatExchange::Stopped,"synthetic cancellation")
        end
      end
      client.request(method,path,payload,deadline:deadline)
    end
    begin
      exchange(adapter,0,client:wrapper,cancel:-> { canceled }).call(
        messages:extra_preflight.fetch("messages"),deadline:now+request_seconds)
      raise Abort,"request finished before cancellation; test inconclusive"
    rescue SoulCore::RosterChatExchange::Stopped
      raise Abort,"unexpected pre-dispatch stop" unless canceled
      save("inflight-cancellation.json",{"state"=>"interrupted_pending_cleanup_verification",
        "final_returned_to_caller"=>false,"delay_seconds"=>0.5})
    ensure
      watcher&.kill
      watcher&.join
    end
  end
end

if $PROGRAM_NAME==__FILE__
  abort "Expected isolated cancellation flag" unless ARGV==["--approved-qwen38-cancellation-trial"]
  exit(Qwen38CancellationTrial.new.run ? 0 : 1)
end
