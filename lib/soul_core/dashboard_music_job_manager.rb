# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"

module SoulCore
  class DashboardMusicJobManager
    JOB_ID = /\Ajob_[a-f0-9]{16}\z/
    ACTIVE_STATES = %w[accepted running].freeze
    OPERATIONS = %w[music.generation.execute music.candidates.revision.execute chats.creative.execute].freeze
    MAX_RECORDS = 100

    def initialize(root:, facade:, clock: -> { Time.now }, id_generator: -> { SecureRandom.hex(8) })
      @facade = facade
      @clock = clock
      @id_generator = id_generator
      @directory = File.join(File.expand_path(root), "Soul", "music", "jobs")
      FileUtils.mkdir_p(@directory, mode: 0o700)
      File.chmod(0o700, @directory)
      @mutex = Mutex.new
      @threads = {}
      @subscribers = Hash.new { |hash, key| hash[key] = [] }
      recover_interrupted!
    end

    def start(request)
      operation = request.is_a?(Hash) ? request["operation"].to_s : ""
      raise ArgumentError, "music job operation is not detachable" unless OPERATIONS.include?(operation)
      parameters = request.fetch("parameters", {})
      project_id = parameters["project_id"].to_s
      candidate_id = parameters["candidate_id"].to_s
      chat_id = parameters["chat_id"].to_s
      flow_id = parameters["flow_id"].to_s
      if operation == "chats.creative.execute"
        raise ArgumentError, "creative job chat_id is invalid" unless chat_id.match?(/\Achat_[A-Za-z0-9_.-]+\z/)
        raise ArgumentError, "creative job flow_id is invalid" unless flow_id.match?(/\Acreative_[a-f0-9]{16}\z/)
      else
        raise ArgumentError, "music job project_id is invalid" unless project_id.match?(/\Amusic_[a-f0-9]{16}\z/)
        raise ArgumentError, "music job candidate_id is invalid" unless candidate_id.match?(/\Acandidate_[a-f0-9]{16}\z/)
      end

      digest = Digest::SHA256.hexdigest(JSON.generate(request.slice("operation", "parameters", "context")))
      record = nil
      @mutex.synchronize do
        active = records_unlocked.find { |item| ACTIVE_STATES.include?(item["status"]) }
        if active
          return active if active["request_digest"] == digest
          raise ArgumentError, "another bounded music generation job is active"
        end
        now = @clock.call.iso8601
        record = {
          "schema_version" => "soul.dashboard.music_job.v1", "job_id" => "job_#{@id_generator.call}",
          "operation" => operation, "project_id" => project_id.empty? ? nil : project_id, "candidate_id" => candidate_id.empty? ? nil : candidate_id,
          "chat_id" => chat_id.empty? ? nil : chat_id, "flow_id" => flow_id.empty? ? nil : flow_id,
          "request_digest" => digest, "status" => "accepted", "lifecycle_state" => "awaiting_input",
          "latest_progress" => { "stage" => "accepted", "message" => "Generation accepted by the bounded dashboard worker" },
          "created_at" => now, "updated_at" => now, "result" => nil
        }
        raise ArgumentError, "music job id is invalid" unless record["job_id"].match?(JOB_ID)
        raise ArgumentError, "music job id already exists" if read_record_unlocked(record.fetch("job_id"))
        write_record_unlocked(record)
        gate = Queue.new
        thread = Thread.new { gate.pop; execute(record.fetch("job_id"), request) }
        thread.report_on_exception = false
        @threads[record.fetch("job_id")] = thread
        gate << true
      end
      record
    end

    def active(project_id: nil)
      @mutex.synchronize do
        records_unlocked.select { |item| ACTIVE_STATES.include?(item["status"]) && (project_id.nil? || item["project_id"] == project_id) }
          .sort_by { |item| item["created_at"] }.reverse.map { |item| public_record(item) }
      end
    end

    def stream(job_id)
      raise ArgumentError, "music job id is invalid" unless job_id.to_s.match?(JOB_ID)
      queue = Queue.new
      Enumerator.new do |output|
        record = nil
        @mutex.synchronize do
          record = read_record_unlocked(job_id)
          raise ArgumentError, "music job was not found" unless record
          @subscribers[job_id] << queue if ACTIVE_STATES.include?(record["status"])
        end
        emit_snapshot(output, record)
        while ACTIVE_STATES.include?(record["status"])
          event = queue.pop
          output << JSON.generate(event) + "\n"
          record = event["record"] if event["record"]
          break if event["type"] == "result"
        end
      ensure
        @mutex.synchronize { @subscribers[job_id].delete(queue) }
      end
    end

    private

    def execute(job_id, request)
      update(job_id) { |record| record.merge("status" => "running", "lifecycle_state" => "awaiting_input") }
      progress = lambda do |event|
        update(job_id) { |record| record.merge("latest_progress" => safe_progress(event)) }
      end
      envelope = @facade.call(request, progress: progress)
      update(job_id) do |record|
        record.merge("status" => "terminal", "lifecycle_state" => envelope["lifecycle_state"].to_s,
          "result" => envelope, "latest_progress" => { "stage" => "complete", "message" => terminal_message(envelope) })
      end
    rescue StandardError => error
      envelope = failure_envelope(request, error)
      update(job_id) do |record|
        record.merge("status" => "terminal", "lifecycle_state" => "failed", "result" => envelope,
          "latest_progress" => { "stage" => "failed", "message" => "Music job failed safely: #{error.class}" })
      end
    ensure
      @mutex.synchronize { @threads.delete(job_id) }
    end

    def update(job_id)
      @mutex.synchronize do
        record = read_record_unlocked(job_id)
        return unless record
        updated = yield(record).merge("updated_at" => @clock.call.iso8601)
        write_record_unlocked(updated)
        event = if updated["status"] == "terminal"
          { "type" => "result", "envelope" => updated["result"], "record" => public_record(updated) }
        else
          { "type" => "progress", "event" => updated["latest_progress"], "record" => public_record(updated) }
        end
        @subscribers[job_id].each { |queue| queue << event }
      end
    end

    def emit_snapshot(output, record)
      if record["status"] == "terminal"
        output << JSON.generate({ "type" => "result", "envelope" => record["result"], "record" => public_record(record) }) + "\n"
      else
        output << JSON.generate({ "type" => "progress", "event" => record["latest_progress"], "record" => public_record(record) }) + "\n"
      end
    end

    def recover_interrupted!
      @mutex.synchronize do
        records_unlocked.each do |record|
          next unless ACTIVE_STATES.include?(record["status"])
          record["status"] = "terminal"
          record["lifecycle_state"] = "failed"
          record["latest_progress"] = { "stage" => "interrupted", "message" => "Dashboard process ended before the bounded job recorded completion" }
          record["result"] = failure_envelope({ "request_id" => "recovered-#{record['job_id']}", "operation" => record["operation"] }, RuntimeError.new("dashboard process interrupted"))
          record["updated_at"] = @clock.call.iso8601
          write_record_unlocked(record)
        end
      end
    end

    def records_unlocked
      Dir.glob(File.join(@directory, "job_*.json")).filter_map do |path|
        next unless File.file?(path) && !File.symlink?(path) && File.size(path) <= 256 * 1024
        JSON.parse(File.binread(path, 256 * 1024))
      rescue JSON::ParserError, Errno::ENOENT
        nil
      end
    end

    def read_record_unlocked(job_id)
      path = File.join(@directory, "#{job_id}.json")
      return nil unless File.file?(path) && !File.symlink?(path) && File.size(path) <= 256 * 1024
      JSON.parse(File.binread(path, 256 * 1024))
    rescue JSON::ParserError, Errno::ENOENT
      nil
    end

    def write_record_unlocked(record)
      path = File.join(@directory, "#{record.fetch('job_id')}.json")
      temporary = "#{path}.#{Process.pid}.tmp"
      File.write(temporary, JSON.pretty_generate(record) + "\n", mode: "w", perm: 0o600)
      File.rename(temporary, path)
      prune_unlocked
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && File.exist?(temporary)
    end

    def prune_unlocked
      terminal = records_unlocked.select { |item| item["status"] == "terminal" }.sort_by { |item| item["updated_at"] }.reverse
      terminal.drop(MAX_RECORDS).each { |item| FileUtils.rm_f(File.join(@directory, "#{item.fetch('job_id')}.json")) }
    end

    def public_record(record)
      record.slice("job_id", "operation", "project_id", "candidate_id", "chat_id", "flow_id", "status", "lifecycle_state", "latest_progress", "created_at", "updated_at")
    end

    def safe_progress(event)
      { "stage" => event.to_h["stage"].to_s.byteslice(0, 80), "message" => event.to_h["message"].to_s.byteslice(0, 500) }
    end

    def terminal_message(envelope)
      envelope.dig("data", "reason").to_s.empty? ? "Bounded music job reached a terminal state" : envelope.dig("data", "reason").to_s.byteslice(0, 500)
    end

    def failure_envelope(request, error)
      { "schema_version" => "soul.application.v1", "request_id" => request["request_id"].to_s,
        "operation" => request["operation"].to_s, "ok" => false, "lifecycle_state" => "failed", "data" => {},
        "errors" => [{ "code" => "music_job_failure", "message" => "Music job failed safely: #{error.class}" }],
        "warnings" => [], "meta" => { "mutation" => "none" } }
    end
  end
end
