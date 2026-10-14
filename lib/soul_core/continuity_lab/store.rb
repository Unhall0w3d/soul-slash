# frozen_string_literal: true

require "securerandom"
require "time"
require_relative "config"
require_relative "actions"
require_relative "context_builder"
require_relative "token_context"

module SoulCore
  module ContinuityLab
    class Store
      SCHEMA = "soul.continuity_lab.a1"
      TERMINAL = %w[complete failed canceled blocked_for_human_review awaiting_input].freeze
      COMMIT = /\Acommit-(\d{8})\.json\z/
      STAGE = /\A\.stage-[a-f0-9]{32}\.json\z/
      MAX_RECORD_BYTES = 524_288
      attr_reader :config

      def self.create(path:, config: Config.new, fault: nil, corpus: [])
        new(path: path, config: config, create: true, fault: fault, corpus: corpus)
      end

      def self.open(path:, config: Config.new, fault: nil)
        new(path: path, config: config, create: false, fault: fault, corpus: nil)
      end

      def initialize(path:, config:, create:, fault:, corpus:)
        raise ValidationError, "invalid config" unless config.instance_of?(Config)
        if create
          Retrieval.validate_corpus!(corpus)
          raise ValidationError, "corpus requires explicit context mode" unless corpus.empty? || config["context_mode"] == "explicit_v1"
          corpus = JSON.parse(JSON.generate(corpus))
          manifest_text = ContinuityLab.encode({
            "schema" => SCHEMA, "lineage_id" => SecureRandom.hex(16),
            "config" => config.to_h, "config_digest" => config.digest,
            "corpus" => corpus, "corpus_digest" => ContinuityLab.digest(corpus)
          })
          if manifest_text.bytesize > MAX_RECORD_BYTES || manifest_text.bytesize > config["max_journal_bytes"]
            raise QuotaExceeded, "manifest exceeds store quota"
          end
        end
        unless path.is_a?(String) && path.encoding.ascii_compatible? && path.valid_encoding? && !path.include?("\0") && path.start_with?("/") && File.expand_path(path) == path && path != "/"
          raise ValidationError, "store requires a canonical absolute path"
        end
        @config, @fault, @locked = config, fault, false
        parent = open_directory(File.dirname(path))
        leaf = File.basename(path)
        Dir.mkdir(anchored(parent, leaf), 0o700) if create
        @directory = File.open(anchored(parent, leaf), File::RDONLY | File::NOFOLLOW | File::NONBLOCK)
        validate_directory!
        if create
          write_exclusive("manifest.json", manifest_text)
          write_exclusive("lock", "")
          @directory.fsync
        end
        @manifest = ContinuityLab.parse(read_private("manifest.json", MAX_RECORD_BYTES))
        unless @manifest.is_a?(Hash) && @manifest.keys.sort == %w[config config_digest corpus corpus_digest lineage_id schema] &&
               @manifest["schema"] == SCHEMA && @manifest["lineage_id"].is_a?(String) &&
               @manifest["lineage_id"].match?(/\A[a-f0-9]{32}\z/) &&
               @manifest["config"] == config.to_h && @manifest["config_digest"] == config.digest &&
               @manifest["corpus_digest"] == ContinuityLab.digest(@manifest["corpus"])
          raise IntegrityError, "manifest or configuration mismatch"
        end
        begin
          Retrieval.validate_corpus!(@manifest["corpus"])
          raise ValidationError, "corpus requires explicit context mode" unless @manifest["corpus"].empty? || config["context_mode"] == "explicit_v1"
        rescue ValidationError
          raise IntegrityError, "invalid manifest corpus"
        end
        @lock = open_private("lock", File::RDWR)
      rescue Errno::EEXIST
        close
        raise Conflict, "store already exists"
      rescue JSON::ParserError, SystemCallError, IOError => error
        close
        raise IntegrityError, "cannot open store: #{error.class}"
      rescue Error
        close
        raise
      ensure
        parent&.close
      end

      def close
        @lock&.close unless @lock&.closed?
        @directory&.close unless @directory&.closed?
      end

      def synchronize
        raise Busy, "store writer already active" if @locked
        raise IntegrityError, "store is closed" unless @lock && !@lock.closed?
        raise Busy, "store writer occupied" unless @lock.flock(File::LOCK_EX | File::LOCK_NB)
        begin
          @locked = true
          validate_directory!
          validate_lock!
          current_manifest = ContinuityLab.parse(read_private("manifest.json", MAX_RECORD_BYTES))
          raise IntegrityError, "manifest changed while store open" unless current_manifest == @manifest
          load_journal!
          yield @state
        rescue JSON::ParserError
          raise IntegrityError, "invalid manifest"
        rescue SystemCallError, IOError => error
          raise IntegrityError, "store I/O failed: #{error.class}"
        ensure
          @locked = false
          @lock.flock(File::LOCK_UN)
        end
      end

      def snapshot
        synchronize { JSON.parse(JSON.generate(@state)) }
      end

      def integrity
        synchronize do
          { "ok" => true, "lineage_id" => @manifest.fetch("lineage_id"),
            "transaction_count" => @state.fetch("transaction_count"),
            "event_count" => @state.fetch("events").length,
            "note_count" => @state.fetch("notes").length, "head_digest" => @head,
            "content_included" => false }
        end
      end

      def append(kind, payload)
        raise IntegrityError, "append requires writer lock" unless @locked
        validate_lock!
        seq = @state.fetch("transaction_count") + 1
        raise QuotaExceeded, "transaction bound exceeded" if seq > config["max_transactions"]
        record = { "schema" => SCHEMA, "sequence" => seq, "previous_digest" => @head,
                   "lineage_id" => @manifest.fetch("lineage_id"), "config_digest" => config.digest,
                   "kind" => kind, "payload" => payload, "created_at" => Time.now.utc.iso8601(6) }
        record["digest"] = ContinuityLab.digest(record)
        encoded = ContinuityLab.encode(record) + "\n"
        raise QuotaExceeded, "encoded record bound exceeded" if encoded.bytesize > MAX_RECORD_BYTES
        bytes = inventory.sum { |name| private_stat(name).size }
        raise QuotaExceeded, "journal storage bound exceeded" if bytes + encoded.bytesize > config["max_journal_bytes"]
        next_state = JSON.parse(JSON.generate(@state))
        reduce!(next_state, record)
        @fault&.call(:before_stage, record)
        stage = ".stage-#{SecureRandom.hex(16)}.json"
        write_exclusive(stage, encoded)
        @fault&.call(:after_stage, record)
        destination = format("commit-%08d.json", seq)
        raise IntegrityError, "commit destination already exists" if File.exist?(anchored(@directory, destination))
        File.rename(anchored(@directory, stage), anchored(@directory, destination))
        @directory.fsync
        @state.replace(next_state)
        @head = record.fetch("digest")
        @fault&.call(:after_commit, record)
        record
      rescue SystemCallError, IOError => error
        raise IntegrityError, "journal commit uncertain: #{error.class}"
      end

      private

      def anchored(directory, name)
        "/proc/self/fd/#{directory.fileno}/#{name}"
      end

      # Resolve each component without following symlinks; subsequent I/O remains
      # anchored to the opened directory, even if its display path is renamed.
      def open_directory(path)
        directory = File.open("/", File::RDONLY)
        path.split("/").reject(&:empty?).each do |component|
          child = File.open(anchored(directory, component), File::RDONLY | File::NOFOLLOW | File::NONBLOCK)
          unless child.stat.directory?
            child.close
            raise IntegrityError, "non-directory store ancestor"
          end
          directory.close
          directory = child
        end
        directory
      rescue Exception
        directory&.close
        raise
      end

      def validate_directory!
        stat = @directory.stat
        unless stat.directory? && stat.uid == Process.uid && (stat.mode & 0o777) == 0o700
          raise IntegrityError, "store must be an owner-private directory"
        end
      end

      def private_stat(name)
        stat = File.lstat(anchored(@directory, name))
        unless stat.file? && !stat.symlink? && stat.nlink == 1 && stat.uid == Process.uid && (stat.mode & 0o777) == 0o600
          raise IntegrityError, "unsafe store entry"
        end
        stat
      end

      def open_private(name, flags)
        before = private_stat(name)
        file = File.open(anchored(@directory, name), flags | File::NOFOLLOW | File::NONBLOCK)
        after = file.stat
        unless before.ino == after.ino && before.dev == after.dev && after.nlink == 1
          file.close
          raise IntegrityError, "store entry changed during open"
        end
        file
      end

      def read_private(name, limit)
        file = open_private(name, File::RDONLY)
        value = file.read(limit + 1)
        raise IntegrityError, "store record exceeds bound" if value.bytesize > limit
        value
      ensure
        file&.close
      end

      def write_exclusive(name, content)
        File.open(anchored(@directory, name), File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
          file.write(content)
          file.flush
          file.fsync
        end
      end

      def validate_lock!
        stat = private_stat("lock")
        held = @lock.stat
        raise IntegrityError, "writer lock replaced" unless stat.ino == held.ino && stat.dev == held.dev && stat.size.zero?
      end

      def inventory
        names = []
        Dir.each_child(anchored(@directory, ".")) do |name|
          raise IntegrityError, "unknown store entry" unless %w[manifest.json lock].include?(name) || name.match?(COMMIT) || name.match?(STAGE)
          names << name
          raise QuotaExceeded, "store entry bound exceeded" if names.length > config["max_transactions"] * 2 + 16
        end
        names
      end

      def load_journal!
        @state = { "events" => {}, "notes" => {}, "operations" => [], "transaction_count" => 0,
                   "lineage_id" => @manifest.fetch("lineage_id"), "corpus" => @manifest.fetch("corpus"),
                   "corpus_digest" => @manifest.fetch("corpus_digest") }
        @head = nil
        names = inventory
        bytes = names.sum { |name| private_stat(name).size }
        raise QuotaExceeded, "journal storage bound exceeded" if bytes > config["max_journal_bytes"]
        names.grep(COMMIT).sort.each do |name|
          record = ContinuityLab.parse(read_private(name, MAX_RECORD_BYTES))
          unless record.is_a?(Hash) && record.keys.sort == %w[config_digest created_at digest kind lineage_id payload previous_digest schema sequence] &&
                 record["schema"] == SCHEMA && record["sequence"] == @state["transaction_count"] + 1 &&
                 record["lineage_id"] == @manifest["lineage_id"] && record["config_digest"] == config.digest &&
                 record["sequence"] <= config["max_transactions"] &&
                 name == format("commit-%08d.json", record["sequence"]) &&
                 record["previous_digest"] == @head &&
                 record["digest"] == ContinuityLab.digest(record.reject { |key, _| key == "digest" })
            raise IntegrityError, "invalid journal chain"
          end
          Time.iso8601(record.fetch("created_at"))
          reduce!(@state, record)
          @head = record.fetch("digest")
        end
      rescue JSON::ParserError, KeyError, TypeError, ArgumentError => error
        raise IntegrityError, "invalid journal: #{error.class}"
      end

      def reduce!(state, record)
        payload = record.fetch("payload")
        raise IntegrityError, "invalid journal payload" unless payload.is_a?(Hash)
        id = payload.fetch("event_id")
        raise IntegrityError, "invalid event ID" unless Actions.valid_id?(id)
        event = state["events"][id]
        case record.fetch("kind")
        when "accepted"
          fields!(payload, %w[event_id content content_digest])
          raise IntegrityError, "duplicate accepted event" if event
          raise IntegrityError, "conflicting admission" if state["events"].values.any? { |entry| %w[pending blocked_for_human_review].include?(entry["state"]) }
          unless payload["content"].is_a?(String) && payload["content"].bytesize <= config["max_event_bytes"] &&
                 payload["content_digest"] == Digest::SHA256.hexdigest(payload["content"])
            raise IntegrityError, "invalid accepted content"
          end
          state["events"][id] = payload.merge("state" => "pending", "calls" => [], "tool_count" => 0, "invalid_count" => 0)
        when "model_intent"
          fields!(payload, config["context_mode"] == "explicit_v1" ? %w[event_id call_index context] : %w[event_id call_index])
          pending!(event)
          raise IntegrityError, "context rejection requires termination" if event["context_rejection"]
          raise IntegrityError, "invalid call sequence" unless payload["call_index"] == event["calls"].length && event["calls"].length < config["max_model_calls"]
          raise IntegrityError, "previous action unresolved" if event["calls"].last && !event["calls"].last["result"]
          raise IntegrityError, "invalid action budget exhausted" if event["invalid_count"] > config["max_invalid_actions"]
          raise IntegrityError, "repeated failed action requires termination" if Actions.repeated_failure?(event, config)
          if config["context_mode"] == "explicit_v1"
            begin
              expected_context = if config.tokenized_context?
                TokenContext.finalize(state: state, event_id: id, config: config, preparation: payload.fetch("context").fetch("preparation"))
              else
                ContextBuilder.build(state: state, event_id: id, config: config)
              end
            rescue ContextBudgetExceeded, ValidationError
              raise IntegrityError, "intent exceeds context budget"
            end
            raise IntegrityError, "context does not match eligible state" unless payload["context"] == expected_context
          end
          call = { "response" => nil, "result" => nil }
          call["context"] = payload["context"] if payload.key?("context")
          event["calls"] << call
        when "context_rejected"
          fields!(payload, %w[event_id context])
          pending!(event)
          call = event["calls"].last
          unless config.tokenized_context? && !event["context_rejection"] && (!call || call["result"]) &&
                 event["calls"].length < config["max_model_calls"] && event["invalid_count"] <= config["max_invalid_actions"] &&
                 !Actions.repeated_failure?(event, config)
            raise IntegrityError, "invalid context rejection state"
          end
          begin
            expected = TokenContext.finalize(state: state, event_id: id, config: config,
              preparation: payload.fetch("context").fetch("preparation"), rejected: true)
          rescue ValidationError, ContextBudgetExceeded
            raise IntegrityError, "invalid context rejection evidence"
          end
          raise IntegrityError, "context rejection mismatch" unless payload["context"] == expected
          event["context_rejection"] = expected
        when "model_response"
          fields!(payload, %w[event_id call_index response])
          pending!(event)
          call = current_call!(event, payload)
          raise IntegrityError, "invalid model response" unless call["response"].nil? && payload["response"].is_a?(String) && payload["response"].bytesize <= 65_536
          call["response"] = payload.fetch("response")
        when "action_result"
          pending!(event)
          call = current_call!(event, payload)
          raise IntegrityError, "duplicate or ungrounded action" unless call["response"] && call["result"].nil? && payload["result"].is_a?(Hash)
          action = Actions.parse(call["response"], config)
          expected = { "event_id" => id, "call_index" => payload["call_index"],
                       "operation_id" => ContinuityLab.digest({ "event_id" => id, "call_index" => payload["call_index"] }) }
          if action.empty?
            expected.merge!("invalid" => true, "tool_attempt" => false, "result" => { "ok" => false, "reason" => "invalid_action" })
          elsif action["action"] == "tool" && event["tool_count"] < config["max_tool_calls"]
            expected.merge!("invalid" => false, "tool_attempt" => true)
            expected.merge!(Actions.tool_result(state, action, config, id))
          else
            raise IntegrityError, "action does not permit a tool effect"
          end
          raise IntegrityError, "effect does not match stored response and state" unless payload == expected
          if (note = payload["note"])
            note_id = note.fetch("note_id")
            previous = state["notes"][note_id]
            expected = previous ? previous.fetch("revision") : 0
            unless Actions.valid_id?(note_id) && note["revision"] == expected + 1 && note["parent_revision"] == expected &&
                   note["content"].is_a?(String) && note["content"].bytesize <= config["max_note_bytes"] &&
                   note["content_digest"] == Digest::SHA256.hexdigest(note["content"])
              raise IntegrityError, "invalid note revision"
            end
            history = previous ? previous.fetch("ancestry") + [previous.fetch("revision")] : []
            state["notes"][note_id] = note.merge("ancestry" => history)
          end
          raise IntegrityError, "note quota in journal" if state["notes"].length > config["max_notes"] || state["notes"].values.sum { |entry| entry["content"].bytesize } > config["max_total_note_bytes"]
          call["result"] = payload.fetch("result")
          event["tool_count"] += 1 if payload["tool_attempt"]
          event["invalid_count"] += 1 if payload["invalid"]
          state["operations"] << payload
        when "terminal"
          pending!(event)
          validate_terminal!(state, event, payload)
          event.merge!(payload)
        else
          raise IntegrityError, "unknown journal event"
        end
        state["transaction_count"] = record.fetch("sequence")
      rescue KeyError, IndexError, TypeError, NoMethodError => error
        raise IntegrityError, "invalid journal transition: #{error.class}"
      end

      def pending!(event)
        raise IntegrityError, "event is not pending" unless event && event["state"] == "pending"
      end

      def fields!(value, fields)
        raise IntegrityError, "unexpected journal fields" unless value.keys.sort == fields.sort
      end

      def current_call!(event, payload)
        index = payload.fetch("call_index")
        raise IntegrityError, "invalid active call index" unless index.is_a?(Integer) && index >= 0 && index == event["calls"].length - 1
        event.fetch("calls").fetch(index)
      end

      def validate_terminal!(state, event, payload)
        fields!(payload, payload.key?("reply") ? %w[event_id state reason reply] : %w[event_id state reason])
        if event["context_rejection"] && [payload["state"], payload["reason"]] != ["failed", "context_budget_exceeded"]
          raise IntegrityError, "context rejection requires its recorded terminal reason"
        end
        if Actions.repeated_failure?(event, config) && [payload["state"], payload["reason"]] != ["failed", "repeated_failed_action"]
          raise IntegrityError, "repeated failed action requires its recorded terminal reason"
        end
        call = event["calls"].last
        action = call && call["response"] ? Actions.parse(call["response"], config) : {}
        valid = case [payload["state"], payload["reason"]]
                when ["complete", "reply"]
                  action["action"] == "reply" && !call["result"] && payload["reply"] == action["content"]
                when ["complete", "wait"]
                  action["action"] == "wait" && !call["result"] && !payload.key?("reply")
                when ["blocked_for_human_review", "unresolved_model_intent"], ["failed", "fake_backend_exhausted"]
                  call && call["response"].nil? && !payload.key?("reply")
                when ["failed", "model_call_budget"]
                  event["calls"].length >= config["max_model_calls"] && call["result"] && !payload.key?("reply")
                when ["failed", "repeated_failed_action"]
                  Actions.repeated_failure?(event, config) && !payload.key?("reply")
                when ["failed", "invalid_action_budget"]
                  event["invalid_count"] > config["max_invalid_actions"] && !payload.key?("reply")
                when ["failed", "tool_call_budget"]
                  event["tool_count"] >= config["max_tool_calls"] && action["action"] == "tool" && !payload.key?("reply")
                when ["failed", "deadline_exceeded"]
                  !payload.key?("reply")
                when ["failed", "context_budget_exceeded"]
                  if config["context_mode"] == "explicit_v1" && (!call || call["result"]) && !payload.key?("reply")
                    begin
                      if config.tokenized_context?
                        TokenContext.initial(state: state, event_id: event["event_id"], config: config)
                        !!event["context_rejection"]
                      else
                        ContextBuilder.build(state: state, event_id: event["event_id"], config: config)
                        false
                      end
                    rescue ContextBudgetExceeded
                      true
                    end
                  end
                else false
                end
        raise IntegrityError, "terminal result inconsistent with event" unless valid
      end
    end
  end
end
