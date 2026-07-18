# frozen_string_literal: true

require "digest"
require "etc"
require "fileutils"
require "json"
require "time"
require_relative "bounded_command_runner"
require_relative "music_generation_service"
require_relative "music_project_store"

module SoulCore
  class MusicCandidateAnalysisService
    CONFIRMATION = "ANALYZE_MUSIC_CANDIDATE"
    TIMEOUT_SECONDS = 360
    MAX_JSON_BYTES = 8 * 1024 * 1024
    MAX_LOG_BYTES = 512 * 1024
    MAX_ALIGNMENT_CELLS = 6_000_000

    def initialize(root: Dir.pwd, music_root: File.join(Dir.home, ".local", "share", "soul", "music"), manifest_path: File.expand_path("../../config/music_transcription_models.json", __dir__), project_store: nil, process_runner: MusicGenerationService::ForegroundProcessRunner.new, runner: BoundedCommandRunner.new, clock: -> { Time.now.utc })
      @root = File.expand_path(root)
      @music_root = File.expand_path(music_root)
      @manifest_path = File.expand_path(manifest_path)
      @store = project_store || MusicProjectStore.new(root: @root)
      @process_runner = process_runner
      @runner = runner
      @clock = clock
      @manifest = load_manifest
      @runtime = @manifest.fetch("runtime")
      @model_name, @model = @manifest.fetch("models").first
      @install_dir = File.join(@music_root, "transcription", @runtime.fetch("release"))
    end

    def preview(project_id:, candidate_id:)
      project, audio = validate_candidate(project_id, candidate_id)
      scope = analysis_scope(project, candidate_id, audio)
      blockers = environment_blockers
      return outcome("blocked_for_human_review", false, blockers.join("; "), data: { "blockers" => blockers }) unless blockers.empty?
      outcome("blocked_for_human_review", true, "exact foreground vocal analysis confirmation required", data: {
        "confirmation_phrase" => CONFIRMATION,
        "expected_digest" => Digest::SHA256.hexdigest(JSON.generate(scope)),
        "preview_scope" => scope
      })
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def execute(project_id:, candidate_id:, confirmation:, expected_digest:, progress: nil)
      project, audio = validate_candidate(project_id, candidate_id)
      scope = analysis_scope(project, candidate_id, audio)
      return outcome("awaiting_input", false, "confirmation and expected_digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      return outcome("blocked_for_human_review", false, "exact vocal analysis confirmation did not match") unless confirmation == CONFIRMATION
      digest = Digest::SHA256.hexdigest(JSON.generate(scope))
      return outcome("blocked_for_human_review", false, "candidate analysis state changed; preview again") unless secure_compare(expected_digest, digest)
      blockers = environment_blockers
      return outcome("blocked_for_human_review", false, blockers.join("; ")) unless blockers.empty?

      candidate_dir = File.dirname(audio)
      staging = File.join(candidate_dir, ".analysis.partial-#{Process.pid}")
      raise MusicProjectStore::IntegrityError, "candidate analysis is already running" if Dir.glob(File.join(candidate_dir, ".analysis.partial-*")).any?
      Dir.mkdir(staging, 0o700)
      output_base = File.join(staging, "whisper")
      progress&.call("stage" => "transcription", "message" => "Loading the CPU transcription model for this candidate only")
      command = [binary_path, "--model", model_path, "--file", audio, "--threads", thread_count.to_s, "--language", @model.fetch("language"), "--no-gpu", "--output-json-full", "--output-file", output_base, "--print-progress"]
      result = @process_runner.run(command, env: { "LD_LIBRARY_PATH" => @install_dir }, chdir: candidate_dir, timeout_seconds: TIMEOUT_SECONDS, max_output_bytes: MAX_LOG_BYTES,
        on_spawn: ->(_pid, _pgid) {}, canceled: -> { false }, progress: progress)
      return failure_outcome(result, staging) unless result.success?

      transcript_path = "#{output_base}.json"
      raise MusicProjectStore::IntegrityError, "transcription output is missing" unless File.file?(transcript_path) && !File.symlink?(transcript_path) && File.size(transcript_path).between?(1, MAX_JSON_BYTES)
      whisper = JSON.parse(File.binread(transcript_path, MAX_JSON_BYTES))
      progress&.call("stage" => "comparison", "message" => "Comparing machine-heard words with the supplied lyric sequence")
      segments = transcript_segments(whisper)
      transcript = transcript_text(segments)
      alignment = align_lyrics(project.fetch("lyrics"), transcript)
      evidence = {
        "schema_version" => "soul.music.candidate_analysis.v1",
        "project_id" => project.fetch("project_id"),
        "candidate_id" => candidate_id,
        "created_at" => @clock.call.iso8601,
        "lifecycle_state" => "blocked_for_human_review",
        "machine_route" => alignment.fetch("machine_route"),
        "next_gate" => alignment.fetch("machine_route") == "human_listening_test" ? "human_listening_test" : "operator_triggered_revision_attempt",
        "disclaimer" => "Machine-heard evidence is fallible and never constitutes human approval or rejection.",
        "runtime" => { "name" => @runtime.fetch("name"), "release" => @runtime.fetch("release"), "model" => @model_name, "cpu_only" => true, "threads" => thread_count, "timeout_seconds" => TIMEOUT_SECONDS, "resident_after_completion" => false },
        "audio_sha256" => Digest::SHA256.file(audio).hexdigest,
        "intended_lyrics" => project.fetch("lyrics"),
        "machine_heard_lyrics" => transcript,
        "machine_heard_formatted" => formatted_transcript(segments),
        "segments" => segments,
        "alignment" => alignment
      }
      write_json(File.join(staging, "analysis.json"), evidence)
      File.write(File.join(staging, "transcription.log"), (result.stdout.to_s + result.stderr.to_s).byteslice(0, MAX_LOG_BYTES), mode: "wx", perm: 0o600)
      publish_analysis(candidate_dir, staging)
      progress&.call("stage" => "complete", "message" => alignment.fetch("machine_route") == "human_listening_test" ? "Machine pass complete; human listening test is next" : "Machine pass found likely drift; an Operator-triggered revision attempt is next")
      outcome("blocked_for_human_review", true, "candidate vocal analysis complete; human authority preserved", data: { "analysis" => evidence }, mutation: "music_candidate_analysis_recorded")
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, JSON::ParserError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    ensure
      FileUtils.rm_rf(staging) if defined?(staging) && staging && File.directory?(staging)
    end

    def read(project_id:, candidate_id:)
      candidate_dir = File.dirname(@store.candidate_artifact_path(project_id, candidate_id, "flac"))
      path = File.join(candidate_dir, "analysis", "analysis.json")
      return nil unless File.file?(path) && !File.symlink?(path) && File.size(path).between?(1, MAX_JSON_BYTES)
      project_current_alignment(JSON.parse(File.binread(path, MAX_JSON_BYTES)))
    rescue JSON::ParserError => error
      raise MusicProjectStore::IntegrityError, "invalid candidate analysis: #{error.class}"
    end

    private

    def validate_candidate(project_id, candidate_id)
      project = @store.read(project_id)
      raise MusicProjectStore::ValidationError, "instrumental candidates have no vocals to analyze" unless project.fetch("vocal_mode") == "vocal"
      raise MusicProjectStore::ValidationError, "candidate_id is invalid" unless candidate_id.to_s.match?(MusicProjectStore::CANDIDATE_ID)
      [project, @store.candidate_artifact_path(project_id, candidate_id, "flac")]
    end

    def analysis_scope(project, candidate_id, audio)
      { "operation" => "music_candidate_vocal_analysis", "project_id" => project.fetch("project_id"), "candidate_id" => candidate_id, "audio_sha256" => Digest::SHA256.file(audio).hexdigest, "lyrics_sha256" => Digest::SHA256.hexdigest(project.fetch("lyrics")), "runtime" => @runtime.slice("name", "release"), "model" => @model_name, "resource_lane" => "cpu-foreground", "threads" => thread_count, "timeout_seconds" => TIMEOUT_SECONDS, "persistent_service" => false, "network_listener" => false, "automatic_retry" => false, "automatic_revision" => false }
    end

    def environment_blockers
      items = []
      items << "pinned whisper.cpp binary is missing" unless File.executable?(binary_path) && !File.symlink?(binary_path)
      items << "pinned transcription model is missing" unless File.file?(model_path) && !File.symlink?(model_path)
      if items.empty?
        items << "transcription model byte count does not match" unless File.size(model_path) == @model.fetch("bytes")
        items << "transcription model digest does not match" unless Digest::SHA256.file(model_path).hexdigest == @model.fetch("sha256")
      end
      items
    end

    def binary_path = File.join(@install_dir, @runtime.fetch("binary"))
    def model_path = File.join(@install_dir, @model_name)
    def thread_count = [[Etc.nprocessors / 2, 1].max, 8].min

    def transcript_text(segments)
      segments.map { |item| item.fetch("text") }.join(" ").gsub(/\s+/, " ").strip
    end

    def transcript_segments(data)
      Array(data["transcription"]).filter_map do |item|
        text = item["text"].to_s.strip
        next if text.empty?
        offsets = item["offsets"] || {}
        { "start_ms" => offsets["from"], "end_ms" => offsets["to"], "text" => text }
      end
    end

    def formatted_transcript(segments)
      previous_end = nil
      segments.flat_map do |segment|
        gap = previous_end && segment["start_ms"].to_i - previous_end.to_i >= 5_000
        previous_end = segment["end_ms"]
        gap ? ["", segment.fetch("text")] : [segment.fetch("text")]
      end.join("\n").strip
    end

    def align_lyrics(intended, heard)
      lines = intended.lines.map(&:strip).reject { |line| line.empty? || line.match?(/\A\[[^\]]+\]\z/) }
      heard_words = words(heard)
      line_words = lines.map { |line| words(line) }
      intended_words = line_words.flatten
      matched = lcs_word_matches(intended_words, heard_words)
      offset = 0
      line_results = lines.each_with_index.map do |line, index|
        target = line_words[index]
        matched_count = matched[offset, target.length].to_a.count(true)
        offset += target.length
        score = target.empty? ? 0.0 : matched_count.fdiv(target.length)
        status = score >= 0.75 ? "heard" : (score >= 0.4 ? "partial" : "not_heard")
        { "intended" => line, "status" => status, "sequence_recall" => score.round(3) }
      end
      recall = intended_words.empty? ? 0.0 : matched.count(true).fdiv(intended_words.length)
      problem_lines = line_results.count { |item| item["status"] != "heard" }
      route = recall >= 0.72 && problem_lines <= [1, (line_results.length * 0.2).floor].max ? "human_listening_test" : "revision_recommended"
      { "algorithm_version" => 2, "intended_word_count" => intended_words.length, "machine_heard_word_count" => heard_words.length, "sequence_recall" => recall.round(3), "lines" => line_results, "problem_line_count" => problem_lines, "machine_route" => route }
    end

    def project_current_alignment(evidence)
      alignment = align_lyrics(evidence.fetch("intended_lyrics"), evidence.fetch("machine_heard_lyrics"))
      evidence["alignment"] = alignment
      evidence["machine_route"] = alignment.fetch("machine_route")
      evidence["next_gate"] = alignment.fetch("machine_route") == "human_listening_test" ? "human_listening_test" : "operator_triggered_revision_attempt"
      evidence
    end

    def words(value) = value.to_s.downcase.scan(/[a-z0-9]+(?:'[a-z0-9]+)?/)

    def lcs_word_matches(left, right)
      cells = (left.length + 1) * (right.length + 1)
      raise MusicProjectStore::IntegrityError, "lyric alignment exceeds bounded comparison size" if cells > MAX_ALIGNMENT_CELLS
      width = right.length + 1
      directions = "\0".b * cells
      previous = Array.new(width, 0)
      current = Array.new(width, 0)
      left.each_with_index do |word, left_index|
        current[0] = 0
        right.each_with_index do |other, right_index|
          cell = (left_index + 1) * width + right_index + 1
          if word == other
            current[right_index + 1] = previous[right_index] + 1
            directions.setbyte(cell, 1)
          elsif previous[right_index + 1] >= current[right_index]
            current[right_index + 1] = previous[right_index + 1]
            directions.setbyte(cell, 2)
          else
            current[right_index + 1] = current[right_index]
            directions.setbyte(cell, 3)
          end
        end
        previous, current = current, previous
      end
      matches = Array.new(left.length, false)
      left_index = left.length; right_index = right.length
      while left_index.positive? && right_index.positive?
        case directions.getbyte(left_index * width + right_index)
        when 1 then matches[left_index - 1] = true; left_index -= 1; right_index -= 1
        when 2 then left_index -= 1
        else right_index -= 1
        end
      end
      matches
    end

    def publish_analysis(candidate_dir, staging)
      target = File.join(candidate_dir, "analysis")
      if File.exist?(target)
        history = File.join(candidate_dir, "analysis-history")
        Dir.mkdir(history, 0o700) unless File.exist?(history)
        digest = Digest::SHA256.file(File.join(target, "analysis.json")).hexdigest[0, 16]
        File.rename(target, File.join(history, digest)) unless File.exist?(File.join(history, digest))
        FileUtils.rm_rf(target) if File.exist?(target)
      end
      File.rename(staging, target)
    end

    def failure_outcome(result, staging)
      state = result.status == "canceled" ? "canceled" : "failed"
      File.write(File.join(staging, "failure.log"), (result.stdout.to_s + result.stderr.to_s).byteslice(0, MAX_LOG_BYTES), mode: "wx", perm: 0o600)
      outcome(state, false, "foreground transcription #{state}; no process remains", data: { "exit_status" => result.exit_status })
    end

    def write_json(path, value)
      body = JSON.pretty_generate(value) + "\n"
      raise MusicProjectStore::IntegrityError, "candidate analysis exceeds size limit" if body.bytesize > MAX_JSON_BYTES
      File.write(path, body, mode: "wx", perm: 0o600)
    end

    def load_manifest
      stat = File.lstat(@manifest_path)
      raise MusicProjectStore::IntegrityError, "transcription manifest must be a regular file" unless stat.file? && !stat.symlink?
      JSON.parse(File.read(@manifest_path))
    rescue Errno::ENOENT, JSON::ParserError => error
      raise MusicProjectStore::IntegrityError, "invalid transcription manifest: #{error.class}"
    end

    def secure_compare(left, right)
      return false unless left.to_s.bytesize == right.to_s.bytesize
      left.to_s.bytes.zip(right.to_s.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    end

    def outcome(state, ok, reason, data: {}, mutation: "none") = { "ok" => ok, "lifecycle_state" => state, "reason" => reason, "data" => data, "mutation" => mutation }
  end
end
