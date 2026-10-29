# frozen_string_literal: true

require_relative "continuity_lab/chat_gateway"
require_relative "roster_runtime_owner"
require_relative "roster_chat_exchange"

module SoulCore
  # A separate append-only lineage. Historical A22/Qwen manifests and workers
  # are neither migrated nor accepted. No model text becomes a command/memory.
  class RosterConversationGateway
    Directory = ContinuityLab::ChatGateway::Directory
    class Refused < StandardError; end
    VERSION = "roster_conversations_v1"
    RECORD = /\Ar-(\d{6})\.json\z/
    ID = /\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/
    LIMIT = 512

    def self.digest(value) = ContinuityLab.digest(value)
    def self.manifest(owner)
      files = %w[roster_chat_adapter.rb roster_chat_exchange.rb roster_runtime_owner.rb roster_conversation_gateway.rb model_runtime_lease_store.rb continuity_lab/chat_gateway.rb]
      { "version" => VERSION, "roster" => owner.binding,
        "history_policy" => "validate_full_history_project_last_three_exchanges_no_memory_import",
        "implementation" => files.to_h { |name| [name, Digest::SHA256.file(File.join(__dir__, name)).hexdigest] } }
    end

    def self.create(path:, owner:)
      raise Refused, "canonical new path required" unless path.is_a?(String) && File.expand_path(path) == path && path != "/"
      parent = Directory.new(File.dirname(path))
      parent.lock_initialization!
      name = File.basename(path)
      raise Refused, "existing roots cannot be rebound" if parent.children.include?(name)
      stage = "stage-#{SecureRandom.hex(16)}"
      Dir.mkdir(parent.anchor(stage), 0o700)
      staged = Directory.new(File.join(File.dirname(path), stage))
      staged.write("roster.json", manifest(owner).merge("lineage_id" => SecureRandom.hex(16)))
      staged.write("lock", {})
      parent.verify!
      raise Refused, "destination appeared" if parent.children.include?(name)
      File.rename(parent.anchor(stage), parent.anchor(name))
      parent.sync
      true
    ensure
      staged&.close
      parent&.close
    end

    def initialize(path:, owner:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @owner, @clock, @mutex = owner, clock, Mutex.new
      @root = Directory.new(path)
      @manifest = @root.read("roster.json")
      unless @manifest.is_a?(Hash) && @manifest["lineage_id"].is_a?(String) &&
             @manifest["lineage_id"].match?(/\A[a-f0-9]{32}\z/) &&
             @manifest.reject { |key| key == "lineage_id" } == self.class.manifest(owner)
        raise Refused, "foreign or changed immutable roster binding"
      end
      @lock = @root.open_file("lock", File::RDWR)
      @lock_identity = [@lock.stat.dev, @lock.stat.ino]
    rescue Exception
      close
      raise
    end

    def close
      @lock&.close unless @lock&.closed?
      @root&.close
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
      raise Refused, "conversation quota" if turns.empty? && @attempts.values.map { |a| a["input"]["conversation_id"] }.uniq.length >= 16
      raise Refused, "conversation is bound to another model/configuration" if turns.any? { |a| a["input"]["adapter"] != adapter.binding }
      raise Refused, "unfinished conversation requires review" unless turns.all? { |a| a["state"] == "complete" }
      expected = turns.flat_map { |a| [a["input"]["messages"].last, { "role" => "assistant", "content" => a["result"]["content"] }] }
      raise Refused, "history import, edit, regeneration or missing turn" unless input["messages"][0...-1] == expected
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
        exchange = RosterChatExchange.new(adapter: adapter, client: client, admission: admission,
          cancel: cancel, clock: @clock, receipt: ->(record) { append!(record.fetch("state"), request_id, record) })
        exchange.call(messages: projected, deadline: deadline)
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

    def check!(deadline, cancel)
      unless deadline.is_a?(Numeric) && deadline.finite? && (deadline - @clock.call).between?(0.001, 180) && !cancel.call
        raise Refused, "canceled or deadline invalid/exhausted"
      end
    end

    def load!
      @root.verify!
      raise Refused, "manifest changed" unless @root.read("roster.json") == @manifest
      file = @root.open_file("lock")
      raise Refused, "lock changed" unless [file.stat.dev, file.stat.ino] == @lock_identity
      names = (@root.children - %w[roster.json lock]).sort
      raise Refused, "unexpected or oversized journal" unless names.length <= LIMIT && names.all? { |n| RECORD.match?(n) }
      @records, @attempts = [], {}
      names.each_with_index do |name, index|
        raise Refused, "journal gap" unless name == format("r-%06d.json", index + 1)
        record = @root.read(name, 524_288)
        expected_keys = %w[data previous request_id sequence state time_utc version]
        unless record.is_a?(Hash) && record.keys.sort == expected_keys && record["version"] == VERSION &&
               record["sequence"] == index + 1 && record["previous"] == previous_digest &&
               record["request_id"].is_a?(String) && ID.match?(record["request_id"])
          raise Refused, "journal binding or chain invalid"
        end
        apply!(record)
        @records << record
      end
    ensure
      file&.close
    end

    def previous_digest = self.class.digest(@records.empty? ? @manifest : @records.last)

    def append!(state, request_id, data)
      @root.verify!
      raise Refused, "journal quota" if @records.length >= LIMIT
      record = { "version" => VERSION, "sequence" => @records.length + 1, "previous" => previous_digest,
        "state" => state, "request_id" => request_id, "data" => JSON.parse(JSON.generate(data)), "time_utc" => Time.now.utc.iso8601(6) }
      raise Refused, "record too large" if JSON.generate(record).bytesize > 524_288
      @root.write(format("r-%06d.json", record["sequence"]), record)
      apply!(record)
      @records << record
    end

    def apply!(record)
      id, state, data = record.values_at("request_id", "state", "data")
      attempt = @attempts[id]
      if state == "requested"
        raise Refused, "duplicate or invalid request" if attempt || !data.is_a?(Hash) || data["request_id"] != id
        @attempts[id] = { "state" => state, "input" => data }
        return
      end
      allowed = { "owned" => ["requested"], "generation_intent" => ["owned"],
        "final_received" => ["generation_intent"], "complete" => ["final_received"],
        "failed" => %w[requested owned generation_intent final_received],
        "canceled" => %w[requested owned generation_intent final_received] }
      raise Refused, "invalid journal transition" unless attempt && allowed.fetch(state, []).include?(attempt["state"])
      case state
      when "owned" then attempt["identity"] = data
      when "generation_intent", "final_received"
        raise Refused, "adapter receipt identity drift" unless data["adapter"] == attempt["input"]["adapter"] && data["state"] == state
        attempt[state] = data
      when "complete"
        receipt = attempt.fetch("final_received")
        unless data["adapter"] == attempt["input"]["adapter"] && data["model"] == data["adapter"]["model"] &&
               data["request_id"] == id && data["conversation_id"] == attempt["input"]["conversation_id"] &&
               data["runtime"] == attempt["identity"] && data["content"].is_a?(String) &&
               Digest::SHA256.hexdigest(data["content"]) == receipt["final_sha256"] && data["usage"] == receipt["usage"]
          raise Refused, "terminal attribution or content mismatch"
        end
        attempt["result"] = data
      end
      attempt["state"] = state
    end
  end
end
