# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "bounded_command_runner"
require_relative "long_form_mix_service"
require_relative "music_project_store"

module SoulCore
  class LongFormMixRenderService
    SCHEMA_VERSION = "soul.music.long_form_mix_render.v1"
    PREVIEW_SCHEMA = "soul.music.long_form_mix_render_scope.v1"
    CONFIRMATION = "RENDER_MIX_LISTENING_CANDIDATE"
    MAX_RENDER_SECONDS = 3_600
    MAX_SEQUENCE_ITEMS = 100
    MAX_TITLE_CHARS = 240
    MAX_INTENT_CHARS = 3_000
    MAX_JSON_BYTES = 128 * 1024
    MAX_MANIFEST_BYTES = 512 * 1024
    ROUNDED = 3
    OUTPUT_SAMPLE_RATE = 48_000
    OUTPUT_CHANNELS = 2
    OUTPUT_FLAC = "master.flac"
    OUTPUT_MP3 = "listening.mp3"
    CHECKSUM_FILE = "checksums.sha256"
    RECEIPT_FILE = "render.json"
    COMMAND_TIMEOUT = 3_600
    MAX_OUTPUT_BYTES = 64 * 1024
    REQUIRED_EXPORT_FILES = %w[master.flac listening.mp3 song.json song-info.md].freeze

    class ValidationError < StandardError; end
    class IntegrityError < StandardError; end

    def initialize(
      root: Dir.pwd,
      mix_service: nil,
      runner: BoundedCommandRunner.new,
      ffmpeg_path: nil,
      ffprobe_path: nil,
      export_root: File.join(Dir.home, "Music", "soul-music"),
      export_parent: File.join(Dir.home, "Music"),
      renders_root: nil,
      clock: -> { Time.now.utc }
    )
      @root = File.expand_path(root)
      @mix_service = mix_service || LongFormMixService.new(root: @root, clock: clock)
      @store = MusicProjectStore.new(root: @root)
      @runner = runner
      @ffmpeg = ffmpeg_path || @runner.which("ffmpeg")
      @ffprobe = ffprobe_path || @runner.which("ffprobe")
      @export_root = File.expand_path(export_root)
      @export_parent = File.expand_path(export_parent)
      @renders_root = File.expand_path(renders_root || File.join(@root, "Soul", "private", "mix_renders"))
      @clock = clock

      raise IntegrityError, "music export root must remain inside configured music root" unless within?(@export_root, @export_parent)
      raise IntegrityError, "private render root must remain inside repository" unless within?(@renders_root, @root)
      assert_no_symlink_path!(@export_root)
      assert_no_symlink_path!(@renders_root)
      prepare_root!(@renders_root)
    end

    def status(mix_id:)
      mix = resolve_mix(mix_id)
      scope = render_scope(mix)
      render = existing_render(scope)
      return outcome(
        "complete",
        true,
        "listening render does not exist",
        data: {
          "mix_id" => mix.fetch("mix_id"),
          "destination" => scope.fetch("destination"),
          "state" => "missing",
          "exists" => false
        }
      ) unless render

      outcome(
        "complete",
        true,
        "listening render exists",
        data: {
          "mix_id" => mix.fetch("mix_id"),
          "destination" => scope.fetch("destination"),
          "state" => "ready",
          "exists" => true,
          "render" => render
        }
      )
    rescue ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def artifact_path(mix_id:, artifact:)
      mix = resolve_mix(mix_id)
      scope = render_scope(mix)
      path = case artifact.to_s
             when "flac"
               File.join(scope.fetch("destination"), OUTPUT_FLAC)
             when "mp3"
               File.join(scope.fetch("destination"), OUTPUT_MP3)
             else
               raise ValidationError, "mix artifact must be mp3 or flac"
             end
      raise IntegrityError, "mix listening artifact is missing" unless File.file?(path) && !File.symlink?(path)
      path
    rescue ValidationError, IntegrityError
      raise
    end

    def preview(mix_id:)
      scope = render_scope(resolve_mix(mix_id))
      existing = existing_render(scope)
      return outcome("complete", true, "this exact long-form mix listening render already exists", data: { "render" => existing, "idempotent_replay" => true }, mutation: "none") if existing

      destination = scope.fetch("destination")
      return outcome("blocked_for_human_review", false, "listening render destination already exists; Soul will not overwrite it") if File.exist?(destination) || File.symlink?(destination)

      outcome(
        "blocked_for_human_review",
        true,
        "exact listening render confirmation required",
        data: {
          "confirmation_phrase" => CONFIRMATION,
          "expected_digest" => digest(scope),
          "preview_scope" => scope
        }
      )
    rescue ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def execute(mix_id:, confirmation:, expected_digest:)
      return outcome("awaiting_input", false, "confirmation and expected_digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?

      begin
        scope = render_scope(resolve_mix(mix_id))
        return outcome("blocked_for_human_review", false, "exact listening render confirmation did not match") unless confirmation == CONFIRMATION
        return outcome("blocked_for_human_review", false, "listening render scope changed; preview again") unless secure_compare(expected_digest.to_s, digest(scope))

        existing = existing_render(scope)
        return outcome("complete", true, "this exact long-form mix listening render already exists", data: { "render" => existing, "idempotent_replay" => true }, mutation: "none") if existing

        destination = scope.fetch("destination")
        raise IntegrityError, "listening render destination already exists" if File.exist?(destination) || File.symlink?(destination)
        raise IntegrityError, "ffmpeg is required for bounded listening render" unless @ffmpeg
        raise IntegrityError, "ffprobe is required for bounded listening render" unless @ffprobe

        prepare_root!(File.dirname(destination))
        staging = File.join(File.dirname(destination), ".#{File.basename(destination)}.partial-#{SecureRandom.hex(6)}")
        FileUtils.mkdir_p(staging, mode: 0o700)

        begin
          flac_path = File.join(staging, OUTPUT_FLAC)
          mp3_path = File.join(staging, OUTPUT_MP3)

          run_mix_render!(scope, flac_path)
          run_mp3_render!(flac_path, mp3_path)

          receipt = build_receipt(scope, flac_path, mp3_path)
          receipt_path = File.join(staging, RECEIPT_FILE)
          write_json(receipt_path, receipt)

          checksums = {
            OUTPUT_FLAC => Digest::SHA256.file(flac_path).hexdigest,
            OUTPUT_MP3 => Digest::SHA256.file(mp3_path).hexdigest,
            RECEIPT_FILE => Digest::SHA256.file(receipt_path).hexdigest
          }
          write_checksum_manifest(File.join(staging, CHECKSUM_FILE), checksums)
          File.rename(staging, destination)

          outcome(
            "complete",
            true,
            "long-form mix listening render prepared",
            data: { "render" => receipt },
            mutation: "long_form_mix_render_prepared"
          )
        rescue ValidationError => error
          outcome("awaiting_input", false, error.message)
        rescue IntegrityError, KeyError, SystemCallError => error
          outcome("blocked_for_human_review", false, error.message)
        ensure
          FileUtils.rm_rf(staging) if staging && File.directory?(staging) && !File.symlink?(staging)
        end
      rescue ValidationError => error
        outcome("awaiting_input", false, error.message)
      rescue IntegrityError, KeyError, SystemCallError => error
        outcome("blocked_for_human_review", false, error.message)
      end
    end

    private

    def resolve_mix(mix_id)
      result = @mix_service.get(mix_id: mix_id)
      state = result.fetch("lifecycle_state")
      raise IntegrityError, result.fetch("reason") if state == "blocked_for_human_review"
      raise ValidationError, result.fetch("reason") unless state == "complete"
      mix = result.fetch("data").fetch("mix")
      validate_mix_record(mix)
      mix
    rescue ValidationError
      raise
    rescue IntegrityError
      raise
    rescue StandardError => error
      raise IntegrityError, "could not load mix plan: #{error.class}"
    end

    def render_scope(mix)
      mix_id = mix.fetch("mix_id").to_s
      raise ValidationError, "mix_id is invalid" unless mix_id.match?(LongFormMixService::MIX_ID)
      raise IntegrityError, "mix total duration is not bounded" if mix.fetch("total_duration_seconds") > MAX_RENDER_SECONDS

      files = [OUTPUT_FLAC, OUTPUT_MP3, CHECKSUM_FILE, RECEIPT_FILE]
      sources = mix.fetch("sequence").each_with_index.map do |entry, index|
        track_from_entry(entry, index, mix.fetch("timeline_seconds").fetch(index))
      end

      {
        "schema_version" => PREVIEW_SCHEMA,
        "operation" => "render_listening_candidate",
        "mix_id" => mix_id,
        "title" => mix.fetch("title"),
        "intent" => mix.fetch("intent"),
        "destination" => destination_for_mix(mix_id, mix.fetch("title")),
        "source_count" => sources.length,
        "sequence" => mix.fetch("sequence"),
        "timeline_seconds" => mix.fetch("timeline_seconds"),
        "total_duration_seconds" => mix.fetch("total_duration_seconds"),
        "source_tracks" => sources,
        "expected_outputs" => files,
        "render_output_sample_rate" => OUTPUT_SAMPLE_RATE,
        "render_output_channels" => OUTPUT_CHANNELS,
        "expected_sample_durations" => { "flac_seconds" => mix.fetch("total_duration_seconds"), "listening_mp3_seconds" => mix.fetch("total_duration_seconds") },
        "command_profile" => {
          "command_template" => "ffmpeg -i ... -filter_complex ... -map [mix_out] ...",
          "trim_filter" => "atrim + asetpts",
          "crossfade_filter" => "acrossfade",
          "concat_filter" => "concat",
          "limiter_filter" => "alimiter",
          "mp3_bitrate" => "320k",
          "render_sample_rate" => OUTPUT_SAMPLE_RATE,
          "render_channels" => OUTPUT_CHANNELS,
          "render_uses_ffmpeg" => true
        },
        "source_file_digests" => sources.to_h { |source| [source.fetch("source_id"), source.fetch("source_digests")] }
      }
    end

    def track_from_entry(entry, index, timeline)
      data = entry.to_h
      raise ValidationError, "sequence entry is incomplete" unless %w[project_id candidate_id source_id source_master_sha256 trim_start_seconds trim_end_seconds crossfade_seconds duration_seconds transition_note].all? { |key| data.key?(key) }
      project_id = data.fetch("project_id").to_s
      candidate_id = data.fetch("candidate_id").to_s
      source_id = data.fetch("source_id").to_s
      raise ValidationError, "project_id is invalid" unless project_id.match?(LongFormMixService::PROJECT_ID)
      raise ValidationError, "candidate_id is invalid" unless candidate_id.match?(LongFormMixService::CANDIDATE_ID)
      raise ValidationError, "source_id is invalid" unless source_id == "#{project_id}/#{candidate_id}"

      trim_start = parse_seconds(data.fetch("trim_start_seconds"), "trim_start_seconds")
      trim_end = parse_seconds(data.fetch("trim_end_seconds"), "trim_end_seconds")
      crossfade = parse_seconds(data.fetch("crossfade_seconds"), "crossfade_seconds")
      raise ValidationError, "trim_end must be greater than trim_start" unless trim_end > trim_start
      source = source_from_receipt(project_id: project_id, candidate_id: candidate_id, source_id: source_id)
      raise IntegrityError, "mix source master digest changed" unless secure_compare(data.fetch("source_master_sha256"), source.fetch("source_master_sha256"))
      source_duration = source.fetch("duration_seconds")
      raise ValidationError, "trim_start is outside source duration" unless trim_start <= source_duration
      raise ValidationError, "trim_end is outside source duration" unless trim_end <= source_duration
      transition = parse_timeline_transition(timeline)
      raise ValidationError, "timeline start changed" unless transition.fetch("start_seconds") == timeline.fetch("start_seconds")

      duration = rounded(trim_end - trim_start)
      raise ValidationError, "source effective duration is not deterministic" unless rounded(rounded(data.fetch("duration_seconds"))) == duration

      if index.zero?
        raise ValidationError, "first crossfade must be exactly 0" unless rounded(crossfade).zero?
      else
        previous_duration = rounded(data.fetch("duration_seconds"))
        raise ValidationError, "crossfade must be finite and nonnegative" unless crossfade.finite? && crossfade >= 0.0
        raise ValidationError, "crossfade must not exceed 10 seconds" if crossfade > 10.0
        raise ValidationError, "crossfade must be less than source effective lengths" unless crossfade < duration && crossfade < previous_duration
      end

      {
        "index" => index,
        "source_id" => source_id,
        "project_id" => project_id,
        "candidate_id" => candidate_id,
        "source_path" => source.fetch("source_path"),
        "source_master_sha256" => source.fetch("source_master_sha256"),
        "source_digests" => source.fetch("source_digests"),
        "trim_start_seconds" => rounded(trim_start),
        "trim_end_seconds" => rounded(trim_end),
        "crossfade_seconds" => rounded(crossfade),
        "duration_seconds" => duration,
        "filename" => format("source_%02d_%s.flac", index, sanitize_filename(source_id)),
        "track_timing" => timeline
      }
    end

    def parse_timeline_transition(entry)
      entry.to_h.slice("start_seconds", "end_seconds", "duration_seconds")
    end

    def source_from_receipt(project_id:, candidate_id:, source_id:)
      project = @store.read(project_id)
      review = @store.read_review(project.fetch("project_id"), candidate_id)
      raise ValidationError, "mix source requires reviewed keep disposition" unless review && review["disposition"] == "keep"
      path = File.join(@store.project_path(project.fetch("project_id")), "exports", "#{candidate_id}.json")
      raise IntegrityError, "source export record is missing for #{source_id}" unless File.file?(path) && !File.symlink?(path)
      receipt = parse_json(path)
      raise IntegrityError, "source export schema is invalid" unless receipt.fetch("schema_version") == "soul.music.finished_export.v1"

      destination = File.expand_path(receipt.fetch("destination"))
      raise IntegrityError, "source export destination is outside configured music tree" unless within?(destination, @export_root)
      raise IntegrityError, "source export destination is missing" unless File.directory?(destination)
      raise IntegrityError, "source export destination is a symlink" if File.symlink?(destination)
      raise IntegrityError, "source export destination is unsafe" if path_has_symlink?(destination)
      source_files = {}
      source_digests = {}
      REQUIRED_EXPORT_FILES.each do |name|
        file = File.join(destination, name)
        raise IntegrityError, "source export file is missing: #{name}" unless File.file?(file) && !File.symlink?(file)
        actual = Digest::SHA256.file(file).hexdigest
        recorded = receipt.fetch("files", {}).to_h.fetch(name, nil)
        raise IntegrityError, "source export file digest is missing: #{name}" if recorded.to_s.empty?
        raise IntegrityError, "source export file digest changed: #{name}" unless secure_compare(recorded, actual)
        source_files[name] = file
        source_digests[name] = actual
      end
      song = parse_json(File.join(destination, "song.json"))
      raise IntegrityError, "source song schema is invalid" unless song.fetch("schema_version") == "soul.music.finished_song.v1"
      duration = parse_seconds(song.fetch("duration_seconds"), "source song duration")
      source_master = source_digests.fetch("master.flac")

      {
        "project_id" => project.fetch("project_id"),
        "candidate_id" => candidate_id,
        "source_id" => source_id,
        "source_path" => source_files.fetch("master.flac"),
        "source_master_sha256" => source_master,
        "source_digests" => source_digests,
        "duration_seconds" => duration
      }
    end

    def run_mix_render!(scope, output_path)
      filter_graph = render_filter_graph(scope.fetch("source_tracks"))
      command = [@ffmpeg, "-y", "-nostdin", "-hide_banner", "-loglevel", "error"]
      scope.fetch("source_tracks").each { |track| command << "-i" << track.fetch("source_path") }
      command += [
        "-filter_complex", filter_graph,
        "-map", "[mix_out]",
        "-ar", OUTPUT_SAMPLE_RATE.to_s,
        "-ac", OUTPUT_CHANNELS.to_s,
        "-c:a", "flac", "-compression_level", "8", output_path
      ]
      result = @runner.run(*command, timeout_seconds: COMMAND_TIMEOUT, max_output_bytes: MAX_OUTPUT_BYTES)
      valid = result.success? && File.file?(output_path) && !File.symlink?(output_path) && File.size(output_path).positive?
      raise IntegrityError, "listening mix render failed safely: #{result.status}" unless valid
      verify_audio_media_profile!(
        output_path,
        duration_seconds: scope.fetch("total_duration_seconds"),
        sample_rate: OUTPUT_SAMPLE_RATE,
        channels: OUTPUT_CHANNELS
      )
      File.chmod(0o600, output_path)
      command
    end

    def run_mp3_render!(input_path, output_path)
      command = [@ffmpeg, "-y", "-nostdin", "-hide_banner", "-loglevel", "error", "-i", input_path,
        "-filter_complex", "alimiter=limit=0.98", "-ar", OUTPUT_SAMPLE_RATE.to_s, "-ac", OUTPUT_CHANNELS.to_s,
        "-c:a", "libmp3lame", "-q:a", "0", "-b:a", "320k", output_path]
      result = @runner.run(*command, timeout_seconds: COMMAND_TIMEOUT, max_output_bytes: MAX_OUTPUT_BYTES)
      valid = result.success? && File.file?(output_path) && !File.symlink?(output_path) && File.size(output_path).positive?
      raise IntegrityError, "listening mp3 render failed safely: #{result.status}" unless valid
      verify_audio_media_profile!(
        output_path,
        sample_rate: OUTPUT_SAMPLE_RATE,
        channels: OUTPUT_CHANNELS
      )
      File.chmod(0o600, output_path)
      command
    end

    def render_filter_graph(tracks)
      trimmed = tracks.map.with_index do |track, index|
        start = format_number(track.fetch("trim_start_seconds"))
        finish = format_number(track.fetch("trim_end_seconds"))
        "[#{index}:a]atrim=start=#{start}:end=#{finish},asetpts=PTS-STARTPTS,aformat=sample_rates=#{OUTPUT_SAMPLE_RATE}:channel_layouts=stereo[s#{index}]"
      end
      return "#{trimmed.join(";")};[s0]alimiter=limit=0.98[mix_out]" if tracks.length == 1

      pieces = trimmed
      current = "s0"
      tracks.each_with_index do |track, index|
        next if index.zero?
        next_label = "m#{index}"
        crossfade = track.fetch("crossfade_seconds")
        if crossfade.zero?
          pieces << "[#{current}][s#{index}]concat=n=2:v=0:a=1[#{next_label}]"
        else
          pieces << "[#{current}][s#{index}]acrossfade=d=#{format_number(crossfade)}:c1=tri:c2=tri[#{next_label}]"
        end
        current = next_label
      end
      "#{pieces.join(";")};[#{current}]alimiter=limit=0.98[mix_out]"
    end

    def existing_render(scope)
      destination = scope.fetch("destination")
      return nil unless File.directory?(destination) && !File.symlink?(destination)

      required = scope.fetch("expected_outputs")
      checksums_path = File.join(destination, CHECKSUM_FILE)
      checksums = parse_checksum_manifest(checksums_path)
      raise IntegrityError, "listening render checksum inventory changed" unless checksums.keys.sort == (required - [CHECKSUM_FILE]).sort

      required.each do |filename|
        path = File.join(destination, filename)
        raise IntegrityError, "listening render artifact is missing: #{filename}" unless File.file?(path) && !File.symlink?(path)
      end

      preview = parse_json(File.join(destination, RECEIPT_FILE))
      raise IntegrityError, "listening render receipt is invalid" unless preview.fetch("schema_version") == SCHEMA_VERSION
      raise IntegrityError, "listening render scope changed" unless secure_compare(preview.fetch("scope_digest"), digest(scope))
      if preview["source_file_digests"] != scope.fetch("source_file_digests")
        raise IntegrityError, "listening render source digests changed"
      end

      if preview["checksums"] && preview["checksums"].is_a?(Hash)
        preview_checksums = preview.fetch("checksums")
        raise IntegrityError, "listening render checksum metadata is incomplete" unless preview_checksums.keys.include?(OUTPUT_FLAC) && preview_checksums.keys.include?(OUTPUT_MP3)
      end

      checksums.each do |name, expected|
        actual = Digest::SHA256.file(File.join(destination, name)).hexdigest
        raise IntegrityError, "listening render checksum mismatch: #{name}" unless secure_compare(actual, expected)
      end

      preview
    end

    def build_receipt(scope, flac_path, mp3_path)
      {
        "schema_version" => SCHEMA_VERSION,
        "mix_id" => scope.fetch("mix_id"),
        "title" => scope.fetch("title"),
        "intent" => scope.fetch("intent"),
        "destination" => destination_for_mix(scope.fetch("mix_id"), scope.fetch("title")),
        "scope_digest" => digest(scope),
        "source_file_digests" => scope.fetch("source_file_digests"),
        "rendered_at" => @clock.call.iso8601,
        "total_duration_seconds" => scope.fetch("total_duration_seconds"),
        "duration_seconds" => scope.fetch("total_duration_seconds"),
        "render_output_sample_rate" => OUTPUT_SAMPLE_RATE,
        "render_output_channels" => OUTPUT_CHANNELS,
        "command_profile" => scope.fetch("command_profile"),
        "files" => [OUTPUT_FLAC, OUTPUT_MP3, RECEIPT_FILE, CHECKSUM_FILE],
        "checksums" => {
          OUTPUT_FLAC => Digest::SHA256.file(flac_path).hexdigest,
          OUTPUT_MP3 => Digest::SHA256.file(mp3_path).hexdigest
        }
      }
    end

    def verify_audio_media_profile!(path, sample_rate:, channels:, duration_seconds: nil)
      command = [@ffprobe, "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=duration,sample_rate,channels", "-of", "json", path]
      result = @runner.run(*command, timeout_seconds: COMMAND_TIMEOUT, max_output_bytes: MAX_OUTPUT_BYTES)
      raise IntegrityError, "listening audio metadata probe failed safely: #{result.status}" unless result.success?
      payload = JSON.parse(result.stdout.to_s)
      stream = payload.fetch("streams").to_a.first
      raise IntegrityError, "listening audio metadata is missing" unless stream

      observed_sample_rate = stream.fetch("sample_rate").to_i
      observed_channels = stream.fetch("channels").to_i
      raise IntegrityError, "listening audio sample rate changed" unless observed_sample_rate == sample_rate
      raise IntegrityError, "listening audio channel count changed" unless observed_channels == channels
      return unless duration_seconds

      observed_duration = stream.fetch("duration").to_f
      tolerance = 0.25
      raise IntegrityError, "listening audio duration changed" unless (observed_duration - duration_seconds).abs <= tolerance
    end

    def parse_json(path)
      raise IntegrityError, "record is invalid or unsafe" unless File.file?(path) && !File.symlink?(path)
      body = File.binread(path, MAX_JSON_BYTES + 1)
      raise IntegrityError, "record is too large" if body.bytesize > MAX_JSON_BYTES
      JSON.parse(body)
    rescue JSON::ParserError => error
      raise IntegrityError, "record JSON is invalid: #{error.class}"
    end

    def path_has_symlink?(path)
      current = "/"
      File.expand_path(path).split(File::SEPARATOR).each do |part|
        next if part.empty?
        current = File.join(current, part)
        return true if File.exist?(current) && File.symlink?(current)
      end
      false
    end

    def write_json(path, payload)
      body = JSON.pretty_generate(payload) + "\n"
      raise IntegrityError, "render receipt exceeds maximum size" if body.bytesize > MAX_JSON_BYTES
      File.write(path, body, mode: "wx", perm: 0o600)
    end

    def parse_checksum_manifest(path)
      raise IntegrityError, "checksum manifest is missing or unsafe" unless File.file?(path) && !File.symlink?(path)
      body = File.binread(path, MAX_MANIFEST_BYTES + 1)
      raise IntegrityError, "checksum manifest is too large" if body.bytesize > MAX_MANIFEST_BYTES
      manifest = {}
      body.each_line do |line|
        next if line.strip.empty?
        value, name = line.strip.split(/\s+/, 2)
        name = name.to_s.sub(/^  /, "")
        raise IntegrityError, "checksum manifest is malformed" unless name && value && value.match?(/\A[a-f0-9]{64}\z/)
        raise IntegrityError, "checksum manifest filename is unsafe" unless name.match?(/\A[a-zA-Z0-9._-]+\z/)
        manifest[name] = value
      end
      manifest
    end

    def write_checksum_manifest(path, checksums)
      lines = checksums.sort.to_h.map { |name, value| "#{value}  #{name}" }
      File.write(path, "#{lines.join("\n")}\n", mode: "wx", perm: 0o600)
    end

    def validate_mix_record(mix)
      raise ValidationError, "mix schema is invalid" unless mix.fetch("schema_version") == LongFormMixService::SCHEMA_VERSION
      raise ValidationError, "mix id is invalid" unless mix.fetch("mix_id").to_s.match?(LongFormMixService::MIX_ID)
      raise ValidationError, "mix title is invalid" if mix.fetch("title").to_s.empty? || mix.fetch("title").to_s.length > MAX_TITLE_CHARS
      raise ValidationError, "mix intent is invalid" if mix.fetch("intent").to_s.empty? || mix.fetch("intent").to_s.length > MAX_INTENT_CHARS

      timeline = mix.fetch("timeline_seconds")
      sequence = mix.fetch("sequence")
      raise ValidationError, "mix timeline is invalid" unless timeline.is_a?(Array) && timeline.length <= MAX_SEQUENCE_ITEMS
      raise ValidationError, "mix sequence is invalid" unless sequence.is_a?(Array) && sequence.length == timeline.length && sequence.length.between?(1, MAX_SEQUENCE_ITEMS)

      sequence.each_with_index do |entry, index|
        data = entry.to_h
        raise ValidationError, "mix source_id mismatch" if data.fetch("source_id") != mix.fetch("timeline_seconds").fetch(index).fetch("source_id")
        trim_start = parse_seconds(data.fetch("trim_start_seconds"), "trim_start_seconds")
        trim_end = parse_seconds(data.fetch("trim_end_seconds"), "trim_end_seconds")
        crossfade = parse_seconds(data.fetch("crossfade_seconds"), "crossfade_seconds")
        raise ValidationError, "trim_end must be greater than trim_start" unless trim_end > trim_start
        expected_duration = rounded(trim_end - trim_start)
        raise ValidationError, "duration is not deterministic" unless rounded(data.fetch("duration_seconds")) == expected_duration
        raise ValidationError, "first crossfade must be exactly 0" if index.zero? && !rounded(crossfade).zero?
      end
    end

    def destination_for_mix(mix_id, title)
      File.join(@renders_root, "#{slugify(title)}-#{mix_id}")
    end

    def parse_seconds(value, label)
      number = Float(value)
      raise ValidationError, "#{label} must be finite" unless number.finite?
      raise ValidationError, "#{label} must be nonnegative" if number.negative?
      number
    rescue ArgumentError, TypeError
      raise ValidationError, "#{label} must be a number"
    end

    def rounded(value)
      value.round(ROUNDED)
    end

    def format_number(value)
      format("%.#{ROUNDED}f", rounded(value))
    end

    def sanitize_filename(value)
      text = value.to_s.gsub(/[^a-zA-Z0-9._-]/, "-").gsub(/-+/, "-").gsub(/\A-+|-+\z/, "")
      fallback = "source"
      return fallback if text.empty?
      text[0, 60]
    end

    def slugify(value)
      slug = value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      slug = slug.gsub(/[-_]+/, "-")
      return "long-form-mix" if slug.empty?
      slug[0, 80]
    end

    def within?(path, parent)
      candidate = File.expand_path(path)
      base = File.expand_path(parent)
      candidate == base || candidate.start_with?("#{base}#{File::SEPARATOR}")
    end

    def prepare_root!(path)
      assert_no_symlink_path!(path)
      FileUtils.mkdir_p(path, mode: 0o700)
      assert_no_symlink_path!(path)
      raise IntegrityError, "storage root must remain a directory" unless File.directory?(path) && !File.symlink?(path)
      File.chmod(0o700, path)
    end

    def assert_no_symlink_path!(path)
      cursor = "/"
      File.expand_path(path).split(File::SEPARATOR).each do |part|
        next if part.empty?
        cursor = File.join(cursor, part)
        next unless File.exist?(cursor)
        raise IntegrityError, "path component is a symlink: #{cursor}" if File.symlink?(cursor)
      end
    end

    def secure_compare(left, right)
      left_s = left.to_s
      right_s = right.to_s
      return false unless left_s.bytesize == right_s.bytesize
      left_s.bytes.zip(right_s.bytes).all? { |pair| pair[0] == pair[1] }
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(value))
    end

    def outcome(state, ok, reason, data: {}, mutation: "none")
      { "ok" => ok, "lifecycle_state" => state, "reason" => reason, "data" => data, "mutation" => mutation }
    end
  end
end
