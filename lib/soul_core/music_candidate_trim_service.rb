# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "bounded_command_runner"
require_relative "music_project_store"

module SoulCore
  class MusicCandidateTrimService
    CONFIRMATION = "APPLY_MUSIC_TRIM"
    MINIMUM_DURATION = 1.0
    MAXIMUM_SOURCE_DURATION = 600.0
    COMMAND_TIMEOUT = 120

    def initialize(root: Dir.pwd, export_root: File.join(Dir.home, "Music", "soul-music"), export_parent: File.join(Dir.home, "Music"), project_store: nil, runner: BoundedCommandRunner.new, ffmpeg_path: nil, ffprobe_path: nil, clock: -> { Time.now.utc })
      @root = File.expand_path(root)
      @export_root = File.expand_path(export_root)
      @export_parent = File.expand_path(export_parent)
      @store = project_store || MusicProjectStore.new(root: @root)
      @runner = runner
      @ffmpeg = ffmpeg_path || @runner.which("ffmpeg")
      @ffprobe = ffprobe_path || @runner.which("ffprobe")
      @clock = clock
      raise MusicProjectStore::ValidationError, "music export root must remain inside the configured Music directory" unless within?(@export_root, @export_parent)
    end

    def preview(project_id:, candidate_id:, start_seconds:, end_seconds:)
      scope = trim_scope(project_id, candidate_id, start_seconds, end_seconds)
      existing = existing_receipt(scope)
      return outcome("complete", true, "this exact trim already exists", data: { "trim" => existing, "idempotent_replay" => true }) if existing
      return outcome("blocked_for_human_review", false, "trim destination already exists; Soul will not overwrite it") if File.exist?(scope.fetch("destination")) || File.symlink?(scope.fetch("destination"))
      outcome("blocked_for_human_review", true, "exact source trim confirmation required", data: {
        "confirmation_phrase" => CONFIRMATION,
        "expected_digest" => digest(scope),
        "preview_scope" => scope
      })
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def execute(project_id:, candidate_id:, start_seconds:, end_seconds:, confirmation:, expected_digest:)
      return outcome("awaiting_input", false, "confirmation and expected_digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      scope = trim_scope(project_id, candidate_id, start_seconds, end_seconds)
      return outcome("blocked_for_human_review", false, "exact source trim confirmation did not match") unless confirmation == CONFIRMATION
      return outcome("blocked_for_human_review", false, "trim source or boundaries changed; preview again") unless secure_compare(expected_digest, digest(scope))
      existing = existing_receipt(scope)
      return outcome("complete", true, "this exact trim already exists", data: { "trim" => existing, "idempotent_replay" => true }) if existing

      destination = scope.fetch("destination")
      raise MusicProjectStore::IntegrityError, "trim destination already exists" if File.exist?(destination) || File.symlink?(destination)
      edits_root = File.dirname(destination)
      prepare_edits_root!(edits_root)
      staging = File.join(edits_root, ".#{scope.fetch('trim_id')}.partial-#{SecureRandom.hex(6)}")
      Dir.mkdir(staging, 0o700)
      source = @store.candidate_artifact_path(project_id, candidate_id, "flac")
      run_ffmpeg!(source, File.join(staging, "master.flac"), scope, codec: "flac")
      run_ffmpeg!(File.join(staging, "master.flac"), File.join(staging, "listening.mp3"), nil, codec: "mp3")
      receipt = scope.merge(
        "schema_version" => "soul.music.trim.v1",
        "created_at" => @clock.call.iso8601,
        "output_digests" => %w[master.flac listening.mp3].to_h { |name| [name, Digest::SHA256.file(File.join(staging, name)).hexdigest] }
      )
      write_json(File.join(staging, "edit.json"), receipt)
      File.rename(staging, destination)
      receipt_path = receipt_path(project_id, candidate_id, scope.fetch("trim_id"))
      write_json(receipt_path, receipt)
      outcome("complete", true, "trimmed listening copy and lossless master created", data: { "trim" => receipt }, mutation: "music_trim_created")
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError, SystemCallError => error
      FileUtils.rm_rf(destination) if defined?(destination) && destination && File.directory?(destination) && !File.symlink?(destination) && (!defined?(receipt_path) || !receipt_path || !File.exist?(receipt_path))
      outcome("blocked_for_human_review", false, error.message)
    ensure
      FileUtils.rm_rf(staging) if defined?(staging) && staging && File.directory?(staging) && !File.symlink?(staging)
    end

    private

    def trim_scope(project_id, candidate_id, start_seconds, end_seconds)
      raise MusicProjectStore::ValidationError, "ffmpeg and ffprobe are required for Lite Edit" unless @ffmpeg && @ffprobe
      project = @store.read(project_id)
      review = @store.read_review(project_id, candidate_id)
      raise MusicProjectStore::ValidationError, "Lite Edit requires a recorded keep review" unless review && review["disposition"] == "keep"
      source = @store.candidate_artifact_path(project_id, candidate_id, "flac")
      source_digest = Digest::SHA256.file(source).hexdigest
      export = verified_export(project, candidate_id)
      duration = probe_duration(source)
      start_at = decimal_seconds(start_seconds, "trim start")
      end_at = decimal_seconds(end_seconds, "trim end")
      raise MusicProjectStore::ValidationError, "trim start must be at or after 0 seconds" if start_at.negative?
      raise MusicProjectStore::ValidationError, "trim end exceeds the source duration" if end_at > duration + 0.01
      end_at = duration if (end_at - duration).abs <= 0.01
      raise MusicProjectStore::ValidationError, "trim end must follow trim start by at least #{MINIMUM_DURATION.to_i} second" if end_at - start_at < MINIMUM_DURATION
      raise MusicProjectStore::ValidationError, "change the start or end boundary before applying a trim" if start_at < 0.01 && (duration - end_at).abs < 0.01
      base = {
        "operation" => "trim_finished_music_candidate",
        "project_id" => project.fetch("project_id"), "candidate_id" => candidate_id,
        "source_artifact" => "immutable candidate master.flac", "source_sha256" => source_digest,
        "source_duration_seconds" => rounded(duration), "start_seconds" => rounded(start_at),
        "end_seconds" => rounded(end_at), "result_duration_seconds" => rounded(end_at - start_at),
        "source_export_destination" => export.fetch("destination"), "overwrite" => false,
        "internal_edits" => false, "edit_of_edit" => false
      }
      trim_id = "trim_#{digest(base)[0, 16]}"
      base.merge("trim_id" => trim_id, "destination" => File.join(export.fetch("destination"), "edits", trim_id))
    end

    def verified_export(project, candidate_id)
      path = File.join(@store.project_path(project.fetch("project_id")), "exports", "#{candidate_id}.json")
      raise MusicProjectStore::ValidationError, "export the accepted original before creating an edited copy" unless File.file?(path) && !File.symlink?(path)
      receipt = JSON.parse(File.binread(path, MusicProjectStore::MAX_PROJECT_BYTES))
      destination = File.expand_path(receipt.fetch("destination"))
      raise MusicProjectStore::IntegrityError, "finished export receipt does not match this candidate" unless receipt["candidate_id"] == candidate_id
      raise MusicProjectStore::IntegrityError, "finished export destination is invalid" unless within?(destination, @export_root) && File.directory?(destination) && !File.symlink?(destination)
      receipt.merge("destination" => destination)
    rescue JSON::ParserError => error
      raise MusicProjectStore::IntegrityError, "invalid finished export receipt: #{error.class}"
    end

    def probe_duration(path)
      result = @runner.run(@ffprobe, "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", path, timeout_seconds: 15, max_output_bytes: 4096)
      raise MusicProjectStore::IntegrityError, "could not inspect source audio duration" unless result.success?
      value = Float(result.stdout.strip)
      raise MusicProjectStore::IntegrityError, "source audio duration is invalid" unless value.between?(MINIMUM_DURATION, MAXIMUM_SOURCE_DURATION)
      value
    rescue ArgumentError
      raise MusicProjectStore::IntegrityError, "source audio duration is invalid"
    end

    def run_ffmpeg!(source, output, scope, codec:)
      command = [@ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-i", source]
      if scope
        command += ["-map", "0:a:0", "-af", "atrim=start=#{scope.fetch('start_seconds')}:end=#{scope.fetch('end_seconds')},asetpts=PTS-STARTPTS"]
      end
      command += codec == "flac" ? ["-c:a", "flac", "-compression_level", "8", output] : ["-c:a", "libmp3lame", "-q:a", "2", output]
      result = @runner.run(command, timeout_seconds: COMMAND_TIMEOUT, max_output_bytes: 64 * 1024)
      raise MusicProjectStore::IntegrityError, "audio trim failed safely: #{result.status}" unless result.success? && File.file?(output) && File.size(output).positive?
      File.chmod(0o600, output)
    end

    def prepare_edits_root!(path)
      parent = File.dirname(path)
      raise MusicProjectStore::IntegrityError, "trim export escaped the finished song" unless within?(path, @export_root)
      [parent, path].each do |directory|
        if File.exist?(directory) || File.symlink?(directory)
          stat = File.lstat(directory)
          raise MusicProjectStore::IntegrityError, "trim export path is invalid" unless stat.directory? && !stat.symlink?
        else
          Dir.mkdir(directory, 0o700)
        end
      end
    end

    def existing_receipt(scope)
      path = receipt_path(scope.fetch("project_id"), scope.fetch("candidate_id"), scope.fetch("trim_id"))
      return nil unless File.exist?(path)
      raise MusicProjectStore::IntegrityError, "trim receipt is invalid" unless File.file?(path) && !File.symlink?(path)
      receipt = JSON.parse(File.binread(path, MusicProjectStore::MAX_PROJECT_BYTES))
      raise MusicProjectStore::IntegrityError, "trim receipt scope changed" unless receipt.slice(*scope.keys) == scope && File.directory?(scope.fetch("destination"))
      receipt
    rescue JSON::ParserError => error
      raise MusicProjectStore::IntegrityError, "invalid trim receipt: #{error.class}"
    end

    def receipt_path(project_id, candidate_id, trim_id)
      File.join(@store.project_path(project_id), "exports", "#{candidate_id}.#{trim_id}.json")
    end

    def decimal_seconds(value, label)
      number = Float(value)
      raise MusicProjectStore::ValidationError, "#{label} must have at most millisecond precision" unless (number * 1000).round.fdiv(1000) == number
      number
    rescue ArgumentError, TypeError
      raise MusicProjectStore::ValidationError, "#{label} must be a number"
    end

    def rounded(value) = value.round(3)
    def write_json(path, value)
      body = JSON.pretty_generate(value) + "\n"
      raise MusicProjectStore::IntegrityError, "trim receipt exceeds size limit" if body.bytesize > MusicProjectStore::MAX_PROJECT_BYTES
      File.write(path, body, mode: "wx", perm: 0o600)
    end
    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))
    def within?(path, parent) = File.expand_path(path) == File.expand_path(parent) || File.expand_path(path).start_with?(File.expand_path(parent) + File::SEPARATOR)
    def secure_compare(left, right) = left.to_s.bytesize == right.to_s.bytesize && left.to_s.bytes.zip(right.to_s.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    def outcome(state, ok, reason, data: {}, mutation: "none") = { "ok" => ok, "lifecycle_state" => state, "reason" => reason, "data" => data, "mutation" => mutation }
  end
end
