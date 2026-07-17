# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "music_candidate_analysis_service"
require_relative "music_project_store"

module SoulCore
  class MusicCandidateDispositionService
    REJECT_CONFIRMATION = "DELETE_REJECTED_CANDIDATE"
    EXPORT_CONFIRMATION = "EXPORT_FINISHED_SONG"
    MAX_JSON_BYTES = 8 * 1024 * 1024

    def initialize(root: Dir.pwd, export_root: File.join(Dir.home, "Music", "soul-music"), export_parent: File.join(Dir.home, "Music"), project_store: nil, analysis_service: nil, clock: -> { Time.now.utc })
      @root = File.expand_path(root)
      @export_root = File.expand_path(export_root)
      @export_parent = File.expand_path(export_parent)
      @store = project_store || MusicProjectStore.new(root: @root)
      @analysis = analysis_service || MusicCandidateAnalysisService.new(root: @root, project_store: @store)
      @clock = clock
      raise MusicProjectStore::ValidationError, "music export root must remain inside the configured Music directory" unless within?(@export_root, @export_parent)
    end

    def reject_preview(project_id:, candidate_id:)
      project, candidate, input, review = candidate_state(project_id, candidate_id, disposition: "reject")
      scope = reject_scope(project, candidate, input, review)
      outcome("blocked_for_human_review", true, "exact rejected-candidate deletion confirmation required", data: {
        "confirmation_phrase" => REJECT_CONFIRMATION,
        "expected_digest" => digest(scope),
        "preview_scope" => scope
      })
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def reject_execute(project_id:, candidate_id:, confirmation:, expected_digest:)
      return outcome("awaiting_input", false, "confirmation and expected_digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      project, candidate, input, review = candidate_state(project_id, candidate_id, disposition: "reject")
      scope = reject_scope(project, candidate, input, review)
      return outcome("blocked_for_human_review", false, "exact rejected-candidate deletion confirmation did not match") unless confirmation == REJECT_CONFIRMATION
      return outcome("blocked_for_human_review", false, "rejected candidate state changed; preview again") unless secure_compare(expected_digest, digest(scope))

      project_path = @store.project_path(project_id)
      candidate_dir = candidate_directory(project_id, candidate_id)
      rejected_dir = File.join(project_path, "reviews", "rejected")
      prepare_private_directory(rejected_dir, parent: File.join(project_path, "reviews"))
      tombstone = File.join(rejected_dir, "#{candidate_id}.json")
      raise MusicProjectStore::IntegrityError, "rejection receipt already exists" if File.exist?(tombstone) || File.symlink?(tombstone)
      receipt = {
        "schema_version" => "soul.music.candidate_rejection.v1", "project_id" => project_id,
        "candidate_id" => candidate_id, "deleted_at" => @clock.call.iso8601,
        "candidate_input_digest" => @store.generation_input_digest(input),
        "review_digest" => digest(review), "artifact_digests" => artifact_digests(candidate),
        "descendant_candidate_ids" => descendant_ids(project_id, candidate_id),
        "audio_retained" => false, "analysis_retained" => false, "review" => review
      }
      atomic_json(tombstone, receipt)
      FileUtils.rm_rf(candidate_dir)
      raise MusicProjectStore::IntegrityError, "rejected candidate directory could not be removed" if File.exist?(candidate_dir) || File.symlink?(candidate_dir)
      review_path = File.join(project_path, "reviews", "#{candidate_id}.json")
      FileUtils.rm_f(review_path)
      outcome("complete", true, "rejected candidate audio, inputs, and analysis deleted", data: { "rejection" => receipt }, mutation: "music_candidate_deleted")
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError, SystemCallError => error
      FileUtils.rm_f(tombstone) if defined?(tombstone) && tombstone && defined?(candidate_dir) && candidate_dir && (File.exist?(candidate_dir) || File.symlink?(candidate_dir))
      outcome("blocked_for_human_review", false, error.message)
    end

    def export_preview(project_id:, candidate_id:)
      project, candidate, input, review = candidate_state(project_id, candidate_id, disposition: "keep")
      analysis = export_analysis(project, candidate_id)
      scope = export_scope(project, candidate, input, review, analysis)
      existing = existing_export(scope)
      return outcome("complete", true, "finished song is already exported", data: existing.merge("idempotent_replay" => true), mutation: "none") if existing
      destination = scope.fetch("destination")
      return outcome("blocked_for_human_review", false, "finished song destination already exists; Soul will not overwrite it") if File.exist?(destination) || File.symlink?(destination)
      outcome("blocked_for_human_review", true, "exact finished-song export confirmation required", data: {
        "confirmation_phrase" => EXPORT_CONFIRMATION,
        "expected_digest" => digest(scope),
        "preview_scope" => scope
      })
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError, SystemCallError => error
      if defined?(destination) && destination && File.directory?(destination) && !File.symlink?(destination) && (!defined?(receipt_path) || !File.exist?(receipt_path))
        FileUtils.rm_rf(destination)
      end
      outcome("blocked_for_human_review", false, error.message)
    end

    def export_execute(project_id:, candidate_id:, confirmation:, expected_digest:)
      return outcome("awaiting_input", false, "confirmation and expected_digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      project, candidate, input, review = candidate_state(project_id, candidate_id, disposition: "keep")
      analysis = export_analysis(project, candidate_id)
      scope = export_scope(project, candidate, input, review, analysis)
      return outcome("blocked_for_human_review", false, "exact finished-song export confirmation did not match") unless confirmation == EXPORT_CONFIRMATION
      return outcome("blocked_for_human_review", false, "finished-song export state changed; preview again") unless secure_compare(expected_digest, digest(scope))
      existing = existing_export(scope)
      return outcome("complete", true, "finished song is already exported", data: existing.merge("idempotent_replay" => true), mutation: "none") if existing

      prepare_export_root!
      destination = scope.fetch("destination")
      raise MusicProjectStore::IntegrityError, "finished song destination already exists" if File.exist?(destination) || File.symlink?(destination)
      staging = File.join(@export_root, ".#{File.basename(destination)}.partial-#{SecureRandom.hex(6)}")
      Dir.mkdir(staging, 0o700)
      flac_source = @store.candidate_artifact_path(project_id, candidate_id, "flac")
      mp3_source = @store.candidate_artifact_path(project_id, candidate_id, "mp3")
      copy_verified(flac_source, File.join(staging, "master.flac"), candidate.dig("artifacts", "flac", "sha256"))
      copy_verified(mp3_source, File.join(staging, "listening.mp3"), candidate.dig("artifacts", "mp3", "sha256"))
      metadata = export_metadata(project, candidate, input, analysis)
      atomic_json(File.join(staging, "song.json"), metadata, maximum: MAX_JSON_BYTES)
      write_private(File.join(staging, "song-info.md"), song_info(metadata))
      if project.fetch("vocal_mode") == "vocal"
        transcript = analysis["machine_heard_formatted"] || analysis.fetch("machine_heard_lyrics")
        write_private(File.join(staging, "lyrics.txt"), transcript.to_s.strip + "\n")
      end
      File.rename(staging, destination)
      receipt = {
        "schema_version" => "soul.music.finished_export.v1", "project_id" => project_id,
        "candidate_id" => candidate_id, "destination" => destination,
        "exported_at" => @clock.call.iso8601, "scope_digest" => digest(scope),
        "files" => Dir.children(destination).sort.to_h { |name| [name, Digest::SHA256.file(File.join(destination, name)).hexdigest] }
      }
      receipt_path = File.join(@store.project_path(project_id), "exports", "#{candidate_id}.json")
      atomic_json(receipt_path, receipt)
      outcome("complete", true, "finished song exported", data: { "export" => receipt }, mutation: "finished_song_exported")
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    ensure
      FileUtils.rm_rf(staging) if defined?(staging) && staging && File.directory?(staging) && !File.symlink?(staging)
    end

    private

    def candidate_state(project_id, candidate_id, disposition:)
      project = @store.read(project_id)
      candidate = candidate_record(project_id, candidate_id)
      input = @store.candidate_input(project_id, candidate_id)
      review = @store.read_review(project_id, candidate_id)
      raise MusicProjectStore::ValidationError, "candidate requires a recorded #{disposition} review" unless review && review["disposition"] == disposition
      if disposition == "reject"
        export_receipt = File.join(@store.project_path(project_id), "exports", "#{candidate_id}.json")
        raise MusicProjectStore::ValidationError, "candidate has a finished export; remove that export through a separate reviewed operation before rejection" if File.exist?(export_receipt) || File.symlink?(export_receipt)
      end
      [project, candidate, input, review]
    end

    def candidate_directory(project_id, candidate_id)
      File.dirname(@store.candidate_artifact_path(project_id, candidate_id, "flac"))
    end

    def candidate_record(project_id, candidate_id)
      path = File.join(candidate_directory(project_id, candidate_id), "candidate.json")
      raise MusicProjectStore::IntegrityError, "candidate receipt is invalid" unless File.file?(path) && !File.symlink?(path) && File.size(path).between?(1, MusicProjectStore::MAX_PROJECT_BYTES)
      value = JSON.parse(File.binread(path, MusicProjectStore::MAX_PROJECT_BYTES))
      raise MusicProjectStore::IntegrityError, "candidate receipt identity is invalid" unless value["schema_version"] == "soul.music.generation.v1" && value["project_id"] == project_id && value["candidate_id"] == candidate_id
      value
    rescue JSON::ParserError => error
      raise MusicProjectStore::IntegrityError, "invalid candidate receipt: #{error.class}"
    end

    def reject_scope(project, candidate, input, review)
      {
        "operation" => "delete_rejected_music_candidate", "project_id" => project.fetch("project_id"),
        "candidate_id" => candidate.fetch("candidate_id"), "review_digest" => digest(review),
        "input_digest" => @store.generation_input_digest(input), "artifact_digests" => artifact_digests(candidate),
        "descendant_candidate_ids" => descendant_ids(project.fetch("project_id"), candidate.fetch("candidate_id")),
        "deletes" => %w[FLAC MP3 candidate_input vocal_analysis current_review],
        "retains" => ["small rejection receipt", "prior review-history revisions"],
        "external_export_deleted" => false
      }
    end

    def export_scope(project, candidate, input, review, analysis)
      slug = title_slug(project.fetch("title"))
      {
        "operation" => "export_finished_song", "project_id" => project.fetch("project_id"),
        "candidate_id" => candidate.fetch("candidate_id"), "review_digest" => digest(review),
        "input_digest" => @store.generation_input_digest(input), "artifact_digests" => artifact_digests(candidate),
        "analysis_digest" => analysis && digest(analysis), "destination" => File.join(@export_root, slug),
        "files" => project.fetch("vocal_mode") == "vocal" ? %w[master.flac listening.mp3 song.json song-info.md lyrics.txt] : %w[master.flac listening.mp3 song.json song-info.md],
        "overwrite" => false, "external_publication" => false
      }
    end

    def export_analysis(project, candidate_id)
      return nil if project.fetch("vocal_mode") == "instrumental"
      value = @analysis.read(project_id: project.fetch("project_id"), candidate_id: candidate_id)
      raise MusicProjectStore::ValidationError, "run vocal transcription before exporting a kept song" unless value
      value
    end

    def descendant_ids(project_id, candidate_id)
      generations = @store.generations_path(project_id)
      Dir.children(generations).grep(MusicProjectStore::CANDIDATE_ID).sort.filter_map do |id|
        record = candidate_record(project_id, id)
        id if record["source_candidate_id"] == candidate_id
      end
    end

    def artifact_digests(candidate)
      project_id = candidate.fetch("project_id")
      candidate_id = candidate.fetch("candidate_id")
      %w[flac mp3].to_h do |kind|
        expected = candidate.dig("artifacts", kind, "sha256").to_s
        path = @store.candidate_artifact_path(project_id, candidate_id, kind)
        actual = Digest::SHA256.file(path).hexdigest
        raise MusicProjectStore::IntegrityError, "#{kind} artifact digest does not match its receipt" unless expected.match?(/\A[a-f0-9]{64}\z/) && secure_compare(expected, actual)
        [kind, actual]
      end
    end

    def export_metadata(project, candidate, input, analysis)
      {
        "schema_version" => "soul.music.finished_song.v1", "title" => project.fetch("title"),
        "intent" => project.fetch("intent"), "duration_seconds" => input.fetch("duration"),
        "mode" => project.fetch("vocal_mode"), "rights_status" => project.fetch("rights_status"),
        "bpm" => input.fetch("bpm"), "key" => input.fetch("keyscale"), "time" => input.fetch("timesignature"),
        "seed" => input.fetch("seed"), "sound_and_structure" => input.fetch("caption"),
        "intended_lyrics" => input.fetch("lyrics"), "project_id" => project.fetch("project_id"),
        "candidate_id" => candidate.fetch("candidate_id"), "source_candidate_id" => candidate["source_candidate_id"],
        "transcription" => analysis && { "status" => "complete", "machine_route" => analysis["machine_route"], "sequence_recall" => analysis.dig("alignment", "sequence_recall"), "problem_line_count" => analysis.dig("alignment", "problem_line_count") }
      }
    end

    def song_info(metadata)
      <<~MARKDOWN
        # #{metadata.fetch("title")}

        - Intent: #{metadata.fetch("intent")}
        - Duration: #{metadata.fetch("duration_seconds")} seconds
        - Mode: #{metadata.fetch("mode")}
        - Rights status: #{metadata.fetch("rights_status")}
        - BPM: #{metadata.fetch("bpm")}
        - Key: #{metadata.fetch("key")}
        - Time: #{metadata.fetch("time")}
        - Seed: #{metadata.fetch("seed")}

        ## Sound and Structure

        #{metadata.fetch("sound_and_structure")}

        ## Intended Lyrics and Section Markers

        #{metadata.fetch("intended_lyrics").to_s.empty? ? "Instrumental" : metadata.fetch("intended_lyrics")}
      MARKDOWN
    end

    def prepare_export_root!
      assert_safe_path_components!(@export_parent, base: File.dirname(@export_parent))
      FileUtils.mkdir_p(@export_parent, mode: 0o700)
      assert_safe_path_components!(@export_root, base: @export_parent)
      FileUtils.mkdir_p(@export_root, mode: 0o700)
      File.chmod(0o700, @export_root)
    end

    def prepare_private_directory(path, parent:)
      raise MusicProjectStore::IntegrityError, "private directory escaped its parent" unless within?(path, parent)
      if File.exist?(path) || File.symlink?(path)
        stat = File.lstat(path)
        raise MusicProjectStore::IntegrityError, "private directory is invalid" unless stat.directory? && !stat.symlink?
      else
        Dir.mkdir(path, 0o700)
      end
    end

    def assert_safe_path_components!(path, base:)
      raise MusicProjectStore::IntegrityError, "export path escaped its base" unless within?(path, base)
      current = File.expand_path(base)
      File.expand_path(path).delete_prefix(current).sub(%r{\A/}, "").split(File::SEPARATOR).each do |part|
        current = File.join(current, part)
        next unless File.exist?(current) || File.symlink?(current)
        stat = File.lstat(current)
        raise MusicProjectStore::IntegrityError, "export path contains a symlink" if stat.symlink?
        raise MusicProjectStore::IntegrityError, "export path component is not a directory" unless stat.directory?
      end
    end

    def existing_export(scope)
      receipt_path = File.join(@store.project_path(scope.fetch("project_id")), "exports", "#{scope.fetch("candidate_id")}.json")
      return nil unless File.exist?(receipt_path)
      stat = File.lstat(receipt_path)
      raise MusicProjectStore::IntegrityError, "finished export receipt is invalid" unless stat.file? && !stat.symlink? && stat.size.between?(1, MAX_JSON_BYTES)
      receipt = JSON.parse(File.binread(receipt_path, MAX_JSON_BYTES))
      destination = receipt.fetch("destination")
      raise MusicProjectStore::IntegrityError, "finished export receipt scope changed" unless receipt["scope_digest"] == digest(scope) && destination == scope["destination"] && File.directory?(destination) && !File.symlink?(destination)
      { "export" => receipt }
    rescue JSON::ParserError => error
      raise MusicProjectStore::IntegrityError, "invalid finished export receipt: #{error.class}"
    end

    def copy_verified(source, destination, expected_digest)
      raise MusicProjectStore::IntegrityError, "source artifact digest is missing" unless expected_digest.to_s.match?(/\A[a-f0-9]{64}\z/)
      FileUtils.copy_file(source, destination)
      File.chmod(0o600, destination)
      raise MusicProjectStore::IntegrityError, "copied artifact digest changed" unless Digest::SHA256.file(destination).hexdigest == expected_digest
    end

    def title_slug(title)
      value = title.to_s.downcase.encode("ASCII", invalid: :replace, undef: :replace, replace: "").gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "").slice(0, 80)
      value.empty? ? "untitled-song" : value
    end

    def write_private(path, body)
      File.write(path, body.to_s, mode: "wx", perm: 0o600)
    end

    def atomic_json(path, value, maximum: MusicProjectStore::MAX_PROJECT_BYTES)
      body = JSON.pretty_generate(value) + "\n"
      raise MusicProjectStore::IntegrityError, "music JSON exceeds size limit" if body.bytesize > maximum
      temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.write(temporary, body, mode: "wx", perm: 0o600)
      File.rename(temporary, path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))
    def within?(path, parent) = File.expand_path(path) == File.expand_path(parent) || File.expand_path(path).start_with?(File.expand_path(parent) + File::SEPARATOR)
    def secure_compare(left, right) = left.to_s.bytesize == right.to_s.bytesize && left.to_s.bytes.zip(right.to_s.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    def outcome(state, ok, reason, data: {}, mutation: "none") = { "ok" => ok, "lifecycle_state" => state, "reason" => reason, "data" => data, "mutation" => mutation }
  end
end
