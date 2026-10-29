# frozen_string_literal: true
require_relative "roster_conversation_gateway"
require_relative "roster_memory_exchange"

module SoulCore
  # V1 remains unchanged for authenticated import of its original chains. V2
  # retains the record envelope but adds a memory-bound conversation policy.
  class RosterMemoryGateway < RosterConversationGateway
    def self.manifest(owner)
      super.merge("version" => "roster_conversations_v2_scoped_memory",
        "history_policy" => "validate_full_history_project_last_three_exchanges_scoped_memory_v1",
        "memory_implementation" => %w[roster_memory_gateway.rb roster_memory_exchange.rb roster_memory_context.rb conversation_memory_store.rb].to_h { |n|
          [n, Digest::SHA256.file(File.join(__dir__, n)).hexdigest] })
    end

    def initialize(memory: nil, **args)
      @memory = memory
      super(**args)
    end

    # Offline implementation upgrade. Authenticate the historical implementation
    # against retained source files; never edit a live manifest to accept new code.
    def self.upgrade(source:, destination:, owner:, expected_manifest_sha256:, implementation_files:)
      expected = manifest(owner)
      names = expected.fetch("memory_implementation").keys.sort
      raise Refused, "source implementation set changed" unless implementation_files.keys.sort == names
      historical = expected.merge("memory_implementation" => implementation_files.transform_values { |p| Digest::SHA256.file(p).hexdigest })
      source_directory = Directory.new(source)
      source_manifest = source_directory.read("roster.json")
      unless digest(source_manifest) == expected_manifest_sha256 && source_manifest.reject { |k,_| k == "lineage_id" } == historical
        raise Refused, "source implementation binding changed"
      end
      reader = Class.new(self)
      reader.define_singleton_method(:manifest) { |_owner| historical }
      old = reader.new(path: source, owner: owner)
      raise Refused, "source journal busy" unless old.instance_variable_get(:@lock).flock(File::LOCK_EX | File::LOCK_NB)
      raise Refused, "source manifest changed" unless digest(old.instance_variable_get(:@manifest)) == expected_manifest_sha256
      old.send(:load!)
      records = old.instance_variable_get(:@records)
      unless old.instance_variable_get(:@attempts).values.all? { |a| %w[complete failed canceled].include?(a["state"]) }
        raise Refused, "unfinished source attempt requires reconciliation"
      end
      raise Refused, "transition quota" if records.length + 6 > LIMIT
      create(path: destination, owner: owner)
      target = new(path: destination, owner: owner)
      raise Refused, "target journal busy" unless target.instance_variable_get(:@lock).flock(File::LOCK_EX | File::LOCK_NB)
      target.send(:load!)
      records.each { |r| target.send(:append!, r["state"], r["request_id"], r["data"]) }
      target.send(:append!, "implementation_transition", "implementation-transition", {
        "source_manifest_sha256" => expected_manifest_sha256,
        "source_tail_sha256" => digest(records.empty? ? source_manifest : records.last),
        "imported_records" => records.length,
        "payloads_sha256" => digest(records.map { |r| r.values_at("state", "request_id", "data") }) })
      target.send(:load!)
      {"state" => "complete", "imported_records" => records.length,
        "source_manifest_sha256" => expected_manifest_sha256,
        "destination_manifest_sha256" => digest(target.instance_variable_get(:@manifest)), "source_preserved" => true}
    ensure
      target&.close
      old&.close
      source_directory&.close
    end

    # Explicit offline transition: source stays byte-for-byte unchanged. Request
    # inputs and terminal results are imported unchanged; only chain envelopes
    # are new. Thus exact prior replays return their original results/lineage.
    def self.transition(source:, destination:, owner:, expected_manifest_sha256:, source_owner: owner)
      old = RosterConversationGateway.new(path: source, owner: source_owner)
      lock = old.instance_variable_get(:@lock)
      raise Refused, "source journal busy" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
      source_manifest = old.instance_variable_get(:@manifest)
      raise Refused, "source manifest changed" unless digest(source_manifest) == expected_manifest_sha256
      old.send(:load!)
      records = old.instance_variable_get(:@records)
      unless old.instance_variable_get(:@attempts).values.all? { |a| %w[complete failed canceled].include?(a["state"]) }
        raise Refused, "unfinished source attempt requires reconciliation"
      end
      raise Refused, "transition quota" if records.length + 6 > LIMIT
      create(path: destination, owner: owner)
      target = new(path: destination, owner: owner)
      raise Refused, "target journal busy" unless target.instance_variable_get(:@lock).flock(File::LOCK_EX | File::LOCK_NB)
      target.send(:load!)
      target.send(:append!, "transition", "journal-transition", {
        "source_manifest_sha256" => expected_manifest_sha256,
        "source_tail_sha256" => digest(records.empty? ? source_manifest : records.last),
        "imported_records" => records.length,
        "payloads_sha256" => digest(records.map { |r| r.values_at("state", "request_id", "data") }) })
      records.each { |r| target.send(:append!, r["state"], r["request_id"], r["data"]) }
      target.send(:load!)
      {"state" => "complete", "source_manifest_sha256" => expected_manifest_sha256,
        "destination_manifest_sha256" => digest(target.instance_variable_get(:@manifest)),
        "imported_records" => records.length, "source_preserved" => true}
    ensure
      target&.close
      old&.close
    end

    def complete(conversation_id:, request_id:, adapter:, messages:, deadline:, cancel: -> { false })
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
      raise Refused, "journal quota" if @records.length + 5 > LIMIT
      append!("requested", request_id, input)
      begun = true
      result = @owner.with_runtime(adapter: adapter, request_id: request_id, conversation_id: conversation_id,
        deadline: deadline, cancel: cancel) do |client, admission, identity|
        append!("owned", request_id, identity)
        exchange = RosterMemoryExchange.new(adapter: adapter, memory: @memory, client: client, admission: admission,
          cancel: cancel, clock: @clock, receipt: ->(record) { append!(record.fetch("state"), request_id, record) })
        exchange.call(messages: projected, deadline: deadline, chat_id: conversation_id)
      end
      check!(deadline, cancel)
      result = result.merge("conversation_id" => conversation_id, "request_id" => request_id,
        "lineage" => self.class.digest(@manifest), "runtime" => @attempts.fetch(request_id).fetch("identity"),
        "replayed" => false, "history_policy" => @manifest.fetch("history_policy"))
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
      @transition = nil
      @implementation_transitions = []
      super
      @implementation_transitions.each do |boundary|
        prefix = @records.first(boundary.fetch("imported_records"))
        unless self.class.digest(prefix.map { |r| r.values_at("state", "request_id", "data") }) == boundary["payloads_sha256"]
          raise Refused, "changed implementation transition prefix"
        end
      end
      return unless @transition
      imported = @records.slice(1, @transition.fetch("imported_records"))
      unless imported.length == @transition["imported_records"] &&
          self.class.digest(imported.map { |r| r.values_at("state", "request_id", "data") }) == @transition["payloads_sha256"]
        raise Refused, "incomplete or changed transition prefix"
      end
    end

    def apply!(record)
      data, state = record.values_at("data", "state")
      if state == "implementation_transition"
        unless data.is_a?(Hash) && data.keys.sort == %w[imported_records payloads_sha256 source_manifest_sha256 source_tail_sha256] &&
            data["imported_records"] == record["sequence"] - 1 &&
            data.reject { |k,_| k == "imported_records" }.values.all? { |v| hex?(v) }
          raise Refused, "invalid implementation transition boundary"
        end
        @implementation_transitions << data
        return
      end
      if state == "transition"
        unless record["sequence"] == 1 && data.is_a?(Hash) &&
            data.keys.sort == %w[imported_records payloads_sha256 source_manifest_sha256 source_tail_sha256] &&
            data["imported_records"].is_a?(Integer) && data["imported_records"].between?(0, LIMIT - 6) &&
            data.reject { |k,_| k == "imported_records" }.values.all? { |v| hex?(v) }
          raise Refused, "invalid transition boundary"
        end
        @transition = data
        return
      end
      imported = @transition && record["sequence"] <= @transition["imported_records"] + 1
      if !imported && %w[generation_intent final_received complete].include?(state)
        attempt = @attempts[record["request_id"]]
        memory = data["memory"]
        unless memory.is_a?(Hash) && memory.keys.sort == %w[member rendered_sha256 revisions selection_sha256 stage version] &&
            memory["version"] == RosterMemoryContext::VERSION && memory["member"] == attempt&.dig("input", "adapter", "model") &&
            memory["stage"] == (state == "generation_intent" ? state : "final_received") &&
            hex?(memory["selection_sha256"]) && hex?(memory["rendered_sha256"]) &&
            memory["revisions"].is_a?(Array) && memory["revisions"].length <= 8 &&
            memory["revisions"].all? { |r| r.is_a?(Hash) && r.keys.sort == %w[id sha256] && r["id"].is_a?(String) && hex?(r["sha256"]) }
          raise Refused, "invalid memory receipt"
        end
        if state != "generation_intent"
          intent = attempt.fetch("generation_intent")
          unless memory.reject { |k,_| k == "stage" } == intent.fetch("memory").reject { |k,_| k == "stage" }
            raise Refused, "memory revision changed across receipts"
          end
          if state == "final_received" && data.values_at("request_sha256", "prompt_sha256", "input_tokens") != intent.values_at("request_sha256", "prompt_sha256", "input_tokens")
            raise Refused, "generation receipt binding changed"
          end
        end
      end
      super
    end

    def hex?(value) = value.is_a?(String) && /\A[a-f0-9]{64}\z/.match?(value)
  end
end
