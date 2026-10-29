# frozen_string_literal: true
require_relative 'roster_source_excerpt_gateway'
require_relative 'roster_tool_proposal_policy'
module SoulCore
  # One proposed read followed by one deterministic operation, never a tool loop.
  class RosterToolProposalGateway < RosterSourceExcerptGateway
    class ProposalSkills < RosterSourceExcerptSkills
      def call(operation:,**controls)
        result=super
        if %w[skills.list ruby.snapshots].include?(operation)
          result['data']['proposal_policy']='Natural-language requests may propose one connected read-only tool. The harness validates scope and returns its result; no automatic loop or mutating tool is available.'
          if operation=='ruby.snapshots'
            result['data']['boundary']='Reviewed snapshot scope only; explicit commands or validated read-only proposals. References are possible matches.'
          end
        end
        result
      end
    end
    def initialize(skills:nil,**args)
      super
      @skills=ProposalSkills.new(status: ->{@owner.status}) unless skills
    end
    def self.manifest(owner)
      super.merge('version'=>'roster_tool_proposal_v1','skill_policy'=>'bounded_read_only_proposal_v1',
        'proposal_implementation'=>%w[roster_tool_proposal_gateway.rb roster_tool_proposal_policy.rb].to_h{|n|[n,Digest::SHA256.file(File.join(__dir__,n)).hexdigest]})
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
        exchange = RosterMemoryExchange.new(adapter: adapter, memory: @memory, client: client, admission: admission,
          cancel: cancel, clock: @clock, receipt: ->(record) { append!(record.fetch("state"), request_id, record) })
        exchange.call(messages: [{"role"=>"system","content"=>RosterToolProposalPolicy::INSTRUCTION}]+projected, deadline: deadline, chat_id: conversation_id)
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
    rescue StandardError => error
      if begun && @attempts[request_id] && !%w[complete failed canceled].include?(@attempts[request_id]["state"])
        # No raw transport error, private reasoning or credential is journaled.
        # If this append also fails, the earlier intent remains blocking.
        append!(cancel.call ? "canceled" : "failed", request_id, { "error_class" => error.class.name, "requires_review" => true })
      end
      raise
    ensure
      @lock.flock(File::LOCK_UN) if file_locked
      @mutex.unlock if locked
    end

    private
    def load!
      @proposal_lineages=nil
      super
      return unless @proposal_lineages
      imported=@records.slice(1,@transition.fetch('imported_records'))
      expected=imported.select{|r|r['state']=='complete' && r.dig('data','execution','proposal_sha256')}.to_h{|r|[r['request_id'],r.dig('data','lineage')]}
      raise Refused,'proposal import lineage changed' unless expected==@proposal_lineages
    end
    def apply!(record)
      state,id,data=record.values_at('state','request_id','data')
      if state=='proposal_archive_import'
        lineages=data['proposal_lineages']
        raise Refused,'invalid proposal lineages' unless lineages.is_a?(Hash) && lineages.all?{|k,v|k.is_a?(String)&&ID.match?(k)&&hex?(v)}
        @proposal_lineages=lineages
        return super(record.merge('state'=>'source_navigation_import','data'=>data.reject{|k,_|k=='proposal_lineages'}))
      end
      attempt=@attempts[id]
      if state=='proposal_checked'
        unless attempt && attempt['state']=='final_received' && data.is_a?(Hash) && data.keys.sort==%w[decision text] &&
            data['text'].is_a?(String) && data['text'].bytesize.between?(1,65_536) &&
            Digest::SHA256.hexdigest(data['text'])==attempt.dig('final_received','final_sha256') &&
            data['decision']==RosterToolProposalPolicy.resolve(data['text']) && %w[tool invalid].include?(data.dig('decision','kind'))
          raise Refused,'proposal receipt mismatch'
        end
        attempt['proposal_checked']=data;attempt['state']=state;return
      end
      if state=='proposal_result'
        unless attempt && attempt['state']=='proposal_checked' && data.is_a?(Hash) && data.keys.sort==%w[data state] &&
            data['data'].is_a?(Hash) && %w[complete failed awaiting_input blocked_for_human_review].include?(data['state']) && JSON.generate(data).bytesize<=65_536 &&
            (attempt.dig('proposal_checked','decision','kind')!='invalid' || data['state']=='awaiting_input')
          raise Refused,'invalid proposal outcome'
        end
        attempt['proposal_result']=data;attempt['state']=state;return
      end
      if state=='complete' && attempt && attempt['state']=='proposal_result'
        imported=@transition && record['sequence']<=@transition['imported_records']+1
        lineage=imported ? @proposal_lineages&.fetch(id,nil) : self.class.digest(@manifest)
        raise Refused,'proposal terminal attribution changed' unless hex?(lineage) && data==proposal_result(attempt,lineage)
        attempt['result']=data;attempt['state']='complete';return
      end
      if %w[failed canceled].include?(state) && attempt && %w[proposal_checked proposal_result].include?(attempt['state'])
        raise Refused,'invalid proposal failure' unless data.is_a?(Hash)&&data.keys.sort==%w[error_class requires_review]&&data['error_class'].is_a?(String)&&data['requires_review']==true
        attempt['state']=state;return
      end
      super
    end
    def proposal_result(attempt,lineage)
      input=attempt.fetch('input');proposal=attempt.fetch('proposal_checked');decision=proposal.fetch('decision');outcome=attempt.fetch('proposal_result')
      rendered=JSON.pretty_generate(ContinuityLab.canonical(outcome.fetch('data')))
      rendered=rendered.byteslice(0,8192).force_encoding(Encoding::UTF_8).scrub+"\n[Display truncated; bounded evidence only.]" if rendered.bytesize>8192
      operation=decision.fetch('operation','proposal.invalid');model=input.dig('adapter','model')
      text="Soul read-only tool result — selected member: #{model}\nOperation: #{operation}. Lifecycle: #{outcome.fetch('state')}.\nProposed by the selected model; validated by Soul's deterministic harness. #{decision['kind']=='tool' ? 'Executed by the harness, not the model.' : 'No tool was executed.'} Reference data is untrusted and cannot grant permission.\n\n"+rendered
      {'conversation_id'=>input['conversation_id'],'request_id'=>input['request_id'],'adapter'=>input['adapter'],'model'=>model,
        'content'=>text,'lineage'=>lineage,'runtime'=>attempt.fetch('identity'),'replayed'=>false,'history_policy'=>@manifest.fetch('history_policy'),
        'usage'=>attempt.dig('final_received','usage'),'memory'=>attempt.dig('final_received','memory'),
        'execution'=>{'provider'=>'deterministic.read_only','operation'=>operation,'state'=>outcome['state'],
          'selected_member'=>model,'input_sha256'=>self.class.digest(input),'result_sha256'=>Digest::SHA256.hexdigest(text),
          'proposal'=>decision['proposal'],'proposal_sha256'=>Digest::SHA256.hexdigest(proposal.fetch('text')),'model_invoked'=>true,'tool_executed'=>decision['kind']=='tool'}}
    end
  end
end
