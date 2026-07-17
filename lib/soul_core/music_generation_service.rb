# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "timeout"
require "time"
require_relative "bounded_command_runner"
require_relative "music_project_store"
require_relative "music_resource_coordinator"

module SoulCore
  class MusicGenerationService
    CONFIRMATION = "START_MUSIC_GENERATION"
    MAX_LOG_BYTES = 2 * 1024 * 1024
    MP3_ARGUMENTS = %w[-map_metadata -1 -codec:a libmp3lame -q:a 2].freeze

    ProcessResult = Struct.new(:status, :stdout, :stderr, :exit_status, :pid, keyword_init: true) do
      def success? = status == "ok"
    end

    class ForegroundProcessRunner
      def run(command, env:, chdir:, timeout_seconds:, max_output_bytes:, on_spawn:, canceled:, progress: nil)
        stdout = +""; stderr = +""; process_status = nil; state = "failed"; pid = nil
        Open3.popen3(env, *command, chdir: chdir, pgroup: true) do |stdin, out, err, wait|
          stdin.close
          pid = wait.pid
          begin
            on_spawn.call(pid, pid)
          rescue StandardError
            terminate_group(pid, wait)
            raise
          end
          events = SizedQueue.new(128)
          readers = [[out, stdout, "stdout"], [err, stderr, "stderr"]].map { |io, buffer, source| bounded_reader(io, buffer, max_output_bytes, events, source) }
          interrupted = false
          previous_int = previous_term = nil
          if Thread.current == Thread.main
            previous_int = Signal.trap("INT") do
              interrupted = true
              Process.kill("TERM", -pid) rescue nil
            end
            previous_term = Signal.trap("TERM") do
              interrupted = true
              Process.kill("TERM", -pid) rescue nil
            end
          end
          begin
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Float(timeout_seconds)
            until wait.join(0.1)
              drain_progress(events, progress)
              raise Interrupt, "music generation canceled" if canceled.call
              raise Timeout::Error if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            end
            process_status = wait.value
            drain_progress(events, progress)
            state = process_status.success? ? "ok" : ((interrupted || canceled.call) ? "canceled" : "failed")
          rescue Interrupt
            state = "canceled"
            terminate_group(pid, wait)
            process_status = wait.value
          rescue Timeout::Error
            state = "canceled"
            terminate_group(pid, wait)
            process_status = wait.value
          rescue StandardError
            terminate_group(pid, wait)
            raise
          ensure
            Signal.trap("INT", previous_int) if previous_int
            Signal.trap("TERM", previous_term) if previous_term
            readers.each { |reader| reader.join(2) || reader.kill }
          end
        end
        ProcessResult.new(status: state, stdout: safe_text(stdout, max_output_bytes), stderr: safe_text(stderr, max_output_bytes), exit_status: process_status&.exitstatus, pid: pid)
      rescue Errno::ENOENT => error
        ProcessResult.new(status: "unavailable", stdout: "", stderr: error.message, exit_status: nil, pid: pid)
      rescue StandardError => error
        ProcessResult.new(status: "failed", stdout: "", stderr: "#{error.class}: #{error.message}", exit_status: nil, pid: pid)
      end

      private

      def bounded_reader(io, buffer, maximum, events, source)
        Thread.new do
          loop do
            chunk = io.readpartial(16 * 1024)
            remaining = maximum - buffer.bytesize
            buffer << chunk.byteslice(0, remaining) if remaining.positive?
            begin
              events.push({ "stage" => "model", "source" => source, "message" => safe_text(chunk, 2_000) }, true)
            rescue ThreadError
              nil # The bounded progress queue may drop display-only output; the full bounded log remains captured.
            end
          end
        rescue EOFError, IOError
          nil
        end
      end

      def drain_progress(events, progress)
        return unless progress
        32.times do
          event = events.pop(true)
          progress.call(event)
        rescue ThreadError
          break
        end
      end

      def terminate_group(pid, wait)
        Process.kill("TERM", -pid) rescue nil
        return if wait.join(5)
        Process.kill("KILL", -pid) rescue nil
        wait.join
      end

      def safe_text(value, maximum)
        value.to_s.byteslice(0, maximum).to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
      end
    end

    def initialize(root: Dir.pwd, music_root: File.join(Dir.home, ".local", "share", "soul", "music"), manifest_path: File.expand_path("../../config/music_pilot_models.json", __dir__), project_store: nil, coordinator: nil, process_runner: ForegroundProcessRunner.new, runner: BoundedCommandRunner.new, clock: -> { Time.now.utc })
      @root = File.expand_path(root)
      @music_root = File.expand_path(music_root)
      @manifest_path = File.expand_path(manifest_path)
      @store = project_store || MusicProjectStore.new(root: @root)
      @runner = runner
      @coordinator = coordinator || MusicResourceCoordinator.new(root: @root, runner: runner)
      @process_runner = process_runner
      @clock = clock
      @manifest = load_manifest
      @source = @manifest.fetch("source")
      @dit_name = @manifest.fetch("dit_models").keys.first
      @lm_name = @manifest.fetch("lm_models").keys.first
      @source_dir = File.join(@music_root, "ace-step", @source.fetch("release"))
    end

    def create_project(attributes)
      project = @store.create(attributes)
      outcome("complete", true, "music project created", data: { "project" => project, "input_digest" => @store.input_digest(project) }, mutation: "music_project_created")
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def list_projects(limit: 100)
      projects = @store.list(limit: limit)
      outcome("complete", true, "music projects inspected", data: { "projects" => projects, "count" => projects.length })
    rescue ArgumentError, MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def inspect_project(project_id:)
      project = @store.read(project_id)
      generations = Dir.children(@store.generations_path(project_id)).grep(MusicProjectStore::CANDIDATE_ID).sort.filter_map do |candidate_id|
        candidate = read_candidate(project_id, candidate_id)
        candidate&.merge("review" => @store.read_review(project_id, candidate_id))
      end
      outcome("complete", true, "music project inspected", data: { "project" => project, "input_digest" => @store.input_digest(project), "generations" => generations })
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def resource_inventory = @coordinator.inventory

    def generation_preview(project_id:)
      project = @store.read(project_id)
      candidate_id = @store.candidate_id
      inventory = @coordinator.inventory
      return inventory unless inventory["lifecycle_state"] == "complete"
      scope = generation_scope(project, candidate_id)
      blockers = inventory.fetch("blockers", []) + environment_blockers
      return outcome("blocked_for_human_review", false, blockers.join("; "), data: { "resource_inventory" => inventory }) unless blockers.empty?
      outcome("blocked_for_human_review", true, "exact generation confirmation required", data: {
        "project" => project,
        "candidate_id" => candidate_id,
        "confirmation_phrase" => CONFIRMATION,
        "expected_digest" => Digest::SHA256.hexdigest(JSON.generate(scope)),
        "preview_scope" => scope,
        "resource_inventory" => inventory
      })
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def generation_execute(project_id:, candidate_id:, confirmation:, expected_digest:, progress: nil)
      progress&.call({ "stage" => "validation", "message" => "Validating exact project scope" })
      return outcome("awaiting_input", false, "confirmation and expected_digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      return outcome("awaiting_input", false, "candidate_id is invalid") unless candidate_id.to_s.match?(MusicProjectStore::CANDIDATE_ID)
      project = @store.read(project_id)
      scope = generation_scope(project, candidate_id)
      return outcome("blocked_for_human_review", false, "exact generation confirmation did not match") unless confirmation == CONFIRMATION
      return outcome("blocked_for_human_review", false, "music generation state changed; preview again") unless secure_compare(expected_digest, Digest::SHA256.hexdigest(JSON.generate(scope)))
      blockers = environment_blockers
      return outcome("blocked_for_human_review", false, blockers.join("; ")) unless blockers.empty?
      progress&.call({ "stage" => "checkpoints", "message" => "Verifying pinned local checkpoints" })
      verify_checkpoints!

      generations = @store.generations_path(project_id)
      target = File.join(generations, candidate_id)
      staging = File.join(generations, ".#{candidate_id}.partial")
      return outcome("blocked_for_human_review", false, "candidate output already exists") if File.exist?(target) || File.symlink?(target) || File.exist?(staging) || File.symlink?(staging)
      Dir.mkdir(staging, 0o700)
      input = @store.input_payload(project)
      input_path = File.join(staging, "input.json")
      File.write(input_path, JSON.pretty_generate(input) + "\n", mode: "wx", perm: 0o600)
      progress&.call({ "stage" => "resources", "message" => "Acquiring the bounded NVIDIA music lane" })
      lease = @coordinator.acquire(project_id: project_id, candidate_id: candidate_id, input_digest: @store.input_digest(project), ttl_seconds: project.fetch("target_duration_seconds") + 240)
      progress&.call({ "stage" => "model", "message" => "Generating the candidate in the foreground" })
      generation = run_generation(project, input_path, staging, lease, progress)
      return quarantined_outcome(generation.status == "canceled" ? "canceled" : "failed", staging, generation, lease) unless generation.success?

      log = generation.stdout.to_s + generation.stderr.to_s
      File.write(File.join(staging, "generation.log"), log, mode: "wx", perm: 0o600)
      return quarantined_outcome("failed", staging, generation, lease, "ACE-Step reported a generation failure") if log.match?(/Generation failed|  FAILED:|Traceback \(most recent call last\)/)
      flac_sources = Dir.glob(File.join(staging, "**", "*.flac")).select { |path| File.file?(path) && File.size(path).positive? }
      return quarantined_outcome("failed", staging, generation, lease, "generation did not produce exactly one FLAC") unless flac_sources.one?
      flac_path = File.join(staging, "master.flac")
      File.rename(flac_sources.first, flac_path)
      progress&.call({ "stage" => "validation", "message" => "Inspecting the lossless master" })
      flac = inspect_audio(flac_path, "flac", project.fetch("target_duration_seconds"))

      mp3_path = File.join(staging, "listening.mp3")
      progress&.call({ "stage" => "transcode", "message" => "Deriving the MP3 listening copy" })
      transcode = run_transcode(flac_path, mp3_path, staging, lease, project.fetch("target_duration_seconds"), progress)
      return quarantined_outcome(transcode.status == "canceled" ? "canceled" : "failed", staging, transcode, lease, "MP3 derivation failed") unless transcode.success?
      mp3 = inspect_audio(mp3_path, "mp3", project.fetch("target_duration_seconds")).merge(
        "derived_from_sha256" => flac.fetch("sha256"),
        "encoder" => "ffmpeg/libmp3lame",
        "encoder_arguments" => MP3_ARGUMENTS
      )
      receipt = {
        "schema_version" => "soul.music.generation.v1",
        "candidate_id" => candidate_id,
        "project_id" => project_id,
        "lifecycle_state" => "blocked_for_human_review",
        "created_at" => @clock.call.iso8601,
        "input_digest" => @store.input_digest(project),
        "model_profile" => model_profile,
        "resource_receipt" => {
          "lane" => "nvidia-music",
          "lease_id" => lease.fetch("lease_id"),
          "amd_conversation_preserved" => true,
          "automatic_model_load" => false,
          "automatic_model_unload" => false
        },
        "artifacts" => {
          "flac" => flac.merge("path" => "master.flac"),
          "mp3" => mp3.merge("path" => "listening.mp3")
        },
        "human_review_required" => true
      }
      remove_nested_generation_directories(staging)
      published = @store.publish_candidate(project_id, candidate_id, staging, receipt)
      progress&.call({ "stage" => "review", "message" => "Candidate ready for Operator listening review" })
      outcome("blocked_for_human_review", true, "music candidate generated; listening review required", data: { "candidate" => receipt, "candidate_path" => published }, mutation: "music_candidate_created")
    rescue MusicResourceCoordinator::Busy => error
      outcome("blocked_for_human_review", false, error.message)
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, MusicResourceCoordinator::IntegrityError, KeyError, SystemCallError, JSON::ParserError => error
      outcome("blocked_for_human_review", false, error.message)
    ensure
      @coordinator.release(lease["lease_id"]) if defined?(lease) && lease
    end

    def cancel_preview(candidate_id:) = @coordinator.cancel_preview(candidate_id: candidate_id)
    def cancel_execute(candidate_id:, confirmation:, expected_digest:) = @coordinator.cancel_execute(candidate_id: candidate_id, confirmation: confirmation, expected_digest: expected_digest)

    def record_review(project_id:, candidate_id:, review:)
      record = @store.record_review(project_id: project_id, candidate_id: candidate_id, attributes: review)
      outcome("complete", true, "music candidate review recorded", data: { "review" => record }, mutation: "music_candidate_review_recorded")
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def artifact_path(project_id:, candidate_id:, artifact:)
      @store.candidate_artifact_path(project_id, candidate_id, artifact)
    end

    private

    def generation_scope(project, candidate_id)
      {
        "operation" => "music_generation",
        "project_id" => project.fetch("project_id"),
        "candidate_id" => candidate_id,
        "input_digest" => @store.input_digest(project),
        "duration_seconds" => project.fetch("target_duration_seconds"),
        "seed" => project.fetch("seed"),
        "model_profile" => model_profile,
        "artifacts" => { "master" => "FLAC 48kHz stereo", "proxy" => "MP3 LAME V2 derived from master" },
        "resource_lane" => "nvidia-music",
        "timeout_seconds" => project.fetch("target_duration_seconds") + 180,
        "persistent_service" => false,
        "network_listener" => false,
        "automatic_download" => false
      }
    end

    def model_profile
      {
        "source_release" => @source.fetch("release"),
        "source_revision" => @source.fetch("revision"),
        "dit_model" => @dit_name,
        "lm_model" => @lm_name,
        "dtype" => "float32",
        "quantization" => "int8_weight_only",
        "cpu_offload" => true,
        "inference_steps" => 8
      }
    end

    def environment_blockers
      items = []
      items << "pinned ACE-Step source is missing" unless File.directory?(File.join(@source_dir, ".git")) && !File.symlink?(@source_dir)
      items << "Music Python environment is missing" unless File.executable?(File.join(@source_dir, ".venv", "bin", "python"))
      revision = @runner.run("git", "rev-parse", "HEAD", timeout_seconds: 10, max_output_bytes: 1024, chdir: @source_dir)
      items << "ACE-Step source revision does not match the pinned manifest" unless revision.success? && revision.stdout.to_s.strip == @source.fetch("revision")
      overlays = {
        File.join(@source_dir, "acestep", "core", "generation", "handler", "init_service_orchestrator.py") => "SOUL_PASCAL_FP32_OVERLAY_V1",
        File.join(@source_dir, "acestep", "core", "generation", "handler", "init_service_downloads.py") => "SOUL_STRICT_OFFLINE_OVERLAY_V1",
        File.join(@source_dir, "profile_inference.py") => "SOUL_RETAIN_OUTPUT_OVERLAY_V2"
      }
      overlays.each do |path, marker|
        items << "required ACE-Step compatibility overlay is missing" unless File.file?(path) && !File.symlink?(path) && File.size(path) <= 512 * 1024 && File.read(path, 512 * 1024).include?(marker)
      end
      %w[ffmpeg ffprobe nvidia-smi systemctl].each { |tool| items << "required tool #{tool} is missing" unless @runner.which(tool) }
      items
    end

    def run_generation(project, input_path, staging, lease, progress)
      python = File.join(@source_dir, ".venv", "bin", "python")
      command = [python, "profile_inference.py", "--device", "cuda", "--lm-backend", "pt", "--config-path", @dit_name, "--lm-model", @lm_name, "--offload-to-cpu", "--offload-dit-to-cpu", "--quantization", "int8_weight_only", "--example", input_path, "--duration", project.fetch("target_duration_seconds").to_s, "--batch-size", "1", "--seed", project.fetch("seed").to_s, "--no-warmup"]
      process(command, staging, lease, project.fetch("target_duration_seconds") + 180, {
        "TMPDIR" => staging,
        "HF_HUB_OFFLINE" => "1",
        "TRANSFORMERS_OFFLINE" => "1",
        "HF_DATASETS_OFFLINE" => "1",
        "SOUL_ACESTEP_STRICT_OFFLINE" => "1",
        "SOUL_ACESTEP_RETAIN_OUTPUT" => "1",
        "ACESTEP_DTYPE" => "float32"
      }, chdir: @source_dir, progress: progress)
    end

    def run_transcode(flac, mp3, staging, lease, duration, progress)
      command = [@runner.which("ffmpeg") || "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-i", flac, *MP3_ARGUMENTS, mp3]
      process(command, staging, lease, [duration, 120].min, {}, chdir: staging, progress: progress)
    end

    def process(command, staging, lease, timeout, env, chdir:, progress: nil)
      options = { env: env, chdir: chdir, timeout_seconds: timeout, max_output_bytes: MAX_LOG_BYTES,
        on_spawn: ->(pid, pgid) { @coordinator.attach_child(lease_id: lease.fetch("lease_id"), child_pid: pid, process_group_id: pgid) },
        canceled: -> { @coordinator.cancellation_requested?(lease.fetch("lease_id")) } }
      options[:progress] = progress if progress
      @process_runner.run(command, **options)
    end

    def inspect_audio(path, codec, expected_duration)
      raise MusicProjectStore::IntegrityError, "#{codec} artifact is missing" unless File.file?(path) && !File.symlink?(path) && File.size(path).positive?
      probe = @runner.run(@runner.which("ffprobe") || "ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_name,sample_rate,channels", "-of", "json", path, timeout_seconds: 15, max_output_bytes: 32 * 1024)
      raise MusicProjectStore::IntegrityError, "#{codec} probe failed" unless probe.success?
      data = JSON.parse(probe.stdout)
      stream = Array(data["streams"]).find { |item| item["codec_name"] == codec }
      duration = Float(data.dig("format", "duration"))
      raise MusicProjectStore::IntegrityError, "#{codec} stream is invalid" unless stream && Integer(stream["sample_rate"]) == 48_000 && Integer(stream["channels"]) == 2
      raise MusicProjectStore::IntegrityError, "#{codec} duration is invalid" if (duration - expected_duration).abs > 1.0
      volume = @runner.run(@runner.which("ffmpeg") || "ffmpeg", "-nostdin", "-hide_banner", "-i", path, "-af", "volumedetect", "-f", "null", "/dev/null", timeout_seconds: 30, max_output_bytes: 64 * 1024)
      output = volume.stdout.to_s + volume.stderr.to_s
      raise MusicProjectStore::IntegrityError, "#{codec} artifact is silent or volume inspection failed" unless output.match?(/mean_volume:\s*(?!-inf)[-0-9.]+ dB/)
      { "bytes" => File.size(path), "sha256" => Digest::SHA256.file(path).hexdigest, "codec" => codec, "duration_seconds" => duration, "sample_rate" => 48_000, "channels" => 2 }
    end

    def verify_checkpoints!
      groups = [[@manifest.fetch("dit_models").fetch(@dit_name), File.join(@source_dir, "checkpoints")], [@manifest.fetch("lm_models").fetch(@lm_name), File.join(@source_dir, "checkpoints", @lm_name)]]
      groups.each do |model, base|
        model.fetch("files").each do |path, bytes, sha|
          target = File.join(base, path)
          raise MusicProjectStore::IntegrityError, "missing or invalid checkpoint #{path}" unless File.file?(target) && !File.symlink?(target) && File.size(target) == bytes && Digest::SHA256.file(target).hexdigest == sha
        end
      end
    end

    def read_candidate(project_id, candidate_id)
      path = File.join(@store.generations_path(project_id), candidate_id, "candidate.json")
      return nil unless File.file?(path) && !File.symlink?(path) && File.size(path) <= MusicProjectStore::MAX_PROJECT_BYTES
      data = JSON.parse(File.binread(path, MusicProjectStore::MAX_PROJECT_BYTES))
      data if data["schema_version"] == "soul.music.generation.v1" && data["candidate_id"] == candidate_id
    rescue JSON::ParserError, Errno::ENOENT
      nil
    end

    def quarantined_outcome(state, staging, result, lease, reason = nil)
      payload = { "schema_version" => "soul.music.generation_failure.v1", "lifecycle_state" => state, "reason" => reason || "music generation #{result.status}", "exit_status" => result.exit_status, "recorded_at" => @clock.call.iso8601, "lease_id" => lease.fetch("lease_id") }
      File.write(File.join(staging, "failure.json"), JSON.pretty_generate(payload) + "\n", mode: "w", perm: 0o600)
      File.write(File.join(staging, "failure.log"), (result.stdout.to_s + result.stderr.to_s).byteslice(0, MAX_LOG_BYTES), mode: "w", perm: 0o600)
      outcome(state, false, payload.fetch("reason"), data: { "quarantine_path" => staging, "exit_status" => result.exit_status }, mutation: "music_candidate_quarantined")
    end

    def remove_nested_generation_directories(staging)
      Dir.children(staging).each do |name|
        path = File.join(staging, name)
        FileUtils.rm_rf(path) if File.directory?(path) && !File.symlink?(path)
      end
    end

    def load_manifest
      stat = File.lstat(@manifest_path)
      raise MusicProjectStore::IntegrityError, "music manifest must be a regular file" unless stat.file? && !stat.symlink?
      JSON.parse(File.read(@manifest_path))
    rescue Errno::ENOENT, JSON::ParserError => error
      raise MusicProjectStore::IntegrityError, "invalid music manifest: #{error.class}"
    end

    def secure_compare(left, right)
      return false unless left.to_s.bytesize == right.to_s.bytesize
      left.to_s.bytes.zip(right.to_s.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    end

    def outcome(state, ok, reason, data: {}, mutation: "none")
      { "ok" => ok, "lifecycle_state" => state, "reason" => reason, "data" => data || {}, "mutation" => mutation }
    end
  end
end
