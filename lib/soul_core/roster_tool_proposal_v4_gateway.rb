# frozen_string_literal: true
require_relative 'roster_tool_proposal_v3_gateway'
require_relative 'roster_final_format_memory_exchange'
module SoulCore
  # Native final grammar is separate from application scope/dispatch validation.
  class RosterToolProposalV4Gateway < RosterToolProposalV3Gateway
    def self.manifest(owner)
      super.merge('version'=>'roster_tool_proposal_v4',
        'proposal_v4_implementation'=>%w[roster_tool_proposal_v4_gateway.rb roster_final_format_memory_exchange.rb roster_final_format_exchange.rb roster_gpt_final_format.rb].to_h{|n|[n,Digest::SHA256.file(File.join(__dir__,n)).hexdigest]})
    end
    def complete(conversation_id:, request_id:, adapter:, messages:, deadline:, cancel: -> { false })
      operation=RosterSourceExcerptSkills.operation(messages.is_a?(Array) && messages.last.is_a?(Hash) ? messages.last['content'] : nil)
      return super if operation
      unless [conversation_id, request_id].all? { |s| s.is_a?(String) && ID.match?(s) } && adapter.instance_of?(RosterChatAdapter)
        raise Refused, "bounded identities and explicit adapter required"
      end
      ContinuityLab::ChatGateway.validate_input!(conversation_id, messages)
      input = JSON.parse(JSON.generate({ "conversation_id" => conversation_id, "request_id" => request_id,
        "adapter" => adapter.binding, "messages" => messages }))
      locked = @mutex.try_lock
      raise Refused, "conversation writer busy" unless locked
      file_locked = @lock.flock(File::LOCK_EX | File::LOCK_NB)
      raise Refused, "conversation root busy" unless file_locked
      load!
      check!(deadline, cancel)
      existing = @attempts[request_id]
      if existing
        raise Refused, "request identity reused with different input" unless existing["input"] == input
        raise Refused, "retained attempt requires review; no automatic retry" unless existing["state"] == "complete"
        return JSON.parse(JSON.generate(existing.fetch("result"))).merge("replayed" => true)
      end
      turns = @attempts.values.select { |a| a["input"]["conversation_id"] == conversation_id }
      # The service journal shares one bounded record budget across chats.
      # A separate trial-era chat-count limit stranded usable capacity. Keep
      # all attempts, including failures, and reserve terminal-record space below.
      raise Refused, "conversation is bound to another model/configuration" if turns.any? { |a| a["input"]["adapter"] != adapter.binding }
      raise Refused, "unfinished conversation requires review" unless turns.all? { |a| a["state"] == "complete" }
      expected = turns.flat_map { |a| [a["input"]["messages"].last, { "role" => "assistant", "content" => a["result"]["content"] }] }
      raise Refused, "history import, edit, regeneration or missing turn" unless input["messages"][0...-1] == expected
      raise Refused, "scoped canonical memory required" unless @memory.instance_of?(RosterMemoryContext)
      projected = input["messages"].last(7)
      adapter.payload(messages: projected)
      check!(deadline, cancel)
      # Reserve room for request, ownership, intent, receipt and terminal state.
      raise Refused, "journal quota" if @records.length + 7 > LIMIT
      append!("requested", request_id, input)
      begun = true
      result = @owner.with_runtime(adapter: adapter, request_id: request_id, conversation_id: conversation_id,
        deadline: deadline, cancel: cancel) do |client, admission, identity|
        append!("owned", request_id, identity)
        exchange = RosterFinalFormatMemoryExchange.new(adapter: adapter, memory: @memory, client: client, admission: admission,
          cancel: cancel, clock: @clock, receipt: ->(record) { append!(record.fetch("state"), request_id, record) })
        exchange.call(messages: [{"role"=>"system","content"=>RosterGptFinalFormat.for_model(adapter.model)}]+projected, deadline: deadline, chat_id: conversation_id)
      end
      check!(deadline, cancel)
      result = result.merge("conversation_id" => conversation_id, "request_id" => request_id,
        "lineage" => self.class.digest(@manifest), "runtime" => @attempts.fetch(request_id).fetch("identity"),
        "replayed" => false, "history_policy" => @manifest.fetch("history_policy"))
      decision=RosterToolProposalPolicy.resolve(result.fetch('content'))
      unless decision['kind']=='none'
        append!('proposal_checked',request_id,{'text'=>result.fetch('content'),'decision'=>decision})
        check!(deadline,cancel)
        outcome=if decision['kind']=='tool'
          @skills.call(operation:decision.fetch('operation'),deadline:deadline,cancel:cancel)
        else
          {'state'=>'awaiting_input','data'=>{'message'=>'The proposed tool request was not valid. Please clarify the supported read-only task, or use an explicit command. No tool was executed.'}}
        end
        check!(deadline,cancel)
        append!('proposal_result',request_id,outcome)
        result=proposal_result(@attempts.fetch(request_id),self.class.digest(@manifest))
      end
      append!("complete", request_id, result)
      result
    rescue Exception => error
      driver_abort = defined?(ChatReplacementTrial::Abort) && error.is_a?(ChatReplacementTrial::Abort)
      raise unless error.is_a?(StandardError) || driver_abort
      if begun && @attempts[request_id] && !%w[complete failed canceled].include?(@attempts[request_id]["state"])
        # No raw transport error, private reasoning or credential is journaled.
        # If this append also fails, the earlier intent remains blocking.
        append!(cancel.call ? "canceled" : "failed", request_id, { "error_class" => error.class.name, "requires_review" => true })
      end
      raise RosterRuntimeOwner::Unavailable, "model transport rejected; retained attempt requires review" if driver_abort
      raise
    ensure
      @lock.flock(File::LOCK_UN) if file_locked
      @mutex.unlock if locked
    end

    private
    def apply!(record)
      imported=@transition && record['sequence']<=@transition['imported_records']+1
      attempt=@attempts[record['request_id']]
      if !imported && %w[generation_intent final_received].include?(record['state']) && attempt&.dig('input','adapter','model')=='gpt-oss-20b'
        data=record['data']
        unless data.is_a?(Hash) && data['output_format']==RosterGptFinalFormat::BINDING &&
            (record['state']!='final_received' || hex?(data['native_final_sha256']))
          raise Refused,'native final format receipt mismatch'
        end
      end
      super
    end
  end
end
