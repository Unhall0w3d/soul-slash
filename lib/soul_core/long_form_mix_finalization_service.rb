# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "long_form_mix_render_service"
require_relative "long_form_mix_service"

module SoulCore
  class LongFormMixFinalizationService
    REVIEW_SCHEMA = "soul.music.long_form_mix_review.v1"
    EXPORT_SCHEMA = "soul.music.accepted_mix_export.v1"
    PREVIEW_SCHEMA = "soul.music.accepted_mix_export_scope.v1"
    CONFIRMATION = "EXPORT_ACCEPTED_MIX"
    DISPOSITIONS = %w[keep revise reject].freeze
    ASSESSMENTS = %w[passed partial failed].freeze
    REVIEW_ID = /\Amixreview_[a-f0-9]{16}\z/
    MAX_NOTES_CHARS = 8_000
    MAX_REVIEW_HISTORY = 20
    MAX_JSON_BYTES = 256 * 1024
    MAX_MANIFEST_BYTES = 512 * 1024
    FINAL_FILES = %w[master.flac listening.mp3 mix.json mix-info.md checksums.sha256].freeze

    class ValidationError < StandardError; end
    class IntegrityError < StandardError; end

    def initialize(
      root: Dir.pwd,
      mix_service: nil,
      render_service: nil,
      reviews_root: nil,
      export_root: File.join(Dir.home, "Music", "soul-music"),
      export_parent: File.join(Dir.home, "Music"),
      final_root: nil,
      clock: -> { Time.now.utc }
    )
      @root = File.expand_path(root)
      @mix_service = mix_service || LongFormMixService.new(root: @root, clock: clock)
      @render_service = render_service || LongFormMixRenderService.new(root: @root, mix_service: @mix_service, clock: clock)
      @reviews_root = File.expand_path(reviews_root || File.join(@root, "Soul", "private", "mix_reviews"))
      @export_root = File.expand_path(export_root)
      @export_parent = File.expand_path(export_parent)
      @final_root = File.expand_path(final_root || File.join(@export_root, "mixes", "finished"))
      @clock = clock

      raise IntegrityError, "private mix review root must remain inside repository" unless within?(@reviews_root, @root)
      raise IntegrityError, "music export root must remain inside configured music root" unless within?(@export_root, @export_parent)
      raise IntegrityError, "accepted mix root must remain inside music export root" unless within?(@final_root, @export_root)
      prepare_root!(@reviews_root)
      assert_no_symlink_path!(@final_root)
    end

    def status(mix_id:)
      mix = resolve_mix(mix_id)
      render = resolve_render(mix.fetch("mix_id"))
      review_record = read_review(mix.fetch("mix_id"))
      latest = review_record && review_record.fetch("latest")
      export = latest && latest.fetch("disposition") == "keep" ? existing_export(export_scope(mix, render, review_record)) : nil
      outcome(
        "complete",
        true,
        "mix finalization status loaded",
        data: {
          "mix_id" => mix.fetch("mix_id"),
          "review" => latest,
          "review_history_count" => review_record ? review_record.fetch("history").length : 0,
          "accepted_export" => export
        }
      )
    rescue ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def record_review(mix_id:, review:)
      mix = resolve_mix(mix_id)
      render = resolve_render(mix.fetch("mix_id"))
      normalized = normalize_review(review)
      path = review_path(mix.fetch("mix_id"))
      prior = read_review(mix.fetch("mix_id"))
      history = prior ? prior.fetch("history").dup : []
      history << prior.fetch("latest") if prior
      history = history.last(MAX_REVIEW_HISTORY)
      revision = prior ? prior.fetch("revision") + 1 : 1
      now = @clock.call.iso8601
      evidence = {
        "mix_id" => mix.fetch("mix_id"),
        "mix_title" => mix.fetch("title"),
        "render_scope_digest" => render.fetch("scope_digest"),
        "render_checksums" => required_render_checksums(render),
        "revision" => revision,
        "reviewed_at" => now,
        "review" => normalized
      }
      latest = normalized.merge(
        "review_id" => "mixreview_#{digest(evidence)[0, 16]}",
        "revision" => revision,
        "reviewed_at" => now,
        "render_scope_digest" => render.fetch("scope_digest"),
        "render_checksums" => required_render_checksums(render)
      )
      record = {
        "schema_version" => REVIEW_SCHEMA,
        "mix_id" => mix.fetch("mix_id"),
        "title" => mix.fetch("title"),
        "revision" => revision,
        "latest" => latest,
        "history" => history,
        "updated_at" => now
      }
      write_json_atomic(path, record)
      outcome(
        "complete",
        true,
        "mix listening review recorded",
        data: { "review" => latest, "review_history_count" => history.length },
        mutation: "long_form_mix_review_recorded"
      )
    rescue ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def export_preview(mix_id:)
      mix, render, review_record, scope = accepted_scope(mix_id)
      existing = existing_export(scope)
      return outcome("complete", true, "this exact accepted mix export already exists", data: { "accepted_export" => existing, "idempotent_replay" => true }) if existing

      destination = scope.fetch("destination")
      return outcome("blocked_for_human_review", false, "accepted mix destination already exists; Soul will not overwrite it") if File.exist?(destination) || File.symlink?(destination)

      outcome(
        "blocked_for_human_review",
        true,
        "exact accepted mix export confirmation required",
        data: {
          "confirmation_phrase" => CONFIRMATION,
          "expected_digest" => digest(scope),
          "preview_scope" => scope,
          "review" => review_record.fetch("latest"),
          "render" => render,
          "mix" => mix
        }
      )
    rescue ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def export_execute(mix_id:, confirmation:, expected_digest:)
      return outcome("awaiting_input", false, "confirmation and expected_digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?

      mix, render, review_record, scope = accepted_scope(mix_id)
      return outcome("blocked_for_human_review", false, "exact accepted mix confirmation did not match") unless confirmation == CONFIRMATION
      return outcome("blocked_for_human_review", false, "accepted mix scope changed; preview again") unless secure_compare(expected_digest.to_s, digest(scope))

      existing = existing_export(scope)
      return outcome("complete", true, "this exact accepted mix export already exists", data: { "accepted_export" => existing, "idempotent_replay" => true }) if existing

      destination = scope.fetch("destination")
      raise IntegrityError, "accepted mix destination already exists" if File.exist?(destination) || File.symlink?(destination)
      prepare_root!(@final_root)
      staging = File.join(@final_root, ".#{File.basename(destination)}.partial-#{SecureRandom.hex(6)}")
      FileUtils.mkdir_p(staging, mode: 0o700)
      begin
        copy_verified(scope.fetch("source_flac"), scope.fetch("render_checksums").fetch("master.flac"), File.join(staging, "master.flac"))
        copy_verified(scope.fetch("source_mp3"), scope.fetch("render_checksums").fetch("listening.mp3"), File.join(staging, "listening.mp3"))
        metadata = {
          "schema_version" => EXPORT_SCHEMA,
          "mix_id" => mix.fetch("mix_id"),
          "title" => mix.fetch("title"),
          "intent" => mix.fetch("intent"),
          "duration_seconds" => mix.fetch("total_duration_seconds"),
          "sequence" => mix.fetch("sequence"),
          "timeline_seconds" => mix.fetch("timeline_seconds"),
          "review" => review_record.fetch("latest"),
          "render_scope_digest" => render.fetch("scope_digest"),
          "render_checksums" => scope.fetch("render_checksums"),
          "scope_digest" => digest(scope),
          "exported_at" => @clock.call.iso8601
        }
        write_json(File.join(staging, "mix.json"), metadata)
        File.write(File.join(staging, "mix-info.md"), summary_markdown(metadata), mode: "wx", perm: 0o600)
        checksums = (FINAL_FILES - ["checksums.sha256"]).to_h do |name|
          [name, Digest::SHA256.file(File.join(staging, name)).hexdigest]
        end
        write_checksum_manifest(File.join(staging, "checksums.sha256"), checksums)
        File.rename(staging, destination)
        exported = existing_export(scope)
        outcome("complete", true, "accepted mix audio export prepared", data: { "accepted_export" => exported }, mutation: "accepted_mix_export_prepared")
      ensure
        FileUtils.rm_rf(staging) if staging && File.directory?(staging) && !File.symlink?(staging)
      end
    rescue ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    private

    def accepted_scope(mix_id)
      mix = resolve_mix(mix_id)
      render = resolve_render(mix.fetch("mix_id"))
      review_record = read_review(mix.fetch("mix_id"))
      raise ValidationError, "listen to the candidate and record a mix review before export" unless review_record
      latest = review_record.fetch("latest")
      raise ValidationError, "accepted mix export requires the latest review disposition to be keep" unless latest.fetch("disposition") == "keep"
      verify_review_render!(latest, render)
      [mix, render, review_record, export_scope(mix, render, review_record)]
    end

    def export_scope(mix, render, review_record)
      latest = review_record.fetch("latest")
      review_id = latest.fetch("review_id")
      destination = File.join(@final_root, "#{slugify(mix.fetch("title"))}-#{mix.fetch("mix_id")}-#{review_id}")
      raise IntegrityError, "accepted mix destination escaped configured root" unless within?(destination, @final_root)
      {
        "schema_version" => PREVIEW_SCHEMA,
        "operation" => "export_accepted_mix_audio",
        "mix_id" => mix.fetch("mix_id"),
        "title" => mix.fetch("title"),
        "intent" => mix.fetch("intent"),
        "duration_seconds" => mix.fetch("total_duration_seconds"),
        "mix_plan_digest" => digest(mix.reject { |key, _| %w[created_at updated_at].include?(key) }),
        "review_id" => review_id,
        "review_revision" => latest.fetch("revision"),
        "review_digest" => digest(latest),
        "render_scope_digest" => render.fetch("scope_digest"),
        "render_checksums" => required_render_checksums(render),
        "source_flac" => @render_service.artifact_path(mix_id: mix.fetch("mix_id"), artifact: "flac"),
        "source_mp3" => @render_service.artifact_path(mix_id: mix.fetch("mix_id"), artifact: "mp3"),
        "destination" => destination,
        "expected_outputs" => FINAL_FILES,
        "automatic_publication" => false,
        "audio_processing" => "none; checksum-verified copy of accepted A1 listening render"
      }
    end

    def resolve_mix(mix_id)
      result = @mix_service.get(mix_id: mix_id)
      raise IntegrityError, result.fetch("reason") if result.fetch("lifecycle_state") == "blocked_for_human_review"
      raise ValidationError, result.fetch("reason") unless result.fetch("lifecycle_state") == "complete"
      result.fetch("data").fetch("mix")
    rescue ValidationError, IntegrityError
      raise
    rescue StandardError => error
      raise IntegrityError, "could not load mix plan: #{error.class}"
    end

    def resolve_render(mix_id)
      result = @render_service.status(mix_id: mix_id)
      raise IntegrityError, result.fetch("reason") if result.fetch("lifecycle_state") == "blocked_for_human_review"
      raise ValidationError, result.fetch("reason") unless result.fetch("lifecycle_state") == "complete"
      render = result.fetch("data").fetch("render", nil)
      raise ValidationError, "render the exact listening candidate before recording a review" unless render
      required_render_checksums(render)
      render
    end

    def normalize_review(review)
      value = review.to_h.transform_keys(&:to_s)
      required = %w[sequence_cohesion transition_quality rating disposition notes]
      raise ValidationError, "mix review is incomplete" unless required.all? { |key| value.key?(key) }
      sequence = value.fetch("sequence_cohesion").to_s
      transition = value.fetch("transition_quality").to_s
      disposition = value.fetch("disposition").to_s
      raise ValidationError, "sequence cohesion is invalid" unless ASSESSMENTS.include?(sequence)
      raise ValidationError, "transition quality is invalid" unless ASSESSMENTS.include?(transition)
      raise ValidationError, "mix disposition is invalid" unless DISPOSITIONS.include?(disposition)
      rating = Integer(value.fetch("rating"))
      raise ValidationError, "mix rating must be between 1 and 5" unless rating.between?(1, 5)
      notes = value.fetch("notes").to_s.strip
      raise ValidationError, "mix review notes exceed #{MAX_NOTES_CHARS} characters" if notes.length > MAX_NOTES_CHARS
      { "sequence_cohesion" => sequence, "transition_quality" => transition, "rating" => rating, "disposition" => disposition, "notes" => notes }
    rescue ArgumentError, TypeError
      raise ValidationError, "mix rating must be between 1 and 5"
    end

    def required_render_checksums(render)
      checksums = render.fetch("checksums").to_h
      %w[master.flac listening.mp3].to_h do |name|
        value = checksums.fetch(name, "").to_s
        raise IntegrityError, "listening render checksum is missing: #{name}" unless value.match?(/\A[a-f0-9]{64}\z/)
        [name, value]
      end
    end

    def verify_review_render!(review, render)
      raise IntegrityError, "reviewed listening render scope changed" unless secure_compare(review.fetch("render_scope_digest"), render.fetch("scope_digest"))
      raise IntegrityError, "reviewed listening render checksums changed" unless review.fetch("render_checksums") == required_render_checksums(render)
    end

    def review_path(mix_id)
      raise ValidationError, "mix_id is invalid" unless mix_id.to_s.match?(LongFormMixService::MIX_ID)
      File.join(@reviews_root, "#{mix_id}.json")
    end

    def read_review(mix_id)
      path = review_path(mix_id)
      return nil unless File.exist?(path)
      record = parse_json(path)
      raise IntegrityError, "mix review schema is invalid" unless record.fetch("schema_version") == REVIEW_SCHEMA
      raise IntegrityError, "mix review identity changed" unless record.fetch("mix_id") == mix_id
      raise IntegrityError, "mix review record is incomplete" unless record.fetch("latest").is_a?(Hash) && record.fetch("history").is_a?(Array)
      raise IntegrityError, "mix review revision is invalid" unless record.fetch("revision").is_a?(Integer) && record.fetch("revision").positive?
      raise IntegrityError, "mix review history exceeds bound" if record.fetch("history").length > MAX_REVIEW_HISTORY
      validate_stored_review!(record.fetch("latest"))
      record.fetch("history").each { |review| validate_stored_review!(review) }
      record
    end

    def validate_stored_review!(review)
      raise IntegrityError, "stored mix review is invalid" unless review.is_a?(Hash)
      normalized = normalize_review(review.slice("sequence_cohesion", "transition_quality", "rating", "disposition", "notes"))
      raise IntegrityError, "stored mix review fields changed" unless normalized.all? { |key, value| review[key] == value }
      raise IntegrityError, "stored mix review ID is invalid" unless review.fetch("review_id", "").to_s.match?(REVIEW_ID)
      raise IntegrityError, "stored mix review revision is invalid" unless review.fetch("revision", nil).is_a?(Integer) && review.fetch("revision").positive?
      raise IntegrityError, "stored mix review timestamp is missing" if review.fetch("reviewed_at", "").to_s.empty?
      raise IntegrityError, "stored mix review render scope is invalid" unless review.fetch("render_scope_digest", "").to_s.match?(/\A[a-f0-9]{64}\z/)
      required_render_checksums({ "checksums" => review.fetch("render_checksums", {}) })
      true
    rescue ValidationError, KeyError
      raise IntegrityError, "stored mix review is invalid"
    end

    def existing_export(scope)
      destination = scope.fetch("destination")
      return nil unless File.directory?(destination) && !File.symlink?(destination)
      raise IntegrityError, "accepted mix destination is unsafe" if path_has_symlink?(destination)
      FINAL_FILES.each do |name|
        path = File.join(destination, name)
        raise IntegrityError, "accepted mix artifact is missing: #{name}" unless File.file?(path) && !File.symlink?(path)
      end
      manifest = parse_checksum_manifest(File.join(destination, "checksums.sha256"))
      raise IntegrityError, "accepted mix checksum inventory changed" unless manifest.keys.sort == (FINAL_FILES - ["checksums.sha256"]).sort
      manifest.each do |name, expected|
        actual = Digest::SHA256.file(File.join(destination, name)).hexdigest
        raise IntegrityError, "accepted mix checksum mismatch: #{name}" unless secure_compare(actual, expected)
      end
      metadata = parse_json(File.join(destination, "mix.json"))
      raise IntegrityError, "accepted mix export schema is invalid" unless metadata.fetch("schema_version") == EXPORT_SCHEMA
      raise IntegrityError, "accepted mix export scope changed" unless secure_compare(metadata.fetch("scope_digest"), digest(scope))
      { "destination" => destination, "files" => FINAL_FILES, "checksums" => manifest, "metadata" => metadata }
    end

    def copy_verified(source, expected, destination)
      raise IntegrityError, "accepted mix source is missing" unless File.file?(source) && !File.symlink?(source)
      raise IntegrityError, "accepted mix source digest changed" unless secure_compare(Digest::SHA256.file(source).hexdigest, expected)
      FileUtils.copy_file(source, destination)
      File.chmod(0o600, destination)
      raise IntegrityError, "accepted mix copy digest changed" unless secure_compare(Digest::SHA256.file(destination).hexdigest, expected)
    end

    def summary_markdown(metadata)
      review = metadata.fetch("review")
      <<~MARKDOWN
        # #{metadata.fetch("title")}

        #{metadata.fetch("intent")}

        - Mix ID: `#{metadata.fetch("mix_id")}`
        - Duration: #{metadata.fetch("duration_seconds")} seconds
        - Review: #{review.fetch("disposition")} (#{review.fetch("rating")}/5)
        - Sequence cohesion: #{review.fetch("sequence_cohesion")}
        - Transition quality: #{review.fetch("transition_quality")}

        ## Operator notes

        #{review.fetch("notes").empty? ? "No additional notes recorded." : review.fetch("notes")}

        This package is the checksum-verified audio accepted from Mix Studio. It
        is not a mastered release, a visual program, or evidence of publication.
      MARKDOWN
    end

    def write_json_atomic(path, payload)
      body = JSON.pretty_generate(payload) + "\n"
      raise IntegrityError, "mix review record exceeds maximum size" if body.bytesize > MAX_JSON_BYTES
      temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.write(temporary, body, mode: "wx", perm: 0o600)
      File.rename(temporary, path)
    ensure
      File.unlink(temporary) if defined?(temporary) && temporary && File.file?(temporary)
    end

    def write_json(path, payload)
      body = JSON.pretty_generate(payload) + "\n"
      raise IntegrityError, "accepted mix record exceeds maximum size" if body.bytesize > MAX_JSON_BYTES
      File.write(path, body, mode: "wx", perm: 0o600)
    end

    def parse_json(path)
      raise IntegrityError, "record is invalid or unsafe" unless File.file?(path) && !File.symlink?(path)
      body = File.binread(path, MAX_JSON_BYTES + 1)
      raise IntegrityError, "record is too large" if body.bytesize > MAX_JSON_BYTES
      JSON.parse(body)
    rescue JSON::ParserError => error
      raise IntegrityError, "record JSON is invalid: #{error.class}"
    end

    def parse_checksum_manifest(path)
      raise IntegrityError, "checksum manifest is missing or unsafe" unless File.file?(path) && !File.symlink?(path)
      body = File.binread(path, MAX_MANIFEST_BYTES + 1)
      raise IntegrityError, "checksum manifest is too large" if body.bytesize > MAX_MANIFEST_BYTES
      body.each_line.each_with_object({}) do |line, result|
        next if line.strip.empty?
        value, name = line.strip.split(/\s+/, 2)
        name = name.to_s.sub(/^  /, "")
        raise IntegrityError, "checksum manifest is malformed" unless value&.match?(/\A[a-f0-9]{64}\z/) && name.match?(/\A[a-zA-Z0-9._-]+\z/)
        result[name] = value
      end
    end

    def write_checksum_manifest(path, checksums)
      lines = checksums.sort.to_h.map { |name, value| "#{value}  #{name}" }
      File.write(path, "#{lines.join("\n")}\n", mode: "wx", perm: 0o600)
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

    def path_has_symlink?(path)
      cursor = "/"
      File.expand_path(path).split(File::SEPARATOR).each do |part|
        next if part.empty?
        cursor = File.join(cursor, part)
        return true if File.exist?(cursor) && File.symlink?(cursor)
      end
      false
    end

    def within?(path, parent)
      candidate = File.expand_path(path)
      base = File.expand_path(parent)
      candidate == base || candidate.start_with?("#{base}#{File::SEPARATOR}")
    end

    def slugify(value)
      slug = value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      slug.empty? ? "accepted-mix" : slug[0, 80]
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
