# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "securerandom"
require "time"

module SoulCore
  class MusicReferenceLibraryStore
    DIRECTORY = File.join("Soul", "music", "references")
    TRACK_SCHEMA = "soul.music.reference.track.v1"
    FUSION_SCHEMA = "soul.music.reference.fusion.v1"
    REFERENCE_ID = /\Aref_[a-f0-9]{16}\z/
    FUSION_ID = /\Afusion_[a-f0-9]{16}\z/
    MAX_RECORDS = 1_000
    MAX_RECORD_BYTES = 128 * 1024
    MAX_TEXT = 8_000
    RIGHTS = %w[analysis_only owned licensed public_domain].freeze
    STATUSES = %w[candidate approved rejected].freeze

    class ValidationError < StandardError; end
    class StaleStateError < ValidationError; end
    class IntegrityError < StandardError; end

    def initialize(root: Dir.pwd, directory: DIRECTORY, clock: -> { Time.now.utc }, id_generator: -> { SecureRandom.hex(8) })
      @root = File.expand_path(root)
      @directory = File.expand_path(directory, @root)
      @clock = clock
      @id_generator = id_generator
      raise ValidationError, "music reference root must remain inside the repository root" unless within?(@directory, @root)
    end

    attr_reader :directory

    def synthesis_revision_id
      id = "syn_#{@id_generator.call}"
      raise IntegrityError, "generated synthesis revision ID is invalid" unless id.match?(/\Asyn_[a-f0-9]{16}\z/)
      id
    end

    def list(limit: 200)
      prepare_root!
      bounded = [[Integer(limit), 1].max, 500].min
      tracks = read_collection("tracks", REFERENCE_ID, TRACK_SCHEMA)
      fusions = read_collection("fusions", FUSION_ID, FUSION_SCHEMA)
      selected_tracks = tracks.sort_by { |item| item.fetch("created_at") }.reverse.first(bounded)
      selected_fusions = fusions.sort_by { |item| item.fetch("created_at") }.reverse.first(bounded)
      {
        "tracks" => selected_tracks,
        "fusions" => selected_fusions,
        "artists" => artist_hierarchy(selected_tracks),
        "count" => selected_tracks.length + selected_fusions.length
      }
    rescue ArgumentError, TypeError
      raise ValidationError, "music reference limit must be an integer"
    end

    def read(identifier)
      id = identifier.to_s
      kind, schema = if id.match?(REFERENCE_ID)
        ["tracks", TRACK_SCHEMA]
      elsif id.match?(FUSION_ID)
        ["fusions", FUSION_SCHEMA]
      else
        raise ValidationError, "music reference ID is invalid"
      end
      prepare_root!
      read_record(File.join(@directory, kind, "#{id}.json"), id, schema)
    end

    # Future bounded analyzers use this exact persistence seam. A5.1 deliberately
    # exposes no application mutation that calls it.
    def write_track(record)
      data = stringify_keys(record)
      prepare_root!
      id = data["reference_id"] || "ref_#{@id_generator.call}"
      now = @clock.call.iso8601
      value = {
        "schema_version" => TRACK_SCHEMA,
        "reference_id" => id,
        "record_type" => "track",
        "status" => data.fetch("status", "candidate"),
        "provenance" => data.fetch("provenance"),
        "evidence" => data.fetch("evidence", default_evidence),
        "synthesis" => normalize_synthesis(data.fetch("synthesis", { "status" => "pending", "selected_revision_id" => nil, "rejected_revision_ids" => [], "revisions" => [] })),
        "created_at" => data.fetch("created_at", now),
        "updated_at" => now
      }
      validate_track!(value, id)
      write_new("tracks", id, value)
    end

    def write_fusion(record)
      data = stringify_keys(record)
      prepare_root!
      id = data["fusion_id"] || "fusion_#{@id_generator.call}"
      now = @clock.call.iso8601
      value = {
        "schema_version" => FUSION_SCHEMA,
        "fusion_id" => id,
        "record_type" => "fusion",
        "status" => data.fetch("status", "candidate"),
        "title" => data.fetch("title"),
        "source_reference_ids" => data.fetch("source_reference_ids"),
        "roles" => data.fetch("roles"),
        "synthesis" => normalize_synthesis(data.fetch("synthesis")),
        "created_at" => data.fetch("created_at", now),
        "updated_at" => now
      }
      validate_fusion!(value, id)
      value.fetch("source_reference_ids").each { |reference_id| read(reference_id) }
      write_new("fusions", id, value)
    end

    def append_synthesis_revision(identifier, revision)
      with_record_lock(identifier) do
        current = read(identifier)
        data = stringify_keys(revision)
        revision_id = data.fetch("revision_id")
        raise ValidationError, "synthesis revision already exists" if current.dig("synthesis", "revisions").any? { |item| item["revision_id"] == revision_id }
        validate_synthesis_revision!(data)
        revisions = current.dig("synthesis", "revisions")
        raise ValidationError, "first synthesis revision must use all scope" if revisions.empty? && data["scope"] != "all"
        raise ValidationError, "music synthesis revision limit exceeded" if revisions.length >= 100
        updated = deep_copy(current)
        updated.fetch("synthesis").fetch("revisions") << data
        updated.fetch("synthesis")["status"] = "candidate"
        updated["status"] = "candidate" unless updated.dig("synthesis", "selected_revision_id")
        updated["updated_at"] = @clock.call.iso8601
        validate_for_identity!(updated, identifier)
        replace_record(identifier, updated)
      end
    end

    def approve_synthesis(identifier, revision_id, expected_state:)
      with_record_lock(identifier) do
        current = read(identifier)
        revision = current.dig("synthesis", "revisions").find { |item| item["revision_id"] == revision_id.to_s }
        raise ValidationError, "synthesis revision does not exist" unless revision
        raise ValidationError, "rejected synthesis revision cannot be approved" if current.dig("synthesis", "rejected_revision_ids").include?(revision_id.to_s)
        next current if current.dig("synthesis", "status") == "approved" && current.dig("synthesis", "selected_revision_id") == revision_id
        actual_state = {
          "currently_selected_revision_id" => current.dig("synthesis", "selected_revision_id"),
          "latest_revision_id" => current.dig("synthesis", "revisions").last&.fetch("revision_id"),
          "revision_count" => current.dig("synthesis", "revisions").length
        }
        raise StaleStateError, "synthesis state changed; preview approval again" unless actual_state == expected_state
        updated = deep_copy(current)
        updated.fetch("synthesis")["status"] = "approved"
        updated.fetch("synthesis")["selected_revision_id"] = revision_id.to_s
        updated["status"] = "approved"
        updated["title"] = revision.fetch("title") if identifier.to_s.match?(FUSION_ID)
        updated["updated_at"] = @clock.call.iso8601
        validate_for_identity!(updated, identifier)
        replace_record(identifier, updated)
      end
    end

    def reject_synthesis(identifier, revision_id, expected_state:)
      with_record_lock(identifier) do
        current = read(identifier)
        synthesis = current.fetch("synthesis")
        revision = synthesis.fetch("revisions").find { |item| item["revision_id"] == revision_id.to_s }
        raise ValidationError, "synthesis revision does not exist" unless revision
        return current if synthesis.fetch("rejected_revision_ids").include?(revision_id.to_s)
        raise ValidationError, "only the latest unapproved synthesis revision can be rejected" unless synthesis.fetch("revisions").last["revision_id"] == revision_id.to_s && synthesis["selected_revision_id"] != revision_id.to_s
        actual_state = {
          "currently_selected_revision_id" => synthesis["selected_revision_id"],
          "latest_revision_id" => synthesis.fetch("revisions").last&.fetch("revision_id"),
          "revision_count" => synthesis.fetch("revisions").length
        }
        raise StaleStateError, "synthesis state changed; preview rejection again" unless actual_state == expected_state
        updated = deep_copy(current)
        updated.fetch("synthesis").fetch("rejected_revision_ids") << revision_id.to_s
        if updated.dig("synthesis", "selected_revision_id")
          updated.fetch("synthesis")["status"] = "approved"
          updated["status"] = "approved"
        else
          updated.fetch("synthesis")["status"] = "rejected"
          updated["status"] = "rejected"
        end
        updated["updated_at"] = @clock.call.iso8601
        validate_for_identity!(updated, identifier)
        replace_record(identifier, updated)
      end
    end

    def delete_track(reference_id, expected_state:)
      with_record_lock(reference_id) do
        current = read(reference_id)
        raise ValidationError, "only track reference profiles can be deleted" unless current["record_type"] == "track"
        dependencies = read_collection("fusions", FUSION_ID, FUSION_SCHEMA).select { |fusion| fusion.fetch("source_reference_ids").include?(reference_id.to_s) }.map { |fusion| fusion.fetch("fusion_id") }.sort
        actual = { "record_digest" => Digest::SHA256.hexdigest(JSON.generate(current)), "dependent_fusion_ids" => dependencies }
        raise StaleStateError, "music reference state changed; preview deletion again" unless actual == expected_state
        raise ValidationError, "music reference is used by fusion profiles: #{dependencies.join(', ')}" unless dependencies.empty?
        path = File.join(@directory, "tracks", "#{reference_id}.json")
        stat = File.lstat(path)
        raise IntegrityError, "music reference record must remain a regular file" unless stat.file? && !stat.symlink?
        File.unlink(path)
        raise IntegrityError, "music reference deletion could not be verified" if File.exist?(path) || File.symlink?(path)
        current
      end
    end

    def replace_track_evidence(reference_id, evidence, expected_record_digest:)
      with_record_lock(reference_id) do
        current = read(reference_id)
        actual = Digest::SHA256.hexdigest(JSON.generate(current))
        raise StaleStateError, "music reference state changed; preview reanalysis again" unless actual == expected_record_digest
        updated = deep_copy(current)
        updated["evidence"] = stringify_keys(evidence)
        updated["updated_at"] = @clock.call.iso8601
        validate_track!(updated, reference_id.to_s)
        replace_record(reference_id, updated)
      end
    end

    private

    def prepare_root!
      assert_safe_components!(@directory)
      FileUtils.mkdir_p(@directory, mode: 0o700)
      %w[tracks fusions locks].each do |name|
        path = File.join(@directory, name)
        assert_safe_components!(path)
        FileUtils.mkdir_p(path, mode: 0o700)
        File.chmod(0o700, path)
      end
      File.chmod(0o700, @directory)
    end

    def read_collection(kind, pattern, schema)
      path = File.join(@directory, kind)
      entries = Dir.children(path)
      raise IntegrityError, "music reference limit exceeded" if entries.length > MAX_RECORDS
      entries.map do |name|
        raise IntegrityError, "invalid music reference entry" unless name.end_with?(".json") && File.basename(name, ".json").match?(pattern)
        id = File.basename(name, ".json")
        read_record(File.join(path, name), id, schema)
      end
    end

    def read_record(path, id, schema)
      stat = File.lstat(path)
      raise IntegrityError, "music reference record must be a regular file" unless stat.file? && !stat.symlink?
      raise IntegrityError, "music reference record exceeds size limit" unless stat.size.between?(1, MAX_RECORD_BYTES)
      value = JSON.parse(File.binread(path, MAX_RECORD_BYTES))
      value["synthesis"] = normalize_synthesis(value["synthesis"]) if value.is_a?(Hash) && value["synthesis"].is_a?(Hash)
      begin
        schema == TRACK_SCHEMA ? validate_track!(value, id) : validate_fusion!(value, id)
      rescue ValidationError, ArgumentError => error
        raise IntegrityError, "invalid music reference record: #{error.message}"
      end
      value
    rescue Errno::ENOENT
      raise ValidationError, "music reference does not exist"
    rescue JSON::ParserError => error
      raise IntegrityError, "invalid music reference record: #{error.class}"
    end

    def validate_for_identity!(value, identifier)
      identifier.to_s.match?(REFERENCE_ID) ? validate_track!(value, identifier.to_s) : validate_fusion!(value, identifier.to_s)
    end

    def validate_track!(value, id)
      expected = %w[schema_version reference_id record_type status provenance evidence synthesis created_at updated_at]
      exact_object!(value, expected, "track")
      raise IntegrityError, "music track reference identity is invalid" unless value["schema_version"] == TRACK_SCHEMA && value["reference_id"] == id && id.match?(REFERENCE_ID) && value["record_type"] == "track"
      raise ValidationError, "music reference status is invalid" unless STATUSES.include?(value["status"])
      validate_provenance!(value["provenance"])
      validate_evidence!(value["evidence"])
      validate_synthesis!(value["synthesis"])
      timestamp!(value["created_at"]); timestamp!(value["updated_at"])
      true
    end

    def validate_evidence!(value)
      expected = %w[status bpm bpm_alternatives key key_alternatives meter sections instrumentation production_traits energy_curve vocal_traits lyrical_traits confidence_notes extractor_receipt]
      exact_object!(value, expected, "evidence")
      raise ValidationError, "music evidence status is invalid" unless %w[pending extracted reviewed].include?(value["status"])
      raise ValidationError, "music evidence BPM alternatives must be a bounded list" unless value["bpm_alternatives"].is_a?(Array) && value["bpm_alternatives"].length <= 20
      [value["bpm"], *value["bpm_alternatives"]].compact.each do |bpm|
        raise ValidationError, "observed BPM is invalid" unless bpm.is_a?(Numeric) && bpm.between?(20, 400)
      end
      text!(value["key"], "observed key", 80, allow_nil: true)
      text!(value["meter"], "observed meter", 40, allow_nil: true)
      %w[key_alternatives sections instrumentation production_traits energy_curve vocal_traits lyrical_traits confidence_notes].each do |field|
        list = value[field]
        raise ValidationError, "music evidence #{field} must be a bounded list" unless list.is_a?(Array) && list.length <= 100
        list.each { |item| text!(item, "evidence #{field}", 500) }
      end
      bounded_json_object!(value["extractor_receipt"], "extractor receipt")
      bounded_json_object!(value, "evidence")
    end

    def default_evidence
      {
        "status" => "pending", "bpm" => nil, "bpm_alternatives" => [], "key" => nil,
        "key_alternatives" => [], "meter" => nil, "sections" => [], "instrumentation" => [],
        "production_traits" => [], "energy_curve" => [], "vocal_traits" => [], "lyrical_traits" => [],
        "confidence_notes" => [], "extractor_receipt" => {}
      }
    end

    def validate_provenance!(value)
      expected = %w[canonical_url platform source_id title artists album duration_seconds rights_assertion captured_at musicbrainz tools]
      exact_object!(value, expected, "provenance")
      url = value["canonical_url"].to_s
      raise ValidationError, "music reference URL must be canonical HTTPS" unless url.match?(%r{\Ahttps://(?:(?:www\.|music\.)?youtube\.com/watch\?v=|youtu\.be/)[A-Za-z0-9_-]{6,20}\z})
      text!(value["platform"], "platform", 40); text!(value["source_id"], "source_id", 80); text!(value["title"], "title", 300)
      artists = value["artists"]
      raise ValidationError, "music reference artists must contain 1..20 names" unless artists.is_a?(Array) && artists.length.between?(1, 20)
      artists.each { |artist| text!(artist, "artist", 200) }
      text!(value["album"], "album", 300, allow_nil: true)
      duration = Integer(value["duration_seconds"])
      raise ValidationError, "music reference duration must be 1..900 seconds" unless (1..900).cover?(duration)
      raise ValidationError, "music reference rights assertion is invalid" unless RIGHTS.include?(value["rights_assertion"])
      timestamp!(value["captured_at"])
      bounded_json_object!(value["musicbrainz"], "musicbrainz")
      bounded_json_object!(value["tools"], "tools")
    rescue ArgumentError, TypeError
      raise ValidationError, "music reference duration must be an integer"
    end

    def validate_synthesis!(value)
      exact_object!(value, %w[status selected_revision_id rejected_revision_ids revisions], "synthesis")
      raise ValidationError, "music synthesis status is invalid" unless %w[pending candidate approved rejected].include?(value["status"])
      selected = value["selected_revision_id"]
      raise ValidationError, "selected synthesis revision is invalid" unless selected.nil? || selected.to_s.match?(/\Asyn_[a-f0-9]{16}\z/)
      revisions = value["revisions"]
      raise ValidationError, "music synthesis revisions must be a bounded list" unless revisions.is_a?(Array) && revisions.length <= 100
      revisions.each { |revision| validate_synthesis_revision!(revision) }
      rejected = value["rejected_revision_ids"]
      raise ValidationError, "rejected synthesis revisions must be a unique bounded list" unless rejected.is_a?(Array) && rejected.uniq.length == rejected.length && rejected.length <= 100
      raise ValidationError, "rejected synthesis revision is invalid" unless rejected.all? { |revision_id| revision_id.to_s.match?(/\Asyn_[a-f0-9]{16}\z/) && revisions.any? { |revision| revision["revision_id"] == revision_id } }
      raise ValidationError, "selected synthesis revision cannot be rejected" if selected && rejected.include?(selected)
      raise ValidationError, "selected synthesis revision does not exist" if selected && revisions.none? { |revision| revision.is_a?(Hash) && revision["revision_id"] == selected }
      bounded_json_object!(value, "synthesis")
    end

    def validate_synthesis_revision!(value)
      expected = %w[revision_id scope intent title caption lyrics bpm keyscale timesignature exclusions rationale created_at provider_receipt]
      exact_object!(value, expected, "synthesis revision")
      raise ValidationError, "music synthesis revision ID is invalid" unless value["revision_id"].to_s.match?(/\Asyn_[a-f0-9]{16}\z/)
      raise ValidationError, "music synthesis revision scope is invalid" unless %w[all intent title caption lyrics bpm keyscale timesignature].include?(value["scope"])
      %w[intent title caption lyrics keyscale timesignature rationale].each { |field| text!(value[field], "synthesis #{field}", field == "lyrics" ? 20_000 : MAX_TEXT, allow_nil: true) }
      raise ValidationError, "music synthesis BPM is invalid" unless value["bpm"].nil? || (value["bpm"].is_a?(Numeric) && value["bpm"].between?(30, 300))
      exclusions = value["exclusions"]
      raise ValidationError, "music synthesis exclusions must be a bounded list" unless exclusions.is_a?(Array) && exclusions.length <= 50
      exclusions.each { |item| text!(item, "synthesis exclusion", 500) }
      timestamp!(value["created_at"])
      bounded_json_object!(value["provider_receipt"], "provider receipt")
    end

    def validate_fusion!(value, id)
      expected = %w[schema_version fusion_id record_type status title source_reference_ids roles synthesis created_at updated_at]
      exact_object!(value, expected, "fusion")
      raise IntegrityError, "music fusion identity is invalid" unless value["schema_version"] == FUSION_SCHEMA && value["fusion_id"] == id && id.match?(FUSION_ID) && value["record_type"] == "fusion"
      raise ValidationError, "music fusion status is invalid" unless STATUSES.include?(value["status"])
      text!(value["title"], "fusion title", 300)
      sources = value["source_reference_ids"]
      raise ValidationError, "music fusion requires 2..5 unique references" unless sources.is_a?(Array) && sources.uniq.length == sources.length && sources.length.between?(2, 5) && sources.all? { |source| source.to_s.match?(REFERENCE_ID) }
      roles = value["roles"]
      raise ValidationError, "music fusion roles must match its sources" unless roles.is_a?(Array) && roles.length == sources.length && roles.all? { |role| role.is_a?(Hash) && role.keys.sort == %w[reference_id role weight].sort && sources.include?(role["reference_id"]) && role["weight"].is_a?(Numeric) && role["weight"].between?(0, 1) }
      roles.each { |role| text!(role["role"], "fusion role", 500) }
      validate_synthesis!(value["synthesis"])
      timestamp!(value["created_at"]); timestamp!(value["updated_at"])
      true
    end

    def write_new(kind, id, value)
      path = File.join(@directory, kind, "#{id}.json")
      raise IntegrityError, "music reference already exists" if File.exist?(path) || File.symlink?(path)
      body = JSON.pretty_generate(value) + "\n"
      raise IntegrityError, "music reference record exceeds size limit" if body.bytesize > MAX_RECORD_BYTES
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(body); file.flush; file.fsync }
      value
    end

    def replace_record(identifier, value)
      kind = identifier.to_s.match?(REFERENCE_ID) ? "tracks" : "fusions"
      path = File.join(@directory, kind, "#{identifier}.json")
      stat = File.lstat(path)
      raise IntegrityError, "music reference record must remain a regular file" unless stat.file? && !stat.symlink?
      body = JSON.pretty_generate(value) + "\n"
      raise IntegrityError, "music reference record exceeds size limit" if body.bytesize > MAX_RECORD_BYTES
      temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(body); file.flush; file.fsync }
      File.rename(temporary, path)
      value
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def with_record_lock(identifier)
      id = identifier.to_s
      raise ValidationError, "music reference ID is invalid" unless id.match?(REFERENCE_ID) || id.match?(FUSION_ID)
      prepare_root!
      path = File.join(@directory, "locks", "#{id}.lock")
      if File.exist?(path) || File.symlink?(path)
        stat = File.lstat(path)
        raise IntegrityError, "music reference lock must be a regular file" unless stat.file? && !stat.symlink?
      end
      flags = File::RDWR | File::CREAT
      flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
      File.open(path, flags, 0o600) do |lock|
        raise IntegrityError, "music reference lock must be a regular file" unless lock.stat.file?
        lock.flock(File::LOCK_EX)
        yield
      ensure
        lock.flock(File::LOCK_UN) if lock
      end
    rescue Errno::ELOOP
      raise IntegrityError, "music reference lock must not be a symlink"
    end

    def artist_hierarchy(tracks)
      artists = {}
      tracks.each do |track|
        provenance = track.fetch("provenance")
        album = provenance["album"] || "Unresolved release"
        provenance.fetch("artists").each do |name|
          artist = (artists[name] ||= { "name" => name, "albums" => {} })
          grouping = (artist["albums"][album] ||= { "title" => album, "resolved" => !provenance["album"].nil?, "tracks" => [] })
          grouping["tracks"] << track
        end
      end
      artists.values.sort_by { |artist| artist.fetch("name").downcase }.map do |artist|
        artist.merge("albums" => artist.fetch("albums").values.sort_by { |album| album.fetch("title").downcase })
      end
    end

    def exact_object!(value, keys, label)
      raise ValidationError, "music #{label} must be an object with exact fields" unless value.is_a?(Hash) && value.keys.sort == keys.sort
    end

    def bounded_json_object!(value, label)
      raise ValidationError, "music #{label} must be an object" unless value.is_a?(Hash)
      body = JSON.generate(value)
      raise ValidationError, "music #{label} exceeds size limit" if body.bytesize > MAX_TEXT * 8
    end

    def text!(value, label, limit, allow_nil: false)
      return if allow_nil && value.nil?
      raise ValidationError, "music #{label} must be a non-empty UTF-8 string" unless value.is_a?(String) && value.valid_encoding? && !value.strip.empty?
      raise ValidationError, "music #{label} exceeds #{limit} characters" if value.length > limit
    end

    def timestamp!(value)
      Time.iso8601(value.to_s)
    rescue ArgumentError
      raise ValidationError, "music timestamp is invalid"
    end

    def assert_safe_components!(path)
      relative = path.delete_prefix(@root).sub(%r{\A/}, "")
      current = @root
      relative.split(File::SEPARATOR).each do |part|
        current = File.join(current, part)
        next unless File.exist?(current) || File.symlink?(current)
        stat = File.lstat(current)
        raise IntegrityError, "music reference path contains a symlink" if stat.symlink?
        raise IntegrityError, "music reference path component is not a directory" unless stat.directory?
      end
    end

    def stringify_keys(value)
      raise ValidationError, "music reference input must be an object" unless value.is_a?(Hash)
      value.to_h { |key, item| [key.to_s, item] }
    end

    def deep_copy(value) = JSON.parse(JSON.generate(value))

    def normalize_synthesis(value)
      normalized = deep_copy(value)
      normalized["rejected_revision_ids"] ||= []
      normalized
    end

    def within?(path, parent)
      expanded = File.expand_path(path); base = File.expand_path(parent)
      expanded == base || expanded.start_with?(base + File::SEPARATOR)
    end
  end
end
