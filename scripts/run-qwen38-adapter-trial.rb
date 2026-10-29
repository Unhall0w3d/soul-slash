#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "run-qwen38-native-probe"
require_relative "run-roster-adapter-trial"

# Isolated wire-boundary acceptance; does not advertise a production model.
class Qwen38AdapterTrial < Qwen38NativeProbe
  BUDGET_SECONDS = 600
  def create_output = Dir.mktmpdir("qwen38-adapter-trial-", QUALIFICATION)
  def max_generations = 3
  def completion_state = "completed_pending_adapter_review"
  def adapter_http(path, payload, deadline:)
    remaining = deadline - now
    raise Abort, "adapter deadline exhausted" unless remaining.positive?
    response = http(path, payload, seconds: [remaining, request_seconds].min)
    raise Abort, "adapter HTTP failure" unless response.code == "200"
    JSON.parse(response.body, allow_duplicate_key: false, max_nesting: 24)
  end
  def extra_preflight
    super.merge("adapter_trial_source_sha256"=>Digest::SHA256.file(__FILE__).hexdigest,
      "adapter_sha256"=>Digest::SHA256.file(File.join(ROOT,"lib/soul_core/roster_chat_adapter.rb")).hexdigest,
      "exchange_sha256"=>Digest::SHA256.file(File.join(ROOT,"lib/soul_core/roster_chat_exchange.rb")).hexdigest,
      "messages"=>RosterAdapterTrial::TASK_MESSAGES,
      "cancellation_scope"=>"late final discarded; not active generation interruption or journal qualification")
  end
  def probe
    adapter = SoulCore::RosterChatAdapter.new(model: @candidate, isolated: true)
    RosterAdapterTrial::TASK_MESSAGES.each_with_index do |messages,index|
      result = exchange(adapter,index).call(messages:messages,deadline:now+request_seconds)
      save("answer-#{index}.json",result)
    end
    # Cancel after an actual HTTP final returns but before it can be accepted.
    # This is deliberately labeled separately from interrupting active inference.
    canceled=false
    client=RosterAdapterTrial::Client.new(self)
    wrapper=Object.new
    wrapper.define_singleton_method(:request) do |method,path,payload,deadline:|
      result=client.request(method,path,payload,deadline:deadline)
      canceled=true if path=="/v1/chat/completions"
      result
    end
    begin
      exchange(adapter,2,client:wrapper,cancel:-> { canceled }).call(
        messages:[{"role"=>"user","content"=>"Reply only: violet"}],deadline:now+request_seconds)
      raise Abort,"canceled final was accepted"
    rescue SoulCore::RosterChatExchange::Stopped
      raise Abort,"cancellation occurred before final" unless canceled
      save("late-cancellation.json",{"state"=>"passed","final_returned_to_caller"=>false})
    end
  end
  def exchange(adapter,index,client:RosterAdapterTrial::Client.new(self),cancel:-> { false })
    raise Abort,"generation ceiling" if @generation_count>=max_generations
    @generation_count+=1
    SoulCore::RosterChatExchange.new(adapter:adapter,client:client,cancel:cancel,
      admission:-> { validate_resources!(sample_resources); true },
      receipt:->(record) { save("exchange-#{index}-#{record.fetch('state')}.json",record) })
  end
end

if $PROGRAM_NAME==__FILE__
  abort "Expected isolated adapter trial flag" unless ARGV==["--approved-qwen38-adapter-trial"]
  exit(Qwen38AdapterTrial.new.run ? 0 : 1)
end
