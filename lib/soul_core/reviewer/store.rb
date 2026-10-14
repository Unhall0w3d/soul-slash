# frozen_string_literal: true

require_relative "contract"
require_relative "../continuity_lab/chat_gateway"

module SoulCore
  module Reviewer
    class Store
      Directory = Lab::ChatGateway::Directory
      SCHEMA = "soul.reviewer.store.v1"
      COMMIT = /\Acommit-(\d{8})\.json\z/
      STAGE = /\Astage-[a-f0-9]{32}\z/
      MAX_REVIEWS = 128
      MAX_RECORDS = 2048
      MAX_BYTES = 16 * 1024 * 1024
      MAX_RECORD_BYTES = 131_072
      TERMINAL = %w[completed failed canceled indeterminate expired].freeze

      def self.create(path:, fault: nil)
        unless path.is_a?(String) && path != "/" && File.expand_path(path) == path
          raise Lab::ValidationError, "canonical new root required"
        end
        parent = Directory.new(File.dirname(path))
        parent.lock_initialization!
        name = File.basename(path)
        raise Lab::Conflict, "review root already exists" if parent.children.include?(name)
        stage = "stage-#{SecureRandom.hex(16)}"
        Dir.mkdir(parent.anchor(stage), 0o700)
        directory = Directory.new(File.join(File.dirname(path), stage))
        directory.write("manifest.json", { "schema" => SCHEMA, "store_id" => SecureRandom.hex(16),
          "runtime" => Contract.fake_runtime, "mode" => "detached_fake_only" })
        directory.write("lock", {})
        parent.verify!
        raise Lab::Conflict, "review root already exists" if parent.children.include?(name)
        File.rename(parent.anchor(stage), parent.anchor(name))
        parent.sync
        open(path: path, fault: fault)
      ensure
        directory&.close
        parent&.close
      end

      def self.open(path:, fault: nil) = new(path: path, fault: fault)

      def initialize(path:, fault: nil)
        @directory = Directory.new(path)
        @manifest = @directory.read("manifest.json")
        Contract.fields!(@manifest, %w[schema store_id runtime mode])
        unless @manifest["schema"] == SCHEMA && @manifest["mode"] == "detached_fake_only" &&
               @manifest["store_id"].is_a?(String) && @manifest["store_id"].match?(/\A[a-f0-9]{32}\z/) &&
               @manifest["runtime"] == Contract.fake_runtime
          raise Lab::IntegrityError, "review manifest or implementation mismatch"
        end
        @lock = @directory.open_file("lock", File::RDWR)
        @lock_identity = [@lock.stat.dev, @lock.stat.ino]
        @mutex, @fault = Mutex.new, fault
        snapshot
      rescue Exception
        close
        raise
      end

      def close
        @lock&.close unless @lock&.closed?
        @directory&.close
      end

      def snapshot = synchronize { Contract.copy(@state) }

      def enqueue(request, now:)
        request = Contract.request!(request)
        synchronize do
          existing = @state["reviews"][request["review_id"]]
          if existing
            raise Lab::Conflict, "review ID already binds different content" unless existing["request"] == request
          else
            commit("queued", { "request" => request }, now)
          end
          Contract.copy(@state["reviews"].fetch(request["review_id"]))
        end
      end

      def inspect_review(review_id:, source_revision: nil, evidence_revision: nil)
        if source_revision || evidence_revision
          Contract.hash!(source_revision)
          Contract.hash!(evidence_revision)
        end
        synchronize do
          entry = Contract.copy(find!(review_id))
          entry["freshness"] = if source_revision.nil?
                                 "unknown"
                               elsif entry["request"]["source_revision"] == source_revision && entry["request"]["evidence_revision"] == evidence_revision
                                 "current"
                               else
                                 "stale"
                               end
          entry
        end
      end

      def lease(review_id:, now:, ttl_seconds: 30)
        unless ttl_seconds.is_a?(Integer) && ttl_seconds.between?(1, 60)
          raise Lab::ValidationError, "invalid fake attempt lifetime"
        end
        transition("leased", review_id, now, "attempt_id" => SecureRandom.hex(16), "ttl_seconds" => ttl_seconds)
      end

      def start(review_id:, attempt_id:, now:)
        transition("running", review_id, now, "attempt_id" => attempt_id)
      end

      def complete(review_id:, attempt_id:, response:, runtime:, now:)
        transition("completed", review_id, now, "attempt_id" => attempt_id, "response" => response, "runtime" => runtime)
      end

      def fail(review_id:, attempt_id:, reason:, now:)
        transition("failed", review_id, now, "attempt_id" => attempt_id, "reason" => reason)
      end

      def cancel(review_id:, now:)
        synchronize do
          entry = find!(review_id)
          commit("canceled", { "review_id" => review_id }, now) unless entry["status"] == "canceled"
          Contract.copy(find!(review_id))
        end
      end

      def unavailable(review_id:, now:)
        entry = transition("unavailable", review_id, now)
        { "status" => "reviewer_unavailable", "message" => "Reviewer unavailable. Request retained for later review.",
          "task_disposition" => Contract.disposition(entry["request"]), "review" => entry }
      end

      # Recovery is an explicit invocation, not a timer or automatic replay.
      def recover(now:)
        synchronize do
          Contract.time!(now)
          raise Lab::Conflict, "clock precedes journal" if now < @state["last_time"]
          changed = []
          @state["reviews"].keys.each do |id|
            entry = find!(id)
            if entry["status"] == "queued" && now >= entry["request"]["expires_at"]
              commit("expired", { "review_id" => id }, now)
              changed << id
            elsif %w[leased running].include?(entry["status"]) && now >= entry["lease_expires_at"]
              commit("indeterminate", { "review_id" => id }, now)
              changed << id
            end
          end
          { "changed" => changed, "automatic_retry" => false }
        end
      end

      private

      def transition(kind, id, now, details = {})
        synchronize do
          find!(id)
          commit(kind, details.merge("review_id" => id), now)
          Contract.copy(find!(id))
        end
      end

      def find!(id)
        Contract.id!(id)
        @state["reviews"].fetch(id) { raise Lab::Conflict, "unknown review" }
      end

      def synchronize
        locked = @mutex.try_lock
        raise Lab::Busy, "review store occupied" unless locked
        file_locked = @lock.flock(File::LOCK_EX | File::LOCK_NB)
        raise Lab::Busy, "review store occupied" unless file_locked
        @directory.verify!
        check = @directory.open_file("lock")
        raise Lab::IntegrityError, "review lock replaced" unless [check.stat.dev, check.stat.ino] == @lock_identity && check.read == "{}\n"
        raise Lab::IntegrityError, "manifest changed" unless @directory.read("manifest.json") == @manifest
        replay!
        yield
      ensure
        check&.close
        @lock.flock(File::LOCK_UN) if file_locked
        @mutex.unlock if locked
      end

      def inventory!
        names = @directory.children
        raise Lab::QuotaExceeded, "review file count exceeded" if names.length > MAX_RECORDS * 2 + 2
        @bytes = names.sum do |name|
          unless %w[manifest.json lock].include?(name) || name.match?(COMMIT) || name.match?(STAGE)
            raise Lab::IntegrityError, "unknown review store file"
          end
          file = @directory.open_file(name)
          size = file.stat.size
          raise Lab::IntegrityError, "review file exceeds bound" if size > MAX_RECORD_BYTES
          size
        ensure
          file&.close
        end
        raise Lab::QuotaExceeded, "review storage exceeded" if @bytes > MAX_BYTES
        names
      end

      def replay!
        names = inventory!
        @state = { "reviews" => {}, "sequence" => 0, "last_time" => 0 }
        @head = nil
        names.grep(COMMIT).sort.each do |name|
          record = @directory.read(name, MAX_RECORD_BYTES)
          Contract.fields!(record, %w[schema store_id sequence previous_digest kind payload at digest])
          unless record["schema"] == SCHEMA && record["store_id"] == @manifest["store_id"] &&
                 record["sequence"] == @state["sequence"] + 1 && record["sequence"] <= MAX_RECORDS &&
                 name == format("commit-%08d.json", record["sequence"]) && record["previous_digest"] == @head &&
                 record["digest"] == Contract.digest(record.reject { |key, _| key == "digest" })
            raise Lab::IntegrityError, "invalid reviewer journal chain"
          end
          reduce!(@state, record)
          @head = record["digest"]
        end
      rescue Lab::ValidationError, Lab::Conflict, KeyError, JSON::ParserError, TypeError, ArgumentError => error
        raise Lab::IntegrityError, "invalid reviewer journal: #{error.class}"
      end

      def commit(kind, payload, now)
        raise Lab::QuotaExceeded, "review transaction limit reached" if @state["sequence"] >= MAX_RECORDS
        record = { "schema" => SCHEMA, "store_id" => @manifest["store_id"], "sequence" => @state["sequence"] + 1,
          "previous_digest" => @head, "kind" => kind, "payload" => Contract.copy(payload), "at" => now }
        record["digest"] = Contract.digest(record)
        candidate = Contract.copy(@state)
        reduce!(candidate, record)
        bytes = Lab.encode(record).bytesize + 1
        raise Lab::QuotaExceeded, "review record/storage bound reached" if bytes > MAX_RECORD_BYTES || @bytes + bytes > MAX_BYTES
        name = format("commit-%08d.json", record["sequence"])
        stage = "stage-#{SecureRandom.hex(16)}"
        @fault&.call(:before_write, record)
        @directory.write(stage, record)
        @fault&.call(:after_stage, record)
        @directory.verify!
        raise Lab::IntegrityError, "review commit already exists" if @directory.children.include?(name)
        File.rename(@directory.anchor(stage), @directory.anchor(name))
        @fault&.call(:after_rename, record)
        @directory.sync
        @state, @head, @bytes = candidate, record["digest"], @bytes + bytes
        @fault&.call(:after_commit, record)
      rescue SystemCallError, IOError => error
        raise Lab::IntegrityError, "review commit uncertain: #{error.class}"
      end

      def reduce!(state, record)
        kind, payload, at = record.values_at("kind", "payload", "at")
        Contract.time!(at)
        raise Lab::Conflict, "clock precedes journal" if at < state["last_time"]
        if kind == "queued"
          Contract.fields!(payload, %w[request])
          request = Contract.request!(payload["request"])
          id = request["review_id"]
          raise Lab::Conflict, "duplicate request or invalid admission time" if state["reviews"].key?(id) || at < request["created_at"] || at >= request["expires_at"]
          raise Lab::QuotaExceeded, "review request limit reached" if state["reviews"].size >= MAX_REVIEWS
          state["reviews"][id] = { "request" => request, "request_revision" => Contract.digest(request),
            "status" => "queued", "availability" => "not_checked", "artifact" => nil,
            "visibility" => "detached_not_available_to_soul", "acceptance" => "not_evaluated" }
        else
          raise Lab::ValidationError, "invalid transition payload" unless payload.is_a?(Hash)
          Contract.id!(payload["review_id"])
          entry = state["reviews"].fetch(payload["review_id"]) { raise Lab::Conflict, "unknown review" }
          request = entry["request"]
          case kind
          when "unavailable"
            Contract.fields!(payload, %w[review_id])
            queued!(entry, at)
            entry["availability"] = "unavailable"
          when "leased"
            Contract.fields!(payload, %w[review_id attempt_id ttl_seconds])
            queued!(entry, at)
            unless payload["attempt_id"].is_a?(String) && payload["attempt_id"].match?(/\A[a-f0-9]{32}\z/) &&
                   payload["ttl_seconds"].is_a?(Integer) && payload["ttl_seconds"].between?(1, 60)
              raise Lab::ValidationError, "invalid attempt lease"
            end
            entry.merge!("status" => "leased", "attempt_id" => payload["attempt_id"],
              "lease_expires_at" => [at + payload["ttl_seconds"], request["expires_at"]].min, "availability" => "fake_available")
          when "running", "completed", "failed"
            keys = %w[review_id attempt_id] + (kind == "completed" ? %w[response runtime] : kind == "failed" ? %w[reason] : [])
            Contract.fields!(payload, keys)
            allowed = kind == "running" ? %w[leased] : kind == "failed" ? %w[leased running] : %w[running]
            unless allowed.include?(entry["status"]) && payload["attempt_id"] == entry["attempt_id"] && at < entry["lease_expires_at"]
              raise Lab::Conflict, "stale, canceled, duplicate or expired attempt"
            end
            if kind == "completed"
              response = Contract.response!(payload["response"], request: request)
              raise Lab::ValidationError, "unattested runtime identity" unless payload["runtime"] == @manifest["runtime"]
              entry["artifact"] = { "schema" => "soul.reviewer.artifact.v1", "review_id" => request["review_id"],
                "source_event_id" => request["source_event_id"], "source_revision" => request["source_revision"],
                "evidence_revision" => request["evidence_revision"], "request_revision" => entry["request_revision"],
                "attempt_id" => entry["attempt_id"], "completed_at" => at, "runtime" => Contract.copy(payload["runtime"]),
                "response" => response, "semantic_review_performed" => false }
              entry["artifact"]["artifact_revision"] = Contract.digest(entry["artifact"])
            elsif kind == "failed"
              unless %w[invalid_response fake_failure deadline_exceeded].include?(payload["reason"])
                raise Lab::ValidationError, "invalid failure reason"
              end
              entry["reason"] = payload["reason"]
            end
            entry["status"] = kind
          when "canceled"
            Contract.fields!(payload, %w[review_id])
            raise Lab::Conflict, "terminal review cannot be canceled" if TERMINAL.include?(entry["status"])
            entry.merge!("status" => "canceled", "reason" => "explicit_cancellation")
          when "expired"
            Contract.fields!(payload, %w[review_id])
            unless entry["status"] == "queued" && at >= request["expires_at"]
              raise Lab::Conflict, "request is not expired queued work"
            end
            entry.merge!("status" => "expired", "reason" => "request_expired")
          when "indeterminate"
            Contract.fields!(payload, %w[review_id])
            unless %w[leased running].include?(entry["status"]) && at >= entry["lease_expires_at"]
              raise Lab::Conflict, "attempt is not expired unresolved work"
            end
            entry.merge!("status" => "indeterminate", "reason" => "attempt_expired_no_replay")
          else
            raise Lab::ValidationError, "unknown reviewer transition"
          end
        end
        state["sequence"], state["last_time"] = record["sequence"], at
      end

      def queued!(entry, at)
        raise Lab::Conflict, "review is not unexpired queued work" unless entry["status"] == "queued" && at < entry["request"]["expires_at"]
      end
    end
  end
end
