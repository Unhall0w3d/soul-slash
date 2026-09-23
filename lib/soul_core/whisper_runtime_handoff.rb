# frozen_string_literal: true

require "json"
require "time"
require_relative "model_runtime_control_service"

module SoulCore
  # Foreground GPU borrowing. The control lock owns admission through recovery;
  # a durable pending receipt prevents silent reuse after a hard interruption.
  class WhisperRuntimeHandoff
    class Error < StandardError; end
    class Busy < Error; end
    GPU_UUID = "GPU-92d94102-e241-1a40-62c5-832d60874aab"
    WAIT_SECONDS = 15

    def initialize(root:, env:, gpu_uuid: GPU_UUID, control: nil, runner: BoundedCommandRunner.new,
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, sleeper: ->(s) { sleep(s) })
      @root, @gpu_uuid, @runner, @clock, @sleeper = File.expand_path(root), gpu_uuid, runner, clock, sleeper
      raise Error, "invalid GPU UUID" unless @gpu_uuid.match?(/\AGPU-[a-fA-F0-9-]+\z/)
      @control = control || ModelRuntimeControlService.new(root: @root, env: env)
      @pending = File.join(@root, "Soul/runtime/model_runtime/whisper-pending.json")
    end

    def run
      deadline = @clock.call + WAIT_SECONDS
      61.times do
        entered = false
        begin
          outcome = @control.with_controlled_observation do |before|
            entered = true
            check_pending!
            raise Busy, "model work is busy or activity is uncertain" unless admissible?(before)
            transaction(before) { yield }
          end
          return outcome if entered
          raise Error, outcome.fetch("reason", "runtime control unavailable") unless outcome["reason"] == "model runtime control is busy"
          raise Busy, "runtime control is busy"
        rescue Busy
          raise Error, "GPU transcription remained busy for 15 seconds; no work queued" if @clock.call >= deadline
          @sleeper.call(0.25)
        end
      end
      raise Error, "GPU transcription admission attempt limit exceeded; no work queued"
    end

    private

    def admissible?(before)
      return false unless before["active_work_count"] == 0 && before["active_leases"] == [] && !before["profile_conflict"]
      return false if before.fetch("profiles").any? { |p| !%w[active inactive].include?(p["service_state"]) }
      before["active_profile_count"] == 0 || before["idle_certain"] == true
    end

    def check_pending!
      directory = File.dirname(@pending)
      relative = directory.delete_prefix(@root + "/")
      cursor = @root
      relative.split("/").each do |part|
        cursor = File.join(cursor, part)
        stat = File.lstat(cursor)
        raise Error, "unsafe runtime state directory" unless stat.directory? && !stat.symlink? && stat.uid == Process.uid
      end
      raise Error, "unfinished Whisper transaction requires explicit recovery review" if File.exist?(@pending) || File.symlink?(@pending)
    end

    def gpu_rows
      result = @runner.run("nvidia-smi", "--query-compute-apps=pid,gpu_uuid,used_gpu_memory", "--format=csv,noheader,nounits", timeout_seconds: 5, max_output_bytes: 16384)
      raise Error, "GPU ownership unavailable" unless result.success? && !result.truncated
      rows = result.stdout.lines.map { |line| line.strip.split(/\s*,\s*/) }
      raise Error, "GPU ownership malformed" unless rows.all? { |r| r.size == 3 && r[0].match?(/\A[1-9][0-9]*\z/) && r[1].match?(/\AGPU-[a-fA-F0-9-]+\z/) && r[2].match?(/\A[0-9]+\z/) }
      rows.select { |r| r[1] == @gpu_uuid }
    end

    def verify_free!
      raise Error, "NVIDIA compute allocation remains; refusing overlap" unless gpu_rows.empty?
      result = @runner.run("nvidia-smi", "--id=#{@gpu_uuid}", "--query-gpu=uuid,memory.free", "--format=csv,noheader,nounits", timeout_seconds: 5, max_output_bytes: 1024)
      row = result.stdout.strip.split(/\s*,\s*/)
      raise Error, "insufficient or unverified NVIDIA memory" unless result.success? && !result.truncated && row.size == 2 && row[0] == @gpu_uuid && row[1].match?(/\A[0-9]+\z/) && row[1].to_i >= 5000
    end

    def wait_free!
      deadline = @clock.call + 5
      loop do
        return verify_free! if gpu_rows.empty?
        raise Error, "NVIDIA allocation did not clear before cleanup deadline" if @clock.call >= deadline
        @sleeper.call(0.1)
      end
    end

    def transaction(before)
      target = before.fetch("profiles").find { |p| p["service_state"] == "active" && p.fetch("accelerator", "").downcase.include?("nvidia") }
      prior = nil
      identity = nil
      if target
        raise Error, "unsupported NVIDIA profile" unless target["id"] == "nvidia-fallback" && target["service"] == "llama-server.service"
        prior = @control.send(:observe_nvidia_allocation, target)
        raise Error, "Qwen placement is not qualified" unless prior && prior["gpu_uuid"] == @gpu_uuid && prior["memory_mib"] >= 4500
        identity = model_identity(target)
      else
        verify_free!
      end
      receipt = {"schema_version"=>"soul.whisper_transaction.v1", "pid"=>Process.pid, "started_at"=>Time.now.utc.iso8601,
                 "prior_profile"=>target && target["id"], "gpu_uuid"=>@gpu_uuid, "prior_gpu"=>prior}
      timings = {}
      File.open(@pending, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(JSON.generate(receipt)); f.flush; f.fsync }
      File.open(File.dirname(@pending), File::RDONLY) { |f| f.fsync }
      work_error = recovery_error = nil
      value = nil
      work_started = false
      begin
        stage_started = @clock.call
        if target
          stopped = @control.send(:service_command, "stop", target)
          raise Error, "Qwen stop was not verified" unless stopped.success? && @control.send(:observe_service_state, target["service"]) == "inactive"
        end
        wait_free!
        timings["release_ms"] = ((@clock.call - stage_started) * 1000).round
        work_started = true
        stage_started = @clock.call
        value = yield
        timings["recognition_ms"] = ((@clock.call - stage_started) * 1000).round
      rescue Exception => error
        work_error = error
      ensure
        begin
          stage_started = @clock.call
          rows = gpu_rows
          unchanged = target && !work_started && rows.size == 1 && rows[0][0].to_i == prior["pid"] && @control.send(:observe_service_state, target["service"]) == "active"
          unless unchanged
            wait_free!
            if target
              problem = @control.send(:restore_temporary_profile, target, expected_gpu: prior)
              raise Error, problem if problem
            end
          end
          if target
            allocation = @control.send(:observe_nvidia_allocation, target)
            raise Error, "Qwen model identity or allocation was not restored" unless allocation && allocation["gpu_uuid"] == @gpu_uuid && allocation["memory_mib"] >= prior["memory_mib"] * 0.9 && model_identity(target) == identity
          end
          File.unlink(@pending)
          File.open(File.dirname(@pending), File::RDONLY) { |f| f.fsync }
          timings["recovery_ms"] = ((@clock.call - stage_started) * 1000).round
        rescue StandardError => error
          recovery_error = error
        end
      end
      raise Error, "recovery incomplete; pending receipt retained: #{recovery_error.message}" if recovery_error
      raise work_error if work_error
      [value, receipt.merge("restored"=>true, "released_qwen"=>!target.nil?, "timings"=>timings)]
    end

    def model_identity(target)
      uri = URI(target.fetch("endpoint").sub(%r{/v1/?\z}, "") + "/props")
      raw = @control.send(:bounded_http_get, uri)
      raise Error, "Qwen model identity endpoint unavailable" unless raw.is_a?(Hash) && raw[:status] == 200
      value = JSON.parse(raw.fetch(:body))
      identity = value.slice("model_path", "model_alias", "total_slots")
      raise Error, "Qwen model identity unavailable" unless identity["model_path"].to_s.end_with?("/Qwen3-8B-Q4_K_M.gguf") && identity["model_alias"] == "soul-local-chat" && identity["total_slots"] == 1
      identity
    end
  end
end
