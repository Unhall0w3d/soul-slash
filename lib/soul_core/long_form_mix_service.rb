# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "music_project_store"

module SoulCore
  class LongFormMixService
    SCHEMA_VERSION = "soul.music.long_form_mix.v1"
    PREVIEW_SCHEMA = "soul.music.long_form_mix_handoff_scope.v1"
    EDL_SCHEMA = "soul.music.long_form_mix.edl.v1"
    CONFIRMATION = "EXPORT_MIX_HANDOFF"

    MIX_ID = /\Amix_[a-f0-9]{16}\z/
    PROJECT_ID = /\Amusic_[a-f0-9]{16}\z/
    CANDIDATE_ID = /\Acandidate_[a-f0-9]{16}\z/

    MAX_PLANS = 100
    MAX_SEQUENCE_ITEMS = 100
    MAX_LIMIT = 100
    MAX_TITLE_CHARS = 240
    MAX_INTENT_CHARS = 3_000
    MAX_NOTE_CHARS = 1_200
    MAX_JSON_BYTES = 128 * 1024
    MAX_MANIFEST_BYTES = 512 * 1024
    ROUNDING = 3
    REQUIRED_EXPORT_FILES = %w[master.flac listening.mp3 song.json song-info.md].freeze

    EXPORT_SCHEMA = "soul.music.finished_export.v1"
    SONG_SCHEMA = "soul.music.finished_song.v1"

    EDL_FILE = "mix.edl.json"
    CUE_FILE = "cue-sheet.csv"
    README_FILE = "README.md"
    CHECKSUM_FILE = "checksums.sha256"

    class ValidationError < StandardError; end
    class IntegrityError < StandardError; end

    def initialize(
      root: Dir.pwd,
      export_root: File.join(Dir.home, "Music", "soul-music"),
      export_parent: File.join(Dir.home, "Music"),
      project_store: nil,
      plans_root: nil,
      handoff_root: nil,
      clock: -> { Time.now.utc }
    )
      @root = File.expand_path(root)
      @export_root = File.expand_path(export_root)
      @export_parent = File.expand_path(export_parent)
      @plans_root = File.expand_path(plans_root || File.join(@root, "Soul", "private", "mix_projects"))
      @handoff_root = File.expand_path(handoff_root || File.join(@export_root, "mixes"))
      @store = project_store || MusicProjectStore.new(root: @root)
      @clock = clock

      raise IntegrityError, "music export root must remain inside configured music root" unless within?(@export_root, @export_parent)
      raise IntegrityError, "private mix plan store must remain inside repository" unless within?(@plans_root, @root)
      raise IntegrityError, "handoff package root must remain inside music export root" unless within?(@handoff_root, @export_root)

      assert_no_symlink_path!(@plans_root)
      assert_no_symlink_path!(@handoff_root)
    end

    def sources(limit: 100)
      bounded = bounded_limit(limit)
      source_records = []
      @store.list(limit: MAX_LIMIT).each do |project|
        exports_dir = File.join(@store.project_path(project.fetch("project_id")), "exports")
        next unless File.directory?(exports_dir)

        Dir.children(exports_dir).sort.each do |name|
          next unless name.match?(%r{\Acandidate_[a-f0-9]{16}\.json\z})
          source = source_from_receipt_file(File.join(exports_dir, name))
          source_records << source if source
        end
      end

      source_records.sort_by! { |entry| entry.fetch("exported_at") }
      source_records.reverse!
      source_records = source_records.first(bounded)

      outcome(
        "complete",
        true,
        "eligible long-form mix sources enumerated",
        data: { "sources" => source_records }
      )
    rescue ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def list(limit: 100)
      bounded = bounded_limit(limit)
      plans = list_plan_paths.map { |path| parse_plan(path) }
      plans.sort_by! { |plan| plan.fetch("created_at") }
      plans.reverse!
      plans = plans.first(bounded)

      outcome("complete", true, "mix plans listed", data: { "mixes" => plans })
    rescue ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def get(mix_id:)
      id = mix_id.to_s
      raise ValidationError, "mix_id is required" if id.empty?
      raise ValidationError, "mix_id is invalid" unless MIX_ID.match?(id)

      path = File.join(@plans_root, "#{id}.json")
      raise IntegrityError, "mix plan file is missing" unless File.file?(path)
      raise IntegrityError, "mix plan file is a symlink" if File.symlink?(path)

      outcome("complete", true, "mix plan loaded", data: { "mix" => parse_plan(path) })
    rescue ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue IntegrityError, JSON::ParserError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def create(plan:)
      prepared = prepare_plan(plan)
      prepare_root!(@plans_root)
      path = File.join(@plans_root, "#{prepared.fetch("mix_id")}.json")

      if File.exist?(path)
        existing = parse_plan(path)
        raise IntegrityError, "mix plan id collision detected" unless secure_compare(digest(plan_identity(prepared)), digest(plan_identity(existing)))
        return outcome(
          "complete",
          true,
          "this exact mix plan already exists",
          data: { "mix" => existing, "idempotent_replay" => true },
          mutation: "none"
        )
      end

      raise IntegrityError, "mix plan storage is at capacity" if list_plan_paths.length >= MAX_PLANS
      write_json(path, prepared)
      outcome("complete", true, "long-form mix plan created", data: { "mix" => prepared }, mutation: "long_form_mix_created")
    rescue ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def handoff_preview(mix_id:)
      scope, mix_record = handoff_scope(mix_id: mix_id)
      existing = existing_package(scope)
      return outcome(
        "complete",
        true,
        "this exact mix handoff package already exists",
        data: { "mix" => mix_record, "package" => existing, "idempotent_replay" => true },
        mutation: "none"
      ) if existing

      outcome(
        "blocked_for_human_review",
        true,
        "exact long-form mix handoff confirmation required",
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

    def handoff_execute(mix_id:, confirmation:, expected_digest:)
      return outcome("awaiting_input", false, "confirmation and expected_digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?

      scope, mix_record = handoff_scope(mix_id: mix_id)
      return outcome("blocked_for_human_review", false, "exact long-form mix handoff confirmation did not match") unless confirmation == CONFIRMATION
      return outcome("blocked_for_human_review", false, "long-form mix handoff state changed; preview again") unless secure_compare(expected_digest.to_s, digest(scope))

      existing = existing_package(scope)
      return outcome(
        "complete",
        true,
        "this exact mix handoff package already exists",
        data: { "mix" => mix_record, "package" => existing, "idempotent_replay" => true },
        mutation: "none"
      ) if existing

      prepare_root!(@handoff_root)
      destination = scope.fetch("destination")
      raise IntegrityError, "mix handoff destination already exists" if File.exist?(destination) || File.symlink?(destination)
      assert_no_symlink_path!(destination)

      staging = File.join(@handoff_root, ".#{File.basename(destination)}.partial-#{SecureRandom.hex(6)}")
      FileUtils.mkdir_p(staging, mode: 0o700)

      begin
        csv_rows = ["index,source_id,project_id,candidate_id,source_file,trim_start_seconds,trim_end_seconds,crossfade_seconds,transition_note,start_seconds,end_seconds,duration_seconds"]
        source_digests = {}
        source_files = []

        scope.fetch("files").each do |entry|
          next unless entry.fetch("kind") == "source_flac"

          source_path = entry.fetch("source_path")
          filename = entry.fetch("filename")
          destination_source = File.join(staging, filename)

          copy_verified_file(source_path, destination_source, entry.fetch("source_sha256"))
          actual = Digest::SHA256.file(destination_source).hexdigest
          source_digests[filename] = actual
          source_files << filename

          csv_rows << [
            entry.fetch("track_index"),
            entry.fetch("source_id"),
            entry.fetch("project_id"),
            entry.fetch("candidate_id"),
            filename,
            format_number(entry.fetch("trim_start_seconds")),
            format_number(entry.fetch("trim_end_seconds")),
            format_number(entry.fetch("crossfade_seconds")),
            quote_csv(entry.fetch("transition_note")),
            format_number(entry.fetch("start_seconds")),
            format_number(entry.fetch("end_seconds")),
            format_number(entry.fetch("duration_seconds"))
          ].join(",")
        end

        edl = {
          "schema_version" => EDL_SCHEMA,
          "mix_id" => mix_record.fetch("mix_id"),
          "title" => mix_record.fetch("title"),
          "intent" => mix_record.fetch("intent"),
          "scope_digest" => digest(scope),
          "timeline_seconds" => mix_record.fetch("timeline_seconds"),
          "total_duration_seconds" => mix_record.fetch("total_duration_seconds"),
          "source_count" => scope.fetch("source_count"),
          "sequence" => scope.fetch("sequence"),
          "tracks" => scope.fetch("tracks"),
          "prepared_at" => @clock.call.iso8601,
          "created_at" => mix_record.fetch("created_at")
        }
        write_json(File.join(staging, EDL_FILE), edl)
        File.write(File.join(staging, CUE_FILE), csv_rows.join("\n") + "\n", perm: 0o600)

        readme = <<~README
          # #{mix_record.fetch("title")}

          This package is a bounded long-form mix handoff for a stereo-source
          editor.

          Mix id: #{mix_record.fetch("mix_id")}
          Intent: #{mix_record.fetch("intent")}
          Total duration (seconds): #{format_number(mix_record.fetch("total_duration_seconds"))}
          Source tracks: #{scope.fetch("source_count")}

          The copied FLAC files are finished stereo masters. This package does
          not contain separated stems, a newly rendered mix, or a native project
          for FL Studio, Ableton Live, Logic Pro, or another DAW. Use the EDL and
          cue sheet to reconstruct the reviewed running order in the editor of
          your choice.
        README
        File.write(File.join(staging, README_FILE), readme + "\n", perm: 0o600)

        required_checksums = {}
        required_checksums[EDL_FILE] = Digest::SHA256.file(File.join(staging, EDL_FILE)).hexdigest
        required_checksums[CUE_FILE] = Digest::SHA256.file(File.join(staging, CUE_FILE)).hexdigest
        required_checksums[README_FILE] = Digest::SHA256.file(File.join(staging, README_FILE)).hexdigest
        source_digests.each { |name, value| required_checksums[name] = value }
        write_checksum_manifest(File.join(staging, CHECKSUM_FILE), required_checksums)

        final_checksums = parse_checksum_manifest(File.join(staging, CHECKSUM_FILE))
        final_checksums.each do |name, expected|
          path = File.join(staging, name)
          actual = Digest::SHA256.file(path).hexdigest
          raise IntegrityError, "prepared checksum invalid for #{name}" unless secure_compare(actual, expected)
        end

        File.rename(staging, destination)

        package = {
          "mix_id" => mix_record.fetch("mix_id"),
          "title" => mix_record.fetch("title"),
          "intent" => mix_record.fetch("intent"),
          "destination" => destination,
          "scope_digest" => digest(scope),
          "prepared_at" => @clock.call.iso8601,
          "files" => [EDL_FILE, CUE_FILE, README_FILE, CHECKSUM_FILE] + source_files,
          "checksums" => final_checksums
        }
        outcome(
          "complete",
          true,
          "long-form mix handoff package prepared",
          data: { "mix" => mix_record, "package" => package },
          mutation: "long_form_mix_handoff_prepared"
        )
      ensure
        FileUtils.rm_rf(staging) if staging && File.directory?(staging) && !File.symlink?(staging)
      end
    rescue ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    private

    def prepare_plan(input)
      value = input.to_h
      title = value.fetch("title").to_s.strip
      intent = value.fetch("intent").to_s.strip

      raise ValidationError, "title is required" if title.empty?
      raise ValidationError, "intent is required" if intent.empty?
      raise ValidationError, "title exceeds #{MAX_TITLE_CHARS} characters" if title.length > MAX_TITLE_CHARS
      raise ValidationError, "intent exceeds #{MAX_INTENT_CHARS} characters" if intent.length > MAX_INTENT_CHARS

      sequence = value.fetch("sequence")
      raise ValidationError, "sequence must be an array" unless sequence.is_a?(Array)
      raise ValidationError, "sequence cannot be empty" if sequence.empty?
      raise ValidationError, "sequence has too many items" if sequence.length > MAX_SEQUENCE_ITEMS

      prepared = []
      previous = nil
      sequence.each_with_index do |entry, index|
        prepared << normalize_sequence_entry(entry, index: index, previous_entry: previous)
        previous = prepared.last
      end

      timeline = timeline_seconds(prepared)

      parent_mix_id = value.fetch("parent_mix_id", "").to_s.strip
      if parent_mix_id.empty?
        parent_mix_id = nil
      else
        raise ValidationError, "parent_mix_id is invalid" unless parent_mix_id.match?(MIX_ID)
        parse_plan_file(parent_mix_id)
      end

      {
        "schema_version" => SCHEMA_VERSION,
        "mix_id" => derived_mix_id(title: title, intent: intent, parent_mix_id: parent_mix_id.to_s, sequence: prepared),
        "parent_mix_id" => parent_mix_id,
        "title" => title,
        "intent" => intent,
        "sequence" => prepared,
        "timeline_seconds" => timeline,
        "total_duration_seconds" => timeline.fetch(-1).fetch("end_seconds"),
        "created_at" => @clock.call.iso8601,
        "updated_at" => @clock.call.iso8601
      }
    end

    def normalize_sequence_entry(entry, index:, previous_entry:)
      data = entry.to_h
      required = %w[project_id candidate_id trim_start_seconds trim_end_seconds crossfade_seconds transition_note]
      missing = required.reject { |key| data.key?(key) }
      raise ValidationError, "sequence entry is incomplete" unless missing.empty?

      project_id = data.fetch("project_id").to_s
      candidate_id = data.fetch("candidate_id").to_s
      source_id = data.fetch("source_id", "#{project_id}/#{candidate_id}").to_s

      raise ValidationError, "project_id is invalid" unless project_id.match?(PROJECT_ID)
      raise ValidationError, "candidate_id is invalid" unless candidate_id.match?(CANDIDATE_ID)
      raise ValidationError, "source_id must be project/candidate" unless source_id == "#{project_id}/#{candidate_id}"

      trim_start = parse_seconds(data.fetch("trim_start_seconds"), "trim_start_seconds")
      trim_end = parse_seconds(data.fetch("trim_end_seconds"), "trim_end_seconds")
      crossfade = parse_seconds(data.fetch("crossfade_seconds"), "crossfade_seconds")

      raise ValidationError, "trim_end must be greater than trim_start" unless trim_end > trim_start

      transition_note = data.fetch("transition_note").to_s
      raise ValidationError, "transition_note exceeds #{MAX_NOTE_CHARS} characters" if transition_note.length > MAX_NOTE_CHARS

      source = source_from_ids(project_id: project_id, candidate_id: candidate_id, source_id: source_id)
      source_duration = source.fetch("duration_seconds")
      raise ValidationError, "trim_start is outside source duration" unless trim_start <= source_duration
      raise ValidationError, "trim_end is outside source duration" unless trim_end <= source_duration

      effective = rounded(trim_end - trim_start)
      raise ValidationError, "trim range must be positive" unless effective.positive?

      if index.zero?
        raise ValidationError, "first crossfade must be exactly 0" unless rounded(crossfade).zero?
      else
        previous_duration = previous_entry.fetch("duration_seconds")
        raise ValidationError, "crossfade must be finite and nonnegative" unless crossfade.finite? && crossfade >= 0.0
        raise ValidationError, "crossfade must not exceed 10 seconds" if crossfade > 10.0
        raise ValidationError, "crossfade must be less than source effective length" unless crossfade < effective
        raise ValidationError, "crossfade must be less than adjacent source effective lengths" unless crossfade < previous_duration
      end

      {
        "source_id" => source_id,
        "project_id" => project_id,
        "candidate_id" => candidate_id,
        "source_master_sha256" => source.fetch("source_master_sha256"),
        "trim_start_seconds" => rounded(trim_start),
        "trim_end_seconds" => rounded(trim_end),
        "crossfade_seconds" => rounded(crossfade),
        "duration_seconds" => effective,
        "transition_note" => transition_note
      }
    end

    def timeline_seconds(sequence)
      cursor = 0.0
      sequence.each_with_index.map do |entry, index|
        start_seconds = index.zero? ? 0.0 : rounded(cursor - entry.fetch("crossfade_seconds"))
        raise ValidationError, "timeline start must be nonnegative" if start_seconds.negative?
        duration_seconds = entry.fetch("duration_seconds")
        end_seconds = rounded(start_seconds + duration_seconds)
        cursor = end_seconds
        {
          "index" => index,
          "source_id" => entry.fetch("source_id"),
          "start_seconds" => start_seconds,
          "end_seconds" => end_seconds,
          "duration_seconds" => duration_seconds
        }
      end
    end

    def derived_mix_id(title:, intent:, parent_mix_id:, sequence:)
      value = JSON.generate({ "title" => title, "intent" => intent, "parent_mix_id" => parent_mix_id, "sequence" => sequence })
      mix_id = "mix_#{Digest::SHA256.hexdigest(value)[0, 16]}"
      raise IntegrityError, "generated mix id is invalid" unless mix_id.match?(MIX_ID)
      mix_id
    end

    def handoff_scope(mix_id:)
      id = mix_id.to_s
      raise ValidationError, "mix_id is required" if id.empty?
      raise ValidationError, "mix_id is invalid" unless MIX_ID.match?(id)
      mix = parse_plan_file(id)

      files = []
      source_digests = {}
      mix.fetch("sequence").each_with_index do |entry, index|
        source = source_from_ids(
          project_id: entry.fetch("project_id"),
          candidate_id: entry.fetch("candidate_id"),
          source_id: entry.fetch("source_id")
        )
        source_paths = source.fetch("source_paths")
        source_path = source_paths.fetch("master.flac") { source_paths.fetch("master_flac") }
        filename = "source_#{format("%02d", index)}_#{sanitize_filename(entry.fetch("source_id").gsub("/", "-"))}.flac"
        timeline = mix.fetch("timeline_seconds").fetch(index)
        files << {
          "kind" => "source_flac",
          "source_id" => entry.fetch("source_id"),
          "project_id" => entry.fetch("project_id"),
          "candidate_id" => entry.fetch("candidate_id"),
          "filename" => filename,
          "source_path" => source_path,
          "source_sha256" => source.fetch("source_master_sha256"),
          "trim_start_seconds" => entry.fetch("trim_start_seconds"),
          "trim_end_seconds" => entry.fetch("trim_end_seconds"),
          "crossfade_seconds" => entry.fetch("crossfade_seconds"),
          "transition_note" => entry.fetch("transition_note"),
          "duration_seconds" => timeline.fetch("duration_seconds"),
          "start_seconds" => timeline.fetch("start_seconds"),
          "end_seconds" => timeline.fetch("end_seconds"),
          "track_index" => index
        }
        source_digests[filename] = source.fetch("source_master_sha256")
      end

      files << { "kind" => "manifest", "filename" => EDL_FILE }
      files << { "kind" => "manifest", "filename" => CUE_FILE }
      files << { "kind" => "manifest", "filename" => README_FILE }
      files << { "kind" => "manifest", "filename" => CHECKSUM_FILE }

      scope = {
        "schema_version" => PREVIEW_SCHEMA,
        "operation" => "export_long_form_mix_handoff",
        "mix_id" => mix.fetch("mix_id"),
        "title" => mix.fetch("title"),
        "intent" => mix.fetch("intent"),
        "destination" => File.join(@handoff_root, "#{slugify(mix.fetch("title"))}-#{mix.fetch("mix_id")}"),
        "source_count" => mix.fetch("sequence").length,
        "sequence" => mix.fetch("sequence"),
        "tracks" => mix.fetch("timeline_seconds"),
        "total_duration_seconds" => mix.fetch("total_duration_seconds"),
        "files" => files,
        "source_file_digests" => source_digests
      }

      [scope, mix]
    end

    def existing_package(scope)
      destination = scope.fetch("destination")
      return nil unless File.directory?(destination) && !File.symlink?(destination)

      files = scope.fetch("files").map { |entry| entry.fetch("filename") }
      checksums = parse_checksum_manifest(File.join(destination, CHECKSUM_FILE))
      expected_checksum_files = files - [CHECKSUM_FILE]
      raise IntegrityError, "mix handoff checksum inventory changed" unless checksums.keys.sort == expected_checksum_files.sort

      files.each do |filename|
        path = File.join(destination, filename)
        raise IntegrityError, "mix handoff package is incomplete" unless File.file?(path) && !File.symlink?(path)
      end

      manifest = parse_json(File.join(destination, EDL_FILE))
      raise IntegrityError, "mix handoff manifest is invalid" unless manifest.fetch("schema_version") == EDL_SCHEMA
      raise IntegrityError, "mix handoff scope changed" unless secure_compare(manifest.fetch("scope_digest", ""), digest(scope))

      source_count = manifest.fetch("source_count")
      raise IntegrityError, "mix handoff source_count mismatch" unless source_count == scope.fetch("source_count")

      checksums.each do |name, value|
        actual = Digest::SHA256.file(File.join(destination, name)).hexdigest
        raise IntegrityError, "mix handoff checksum mismatch for #{name}" unless secure_compare(actual, value)
      end

      source_digests = scope.fetch("source_file_digests")
      source_digests.each do |filename, expected|
        actual = Digest::SHA256.file(File.join(destination, filename)).hexdigest
        raise IntegrityError, "mix handoff source checksum mismatch for #{filename}" unless secure_compare(actual, expected)
      end

      {
        "destination" => destination,
        "files" => files,
        "checksums" => checksums
      }
    rescue Errno::ENOENT
      nil
    end

    def source_from_receipt_file(path)
      raise IntegrityError, "music export receipt is invalid" unless File.file?(path) && !File.symlink?(path)
      raise IntegrityError, "music export receipt is too large" if File.size(path) > MAX_JSON_BYTES

      receipt = parse_json(path)
      return nil unless receipt.fetch("schema_version") == EXPORT_SCHEMA

      project_id = receipt.fetch("project_id").to_s
      candidate_id = receipt.fetch("candidate_id").to_s
      raise IntegrityError, "source project_id is invalid" unless project_id.match?(PROJECT_ID)
      raise IntegrityError, "source candidate_id is invalid" unless candidate_id.match?(CANDIDATE_ID)

      review = @store.read_review(project_id, candidate_id)
      raise ValidationError, "mix source requires reviewed keep disposition" unless review && review["disposition"] == "keep"

      destination = File.expand_path(receipt.fetch("destination"))
      raise IntegrityError, "source export destination is outside configured music tree" unless within?(destination, @export_root)
      raise IntegrityError, "source export destination is missing" unless File.directory?(destination)
      raise IntegrityError, "source export destination is a symlink" if File.symlink?(destination)
      raise IntegrityError, "source export destination is unsafe" if path_has_symlink?(destination)

      song = parse_json(File.join(destination, "song.json"))
      raise IntegrityError, "source metadata schema is invalid" unless song.fetch("schema_version") == SONG_SCHEMA
      duration = parse_seconds(song.fetch("duration_seconds"), "song duration")

      source_digests = {}
      source_paths = {}
      REQUIRED_EXPORT_FILES.each do |filename|
        file_path = File.join(destination, filename)
        raise IntegrityError, "source file is missing: #{filename}" unless File.file?(file_path) && !File.symlink?(file_path)
        actual = Digest::SHA256.file(file_path).hexdigest
        recorded = receipt.fetch("files", {}).to_h.fetch(filename, nil)
        raise IntegrityError, "source file digest is missing: #{filename}" if recorded.to_s.empty?
        raise IntegrityError, "source file digest changed: #{filename}" unless secure_compare(recorded, actual)

        source_digests[filename] = actual
        source_paths[filename.tr("-", "_")] = file_path
      end

      {
        "project_id" => project_id,
        "candidate_id" => candidate_id,
        "source_id" => "#{project_id}/#{candidate_id}",
        "source_paths" => source_paths,
        "source_digests" => source_digests,
        "source_master_sha256" => source_digests.fetch("master.flac"),
        "duration_seconds" => duration,
        "exported_at" => receipt.fetch("exported_at", "1970-01-01T00:00:00Z"),
        "project_title" => @store.read(project_id).fetch("title"),
        "project_intent" => @store.read(project_id).fetch("intent")
      }
    end

    def source_from_ids(project_id:, candidate_id:, source_id:)
      expected_id = "#{project_id}/#{candidate_id}"
      raise ValidationError, "source_id is invalid" unless source_id == expected_id
      exports = File.join(@store.project_path(project_id), "exports")
      raise IntegrityError, "music exports folder is missing" unless File.directory?(exports)
      source_record = source_from_receipt_file(File.join(exports, "#{candidate_id}.json"))
      raise ValidationError, "mix source missing finished export receipt" unless source_record
      source_record
    end

    def parse_plan(path)
      value = parse_json(path)
      validate_plan(value)
      value
    end

    def parse_plan_file(id)
      parse_plan(File.join(@plans_root, "#{id}.json"))
    end

    def parse_checksum_manifest(path)
      raise IntegrityError, "checksum manifest is missing or unsafe" unless File.file?(path) && !File.symlink?(path)
      body = File.binread(path, MAX_MANIFEST_BYTES + 1)
      raise IntegrityError, "checksum manifest is too large" if body.bytesize > MAX_MANIFEST_BYTES
      manifest = {}
      body.each_line do |line|
        next if line.strip.empty?
        value, name = line.strip.split(/\s+/, 2)
        name = name.to_s.sub(/\A\*/, "")
        raise IntegrityError, "checksum manifest is malformed" unless !name.empty? && value && value.match?(/\A[a-f0-9]{64}\z/i)
        raise IntegrityError, "checksum manifest filename is unsafe" unless name.match?(/\A[a-zA-Z0-9._-]+\z/)
        manifest[name] = value
      end
      manifest
    end

    def write_checksum_manifest(path, checksums)
      body = checksums.sort.to_h.map { |name, value| "#{value}  #{name}" }.join("\n")
      body << "\n"
      File.write(path, body, perm: 0o600)
    end

    def validate_plan(plan)
      raise IntegrityError, "mix plan schema is invalid" unless plan.fetch("schema_version") == SCHEMA_VERSION
      raise IntegrityError, "mix id is invalid" unless plan.fetch("mix_id").to_s.match?(MIX_ID)
      raise IntegrityError, "mix plan title is invalid" if plan.fetch("title").to_s.empty? || plan.fetch("title").to_s.length > MAX_TITLE_CHARS
      raise IntegrityError, "mix intent is invalid" if plan.fetch("intent").to_s.empty? || plan.fetch("intent").to_s.length > MAX_INTENT_CHARS

      timeline = plan.fetch("timeline_seconds")
      sequence = plan.fetch("sequence")
      raise IntegrityError, "mix timeline is invalid" unless timeline.is_a?(Array) && timeline.length <= MAX_SEQUENCE_ITEMS
      raise IntegrityError, "mix sequence is invalid" unless sequence.is_a?(Array) && sequence.length == timeline.length && sequence.length.between?(1, MAX_SEQUENCE_ITEMS)

      normalized = []
      sequence.each_with_index do |entry, index|
        normalized << validate_plan_sequence_entry(entry, index: index, previous_entry: index.zero? ? nil : normalized[index - 1])
      end

      expected = timeline_seconds(normalized)
      raise IntegrityError, "stored mix timeline is not deterministic" unless expected == timeline
      raise IntegrityError, "stored mix duration mismatch" unless expected.fetch(-1, {}).fetch("end_seconds", 0.0) == plan.fetch("total_duration_seconds")
    end

    def validate_plan_sequence_entry(entry, index:, previous_entry:)
      source_id = entry.to_h.fetch("source_id").to_s
      data = entry.to_h
      required = %w[source_id project_id candidate_id source_master_sha256 trim_start_seconds trim_end_seconds crossfade_seconds duration_seconds transition_note]
      missing = required - data.keys
      raise IntegrityError, "stored mix sequence entry is missing required fields: #{missing.join(', ')}" unless missing.empty?

      normalized = normalize_sequence_entry(
        {
          "project_id" => data.fetch("project_id"),
          "candidate_id" => data.fetch("candidate_id"),
          "trim_start_seconds" => data.fetch("trim_start_seconds"),
          "trim_end_seconds" => data.fetch("trim_end_seconds"),
          "crossfade_seconds" => data.fetch("crossfade_seconds"),
          "source_id" => source_id,
          "transition_note" => data.fetch("transition_note")
        },
        index: index,
        previous_entry: previous_entry
      )

      raise IntegrityError, "mix sequence entry is not deterministic" unless rounded(data.fetch("trim_start_seconds")) == normalized.fetch("trim_start_seconds") &&
        rounded(data.fetch("trim_end_seconds")) == normalized.fetch("trim_end_seconds") &&
        rounded(data.fetch("crossfade_seconds")) == normalized.fetch("crossfade_seconds") &&
        rounded(data.fetch("duration_seconds")) == normalized.fetch("duration_seconds")
      raise IntegrityError, "stored sequence source hash does not match source record" unless secure_compare(data.fetch("source_master_sha256"), normalized.fetch("source_master_sha256"))
      raise IntegrityError, "stored mix duration mismatch" unless rounded(data.fetch("duration_seconds")) == normalized.fetch("duration_seconds")
      raise IntegrityError, "stored source_id mismatch" unless data.fetch("source_id") == normalized.fetch("source_id")
      raise IntegrityError, "stored transition_note changed" unless data.fetch("transition_note").to_s == normalized.fetch("transition_note")

      normalized
    end

    def copy_verified_file(source, destination, expected)
      FileUtils.copy_file(source, destination, true)
      File.chmod(0o600, destination)
      actual = Digest::SHA256.file(destination).hexdigest
      raise IntegrityError, "copied source checksum mismatch" unless secure_compare(actual, expected)
      actual
    end

    def list_plan_paths
      return [] unless File.directory?(@plans_root)
      Dir.children(@plans_root)
        .select { |name| name.match?(%r{\Amix_[a-f0-9]{16}\.json\z}) }
        .map { |name| File.join(@plans_root, name) }
        .sort
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
      value.round(ROUNDING)
    end

    def format_number(value)
      format("%.#{ROUNDING}f", rounded(value))
    end

    def quote_csv(value)
      text = value.to_s.gsub('"', '""')
      needs_quotes = text.include?(",") || text.include?("\n") || text.include?("\r")
      needs_quotes ? %("#{text}") : text
    end

    def path_has_symlink?(path)
      return false unless File.directory?(path)
      Dir.children(path).any? { |name| File.symlink?(File.join(path, name)) }
    end

    def bounded_limit(value)
      bounded = Integer(value)
      return 1 if bounded < 1
      [bounded, MAX_LIMIT].min
    rescue ArgumentError, TypeError
      1
    end

    def slugify(value)
      slug = value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      slug = slug.gsub(/[-_]+/, "-")
      return "long-form-mix" if slug.empty?
      slug[0, 80]
    end

    def sanitize_filename(value)
      name = value.to_s.gsub(/[^a-zA-Z0-9._-]/, "-").gsub(/-+/, "-").gsub(/\A-+|-+\z/, "")
      fallback = "source"
      return fallback if name.empty?
      name[0, 60]
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

    def parse_json(path)
      raise IntegrityError, "record path is invalid" unless File.file?(path) && !File.symlink?(path)
      body = File.binread(path, MAX_JSON_BYTES + 1)
      raise IntegrityError, "record is too large" if body.bytesize > MAX_JSON_BYTES
      JSON.parse(body)
    rescue JSON::ParserError => error
      raise IntegrityError, "record JSON is invalid: #{error.class}"
    end

    def write_json(path, payload)
      body = JSON.pretty_generate(payload) + "\n"
      raise IntegrityError, "plan JSON exceeds maximum size" if body.bytesize > MAX_JSON_BYTES
      temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, File::CREAT | File::EXCL | File::WRONLY, 0o600) do |file|
        file.write(body)
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary && File.file?(temporary)
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

    def plan_identity(plan)
      plan.reject { |key, _value| %w[created_at updated_at].include?(key) }
    end

    def outcome(state, ok, reason, data: {}, mutation: "none")
      { "ok" => ok, "lifecycle_state" => state, "reason" => reason, "data" => data, "mutation" => mutation }
    end
  end
end
