# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "uri"
require_relative "bounded_command_runner"
require_relative "music_generation_service"
require_relative "music_reference_library_store"

module SoulCore
  class MusicReferenceAnalysisService
    CONFIRMATION = "ANALYZE_MUSIC_REFERENCE"
    MAX_DURATION_SECONDS = 900
    MAX_DOWNLOAD_BYTES = 250 * 1024 * 1024
    MAX_LOG_BYTES = 1024 * 1024
    MAX_JSON_BYTES = 4 * 1024 * 1024
    METADATA_TIMEOUT_SECONDS = 45
    DOWNLOAD_TIMEOUT_SECONDS = 300
    TRANSCODE_TIMEOUT_SECONDS = 180
    ANALYSIS_TIMEOUT_SECONDS = 300
    RIGHTS = MusicReferenceLibraryStore::RIGHTS

    def initialize(root: Dir.pwd, store: nil, process_runner: MusicGenerationService::ForegroundProcessRunner.new, runner: BoundedCommandRunner.new, clock: -> { Time.now.utc }, tooling_root: nil)
      @root = File.expand_path(root)
      @store = store || MusicReferenceLibraryStore.new(root: @root)
      @process_runner = process_runner
      @runner = runner
      @clock = clock
      @tooling_root = File.expand_path(tooling_root || File.join(@root, "Soul", "music", "tooling", "reference-analysis"))
      @system_yt_dlp = @runner.which("yt-dlp")
      raise MusicReferenceLibraryStore::ValidationError, "music reference tooling root must remain inside the repository" unless within?(@tooling_root, @root)
    end

    def status
      blockers = environment_blockers
      outcome("complete", true, "music reference tooling inspected", data: {
        "available" => blockers.empty?, "blockers" => blockers,
        "limits" => limits, "resident_process" => false, "automatic_download" => false
      })
    end

    def preview(url:, rights_assertion:)
      canonical = canonical_youtube_url(url)
      validate_rights!(rights_assertion)
      blockers = environment_blockers
      return outcome("blocked_for_human_review", false, blockers.join("; "), data: { "blockers" => blockers, "limits" => limits }) unless blockers.empty?
      metadata = fetch_metadata(canonical)
      scope = analysis_scope(metadata, rights_assertion)
      outcome("blocked_for_human_review", true, "exact foreground reference analysis confirmation required", data: {
        "confirmation_phrase" => CONFIRMATION,
        "expected_digest" => digest(scope),
        "preview_scope" => scope,
        "metadata" => metadata
      })
    rescue MusicReferenceLibraryStore::ValidationError, ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue MetadataFailure => error
      outcome("failed", false, error.message)
    rescue MusicReferenceLibraryStore::IntegrityError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def execute(url:, rights_assertion:, confirmation:, expected_digest:, progress: nil)
      canonical = canonical_youtube_url(url)
      validate_rights!(rights_assertion)
      return outcome("awaiting_input", false, "confirmation and expected_digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      return outcome("blocked_for_human_review", false, "exact reference analysis confirmation did not match") unless confirmation == CONFIRMATION
      blockers = environment_blockers
      return outcome("blocked_for_human_review", false, blockers.join("; "), data: { "blockers" => blockers }) unless blockers.empty?

      progress&.call("stage" => "metadata", "message" => "Revalidating the exact single-video source")
      metadata = fetch_metadata(canonical)
      scope = analysis_scope(metadata, rights_assertion)
      return outcome("blocked_for_human_review", false, "reference metadata changed; preview again") unless secure_compare(expected_digest, digest(scope))
      duplicate = @store.list(limit: 500).fetch("tracks").find { |track| track.dig("provenance", "source_id") == metadata.fetch("source_id") }
      return outcome("blocked_for_human_review", false, "this YouTube source already has a local reference profile", data: { "reference" => duplicate }) if duplicate

      Dir.mktmpdir("soul-music-reference-") do |temporary|
        File.chmod(0o700, temporary)
        progress&.call("stage" => "download", "message" => "Retrieving one bounded transient audio source")
        download_source(canonical, temporary, progress)
        source = single_source_file(temporary)
        wav = File.join(temporary, "analysis.wav")
        progress&.call("stage" => "transcode", "message" => "Creating a transient mono analysis copy")
        transcode(source, wav, temporary, progress)
        progress&.call("stage" => "evidence", "message" => "Extracting tempo, tonal, dynamics, and energy evidence")
        extracted = extract_evidence(wav, temporary, progress)
        record = @store.write_track(track_record(metadata, rights_assertion, extracted))
        progress&.call("stage" => "cleanup", "message" => "Removing transient source media and analysis audio")
        return outcome("blocked_for_human_review", true, "reference evidence recorded; synthesis requires Operator review", data: { "reference" => record }, mutation: "music_reference_evidence_recorded")
      end
    rescue MusicReferenceLibraryStore::ValidationError, ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue ProcessCanceled => error
      outcome("canceled", false, error.message)
    rescue MetadataFailure, ProcessFailure => error
      outcome("failed", false, error.message)
    rescue MusicReferenceLibraryStore::IntegrityError, JSON::ParserError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    class MetadataFailure < StandardError; end
    class ProcessFailure < StandardError; end
    class ProcessCanceled < StandardError; end

    private

    def canonical_youtube_url(value)
      uri = URI.parse(value.to_s.strip)
      raise MusicReferenceLibraryStore::ValidationError, "music reference URL must use HTTPS" unless uri.scheme == "https"
      raise MusicReferenceLibraryStore::ValidationError, "music reference URL must not contain credentials, ports, or fragments" if uri.userinfo || uri.port != 443 || uri.fragment
      host = uri.host.to_s.downcase
      id = if host == "youtu.be"
        raise MusicReferenceLibraryStore::ValidationError, "short YouTube URL must contain only one video ID" unless uri.query.to_s.empty? && uri.path.match?(%r{\A/[A-Za-z0-9_-]{6,20}\z})
        uri.path.delete_prefix("/")
      elsif %w[youtube.com www.youtube.com music.youtube.com].include?(host)
        pairs = URI.decode_www_form(uri.query.to_s)
        raise MusicReferenceLibraryStore::ValidationError, "YouTube URL must identify exactly one video without playlist parameters" unless uri.path == "/watch" && pairs.length == 1 && pairs.first.first == "v" && pairs.first.last.match?(/\A[A-Za-z0-9_-]{6,20}\z/)
        pairs.first.last
      else
        raise MusicReferenceLibraryStore::ValidationError, "A5.2 accepts YouTube song URLs only"
      end
      "https://www.youtube.com/watch?v=#{id}"
    rescue URI::InvalidURIError
      raise MusicReferenceLibraryStore::ValidationError, "music reference URL is invalid"
    end

    def validate_rights!(value)
      raise MusicReferenceLibraryStore::ValidationError, "music reference rights assertion is invalid" unless RIGHTS.include?(value.to_s)
    end

    def fetch_metadata(canonical)
      command = yt_dlp_base + ["--skip-download", "--dump-single-json", "--", canonical]
      result = run_process(command, chdir: @root, timeout: METADATA_TIMEOUT_SECONDS, progress: nil)
      raise MetadataFailure, safe_failure("YouTube metadata lookup failed", result) unless result.success?
      raise MetadataFailure, "YouTube metadata response exceeds size limit" if result.stdout.bytesize > MAX_JSON_BYTES
      raw = JSON.parse(result.stdout)
      raise MusicReferenceLibraryStore::ValidationError, "playlists and multi-entry sources are not accepted" if raw["_type"] == "playlist" || raw["entries"].is_a?(Array)
      duration = Integer(raw.fetch("duration"))
      raise MusicReferenceLibraryStore::ValidationError, "live or scheduled sources are not accepted" if raw["is_live"] || %w[is_live is_upcoming post_live].include?(raw["live_status"])
      raise MusicReferenceLibraryStore::ValidationError, "source duration must be 1..#{MAX_DURATION_SECONDS} seconds" unless (1..MAX_DURATION_SECONDS).cover?(duration)
      source_id = raw.fetch("id").to_s
      expected_id = URI.decode_www_form(URI(canonical).query).to_h.fetch("v")
      raise MetadataFailure, "YouTube returned a different source identity" unless source_id == expected_id
      title = bounded_text(raw.fetch("title"), "source title", 300)
      artists = Array(raw["artists"]).filter_map { |name| clean_optional_text(name, 200) }
      artists << clean_optional_text(raw["artist"], 200) if artists.empty?
      artists << clean_optional_text(raw["uploader"], 200) if artists.compact.empty?
      artists = artists.compact.uniq.first(20)
      raise MusicReferenceLibraryStore::ValidationError, "source artist metadata is missing" if artists.empty?
      {
        "canonical_url" => canonical, "source_id" => source_id, "title" => title,
        "artists" => artists, "album" => clean_optional_text(raw["album"], 300),
        "duration_seconds" => duration, "yt_dlp_version" => tool_version(yt_dlp_path)
      }
    rescue JSON::ParserError, KeyError, ArgumentError, TypeError => error
      raise MetadataFailure, "invalid YouTube metadata: #{error.message}"
    end

    def analysis_scope(metadata, rights_assertion)
      {
        "operation" => "music_reference_analysis", "source" => metadata,
        "rights_assertion" => rights_assertion, "limits" => limits,
        "retention" => { "source_audio" => false, "raw_transcription" => false, "derived_evidence" => true },
        "tools" => { "yt_dlp" => metadata.fetch("yt_dlp_version"), "ffmpeg" => tool_version(ffmpeg_path), "essentia" => essentia_version }
      }
    end

    def download_source(canonical, temporary, progress)
      command = yt_dlp_base + ["--max-filesize", MAX_DOWNLOAD_BYTES.to_s, "--format", "bestaudio[filesize<=250M]/bestaudio[filesize_approx<=250M]", "--output", File.join(temporary, "source.%(ext)s"), "--", canonical]
      result = run_process(command, chdir: temporary, timeout: DOWNLOAD_TIMEOUT_SECONDS, progress: progress, file_limit: MAX_DOWNLOAD_BYTES)
      handle_process!(result, "source download")
    end

    def transcode(source, wav, temporary, progress)
      command = [ffmpeg_path, "-nostdin", "-hide_banner", "-loglevel", "error", "-i", source, "-vn", "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le", wav]
      result = run_process(command, chdir: temporary, timeout: TRANSCODE_TIMEOUT_SECONDS, progress: progress, file_limit: 200 * 1024 * 1024)
      handle_process!(result, "analysis transcode")
      raise ProcessFailure, "analysis WAV is missing or too large" unless File.file?(wav) && !File.symlink?(wav) && File.size(wav).between?(44, 200 * 1024 * 1024)
    end

    def extract_evidence(wav, temporary, progress)
      result = run_process([python_path, analyzer_path, wav], chdir: temporary, timeout: ANALYSIS_TIMEOUT_SECONDS, progress: progress)
      handle_process!(result, "Essentia analysis")
      raise ProcessFailure, "Essentia output exceeds size limit" if result.stdout.bytesize > MAX_JSON_BYTES
      value = JSON.parse(result.stdout)
      expected = %w[schema_version essentia_version bpm bpm_alternatives rhythm_confidence beat_count median_beat_interval key key_strength dynamic_complexity loudness danceability dfa energy_curve]
      raise ProcessFailure, "Essentia output fields are invalid" unless value.is_a?(Hash) && value.keys.sort == expected.sort && value["schema_version"] == "soul.music.reference.extractor.v1"
      value
    end

    def track_record(metadata, rights_assertion, extracted)
      production = [
        "dynamic complexity #{extracted['dynamic_complexity']}", "loudness #{extracted['loudness']}",
        "danceability #{extracted['danceability']}", "rhythm confidence #{extracted['rhythm_confidence']}"
      ].reject { |item| item.end_with?(" ") }
      {
        "status" => "candidate",
        "provenance" => {
          "canonical_url" => metadata.fetch("canonical_url"), "platform" => "youtube", "source_id" => metadata.fetch("source_id"),
          "title" => metadata.fetch("title"), "artists" => metadata.fetch("artists"), "album" => metadata["album"],
          "duration_seconds" => metadata.fetch("duration_seconds"), "rights_assertion" => rights_assertion,
          "captured_at" => @clock.call.iso8601, "musicbrainz" => {},
          "tools" => { "yt_dlp" => metadata.fetch("yt_dlp_version"), "ffmpeg" => tool_version(ffmpeg_path), "essentia" => extracted.fetch("essentia_version") }
        },
        "evidence" => {
          "status" => "extracted", "bpm" => extracted["bpm"], "bpm_alternatives" => extracted.fetch("bpm_alternatives"),
          "key" => extracted["key"], "key_alternatives" => [], "meter" => nil, "sections" => [], "instrumentation" => [],
          "production_traits" => production, "energy_curve" => extracted.fetch("energy_curve"), "vocal_traits" => [], "lyrical_traits" => [],
          "confidence_notes" => ["Deterministic audio evidence only; instrumentation, sections, vocals, and lyrical style await Soul synthesis."],
          "extractor_receipt" => extracted.slice("schema_version", "essentia_version", "rhythm_confidence", "beat_count", "median_beat_interval", "key_strength", "dynamic_complexity", "loudness", "danceability", "dfa")
        }
      }
    end

    def single_source_file(temporary)
      candidates = Dir.children(temporary).map { |name| File.join(temporary, name) }.select { |path| File.file?(path) && !File.symlink?(path) && File.basename(path).start_with?("source.") && !path.end_with?(".part") }
      raise ProcessFailure, "source download did not produce exactly one regular audio file" unless candidates.length == 1
      path = candidates.first
      raise ProcessFailure, "source download exceeds #{MAX_DOWNLOAD_BYTES} bytes" unless File.size(path).between?(1, MAX_DOWNLOAD_BYTES)
      path
    end

    def run_process(command, chdir:, timeout:, progress:, file_limit: nil)
      @process_runner.run(command, env: { "HOME" => chdir, "PATH" => ENV.fetch("PATH", "") }, chdir: chdir,
        timeout_seconds: timeout, max_output_bytes: MAX_LOG_BYTES, on_spawn: ->(_pid, _pgid) {}, canceled: -> { false }, progress: progress,
        rlimit_fsize_bytes: file_limit)
    end

    def handle_process!(result, label)
      raise ProcessCanceled, "#{label} canceled or timed out; transient files removed" if result.status == "canceled"
      raise ProcessFailure, safe_failure("#{label} failed", result) unless result.success?
    end

    def safe_failure(label, result)
      detail = result.stderr.to_s.lines.last(3).join(" ").strip.gsub(/\s+/, " ").byteslice(0, 500)
      detail.empty? ? label : "#{label}: #{detail}"
    end

    def environment_blockers
      blockers = []
      blockers << "yt-dlp is unavailable; install it with the operating system package manager or run the reviewed tooling setup" unless File.executable?(yt_dlp_path)
      blockers << "Essentia tooling is not installed; run make music-reference-tooling-plan" unless File.executable?(python_path)
      blockers << "ffmpeg is unavailable" unless File.executable?(ffmpeg_path)
      blockers << "reference analyzer is unavailable" unless File.file?(analyzer_path) && !File.symlink?(analyzer_path)
      blockers << "Essentia is unavailable in the reference tooling environment" if blockers.empty? && essentia_version.nil?
      blockers
    end

    def yt_dlp_base
      [yt_dlp_path, "--ignore-config", "--no-plugin-dirs", "--no-remote-components", "--no-cache-dir", "--no-playlist", "--abort-on-error", "--no-wait-for-video", "--socket-timeout", "10", "--retries", "1", "--fragment-retries", "1", "--extractor-retries", "1", "--file-access-retries", "1", "--concurrent-fragments", "1", "--no-warnings"]
    end

    def limits
      { "urls" => 1, "provider" => "youtube", "duration_seconds" => MAX_DURATION_SECONDS, "download_bytes" => MAX_DOWNLOAD_BYTES, "retries" => 1, "resident_after_completion" => false }
    end

    def yt_dlp_path
      return @system_yt_dlp if @system_yt_dlp && File.executable?(@system_yt_dlp)
      File.join(@tooling_root, ".venv", "bin", "yt-dlp")
    end
    def python_path = File.join(@tooling_root, ".venv", "bin", "python")
    def analyzer_path = File.join(@root, "scripts", "soul-music-reference-analyze")
    def ffmpeg_path = @runner.which("ffmpeg").to_s

    def essentia_version
      return nil unless File.executable?(python_path)
      result = @runner.run([python_path, "-c", "import essentia; print(essentia.__version__)"], timeout_seconds: 10, max_output_bytes: 1_000)
      result.success? ? result.stdout.to_s.strip : nil
    end

    def tool_version(path)
      flag = File.basename(path) == "ffmpeg" ? "-version" : "--version"
      result = @runner.run([path, flag], timeout_seconds: 10, max_output_bytes: 4_000)
      raise MusicReferenceLibraryStore::IntegrityError, "could not identify #{File.basename(path)}" unless result.success?
      result.stdout.to_s.lines.first.to_s.strip.byteslice(0, 200)
    end

    def bounded_text(value, label, maximum)
      text = value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�").strip
      raise MusicReferenceLibraryStore::ValidationError, "#{label} is missing" if text.empty?
      raise MusicReferenceLibraryStore::ValidationError, "#{label} exceeds #{maximum} characters" if text.length > maximum
      text
    end

    def clean_optional_text(value, maximum)
      return nil if value.nil?
      text = value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�").strip
      return nil if text.empty?
      text[0, maximum]
    end

    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))
    def secure_compare(left, right) = left.to_s.bytesize == right.bytesize && left.to_s.bytes.zip(right.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?

    def within?(path, parent)
      expanded = File.expand_path(path); base = File.expand_path(parent)
      expanded == base || expanded.start_with?(base + File::SEPARATOR)
    end

    def outcome(lifecycle, ok, message, data: {}, mutation: "none")
      { "ok" => ok, "lifecycle_state" => lifecycle, "message" => message, "data" => data, "mutation" => mutation }
    end
  end
end
