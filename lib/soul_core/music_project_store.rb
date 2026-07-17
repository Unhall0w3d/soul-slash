# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"

module SoulCore
  class MusicProjectStore
    SCHEMA_VERSION = "soul.music.project.v1"
    PROJECT_ID = /\Amusic_[a-f0-9]{16}\z/
    CANDIDATE_ID = /\Acandidate_[a-f0-9]{16}\z/
    DEFAULT_DIRECTORY = File.join("Soul", "music", "projects")
    MAX_PROJECTS = 1_000
    MAX_PROJECT_BYTES = 64 * 1024
    STRING_LIMITS = { "title" => 120, "intent" => 2_000, "caption" => 8_000, "lyrics" => 20_000, "keyscale" => 40 }.freeze
    REQUIRED_INPUTS = %w[title intent target_duration_seconds vocal_mode rights_status caption lyrics bpm keyscale timesignature language seed].freeze

    class ValidationError < StandardError; end
    class IntegrityError < StandardError; end

    def initialize(root: Dir.pwd, directory: DEFAULT_DIRECTORY, clock: -> { Time.now.utc }, id_generator: -> { SecureRandom.hex(8) })
      @root = File.expand_path(root)
      @directory = File.expand_path(directory, @root)
      @clock = clock
      @id_generator = id_generator
      raise ValidationError, "music project root must remain inside the repository root" unless within?(@directory, @root)
    end

    attr_reader :directory

    def create(attributes)
      data = stringify_keys(attributes)
      unknown = data.keys - REQUIRED_INPUTS
      missing = REQUIRED_INPUTS - data.keys
      raise ValidationError, "unknown project fields: #{unknown.join(', ')}" unless unknown.empty?
      raise ValidationError, "missing project fields: #{missing.join(', ')}" unless missing.empty?

      validate_inputs!(data)
      prepare_root!
      raise IntegrityError, "music project limit exceeded" if safe_entries(@directory).length >= MAX_PROJECTS

      project_id = "music_#{@id_generator.call}"
      raise IntegrityError, "generated project ID is invalid" unless project_id.match?(PROJECT_ID)
      project_dir = path_for(project_id)
      raise IntegrityError, "music project ID collision" if File.exist?(project_dir) || File.symlink?(project_dir)

      FileUtils.mkdir_p(project_dir, mode: 0o700)
      %w[inputs generations reviews exports].each { |name| Dir.mkdir(File.join(project_dir, name), 0o700) }
      now = @clock.call.iso8601
      project = {
        "schema_version" => SCHEMA_VERSION,
        "project_id" => project_id,
        "title" => data.fetch("title").strip,
        "intent" => data.fetch("intent").strip,
        "target_duration_seconds" => Integer(data.fetch("target_duration_seconds")),
        "vocal_mode" => data.fetch("vocal_mode"),
        "rights_status" => data.fetch("rights_status"),
        "caption" => data.fetch("caption").strip,
        "lyrics" => data.fetch("lyrics"),
        "bpm" => Integer(data.fetch("bpm")),
        "keyscale" => data.fetch("keyscale").strip,
        "timesignature" => data.fetch("timesignature").to_s,
        "language" => data.fetch("language"),
        "seed" => Integer(data.fetch("seed")),
        "created_at" => now,
        "updated_at" => now
      }
      atomic_json(File.join(project_dir, "project.json"), project)
      project
    rescue StandardError
      FileUtils.rm_rf(project_dir) if defined?(project_dir) && project_dir && within?(project_dir, @directory) && File.directory?(project_dir) && !File.symlink?(project_dir) && !File.exist?(File.join(project_dir, "project.json"))
      raise
    end

    def list(limit: 100)
      prepare_root!
      bounded_limit = [[Integer(limit), 1].max, 200].min
      safe_entries(@directory).filter_map do |name|
        next unless name.match?(PROJECT_ID)
        read(name)
      end.sort_by { |project| project.fetch("created_at") }.reverse.first(bounded_limit)
    end

    def read(project_id)
      id = validate_project_id!(project_id)
      project_dir = path_for(id)
      assert_regular_directory!(project_dir, "music project")
      %w[inputs generations reviews exports].each { |name| assert_regular_directory!(File.join(project_dir, name), "music project #{name}") }
      path = File.join(project_dir, "project.json")
      stat = File.lstat(path)
      raise IntegrityError, "music project record must be a regular file" unless stat.file? && !stat.symlink?
      raise IntegrityError, "music project record exceeds size limit" if stat.size > MAX_PROJECT_BYTES
      data = JSON.parse(File.binread(path, MAX_PROJECT_BYTES))
      validate_record!(data, id)
      data
    rescue Errno::ENOENT, JSON::ParserError => error
      raise IntegrityError, "invalid music project record: #{error.class}"
    end

    def project_path(project_id)
      path_for(validate_project_id!(project_id))
    end

    def generations_path(project_id)
      project = read(project_id)
      File.join(path_for(project.fetch("project_id")), "generations")
    end

    def input_payload(project)
      {
        "caption" => project.fetch("caption"),
        "lyrics" => project.fetch("vocal_mode") == "instrumental" ? "" : project.fetch("lyrics"),
        "bpm" => project.fetch("bpm"),
        "keyscale" => project.fetch("keyscale"),
        "timesignature" => project.fetch("timesignature"),
        "language" => project.fetch("language"),
        "duration" => project.fetch("target_duration_seconds"),
        "seed" => project.fetch("seed"),
        "batch_size" => 1,
        "inference_steps" => 8
      }
    end

    def input_digest(project)
      Digest::SHA256.hexdigest(JSON.generate(input_payload(project)))
    end

    def candidate_id
      id = "candidate_#{@id_generator.call}"
      raise IntegrityError, "generated candidate ID is invalid" unless id.match?(CANDIDATE_ID)
      id
    end

    def publish_candidate(project_id, candidate_id, staging_dir, receipt)
      validate_project_id!(project_id)
      raise ValidationError, "candidate_id is invalid" unless candidate_id.to_s.match?(CANDIDATE_ID)
      generations = generations_path(project_id)
      raise IntegrityError, "candidate staging directory is outside project generations" unless within?(staging_dir, generations)
      assert_regular_directory!(staging_dir, "candidate staging")
      target = File.join(generations, candidate_id)
      raise IntegrityError, "candidate output already exists" if File.exist?(target) || File.symlink?(target)
      atomic_json(File.join(staging_dir, "candidate.json"), receipt)
      File.rename(staging_dir, target)
      target
    end

    private

    def prepare_root!
      assert_safe_components!(@directory)
      FileUtils.mkdir_p(@directory, mode: 0o700)
      assert_safe_components!(@directory)
      File.chmod(0o700, @directory)
    end

    def validate_inputs!(data)
      STRING_LIMITS.each do |field, limit|
        value = data[field]
        raise ValidationError, "#{field} must be a UTF-8 string" unless value.is_a?(String) && value.valid_encoding?
        raise ValidationError, "#{field} exceeds #{limit} characters" if value.length > limit
      end
      %w[title intent caption].each { |field| raise ValidationError, "#{field} is required" if data.fetch(field).strip.empty? }
      raise ValidationError, "instrumental projects must not contain lyrics" if data["vocal_mode"] == "instrumental" && !data["lyrics"].empty?
      raise ValidationError, "vocal projects require lyrics" if data["vocal_mode"] == "vocal" && data["lyrics"].strip.empty?
      raise ValidationError, "vocal_mode is invalid" unless %w[vocal instrumental].include?(data["vocal_mode"])
      raise ValidationError, "rights_status is invalid" unless %w[original licensed public_domain].include?(data["rights_status"])
      duration = Integer(data["target_duration_seconds"])
      bpm = Integer(data["bpm"])
      seed = Integer(data["seed"])
      raise ValidationError, "target duration must be 10..180 seconds" unless (10..180).cover?(duration)
      raise ValidationError, "bpm must be 30..300" unless (30..300).cover?(bpm)
      raise ValidationError, "seed must be 0..2147483647" unless (0..2_147_483_647).cover?(seed)
      raise ValidationError, "timesignature is invalid" unless %w[2 3 4 5 6 7 9 12].include?(data["timesignature"].to_s)
      raise ValidationError, "language must be a two- or three-letter lowercase code" unless data["language"].to_s.match?(/\A[a-z]{2,3}\z/)
    rescue ArgumentError, TypeError
      raise ValidationError, "duration, bpm, and seed must be integers"
    end

    def validate_record!(data, id)
      raise IntegrityError, "music project record must be an object" unless data.is_a?(Hash)
      expected = %w[schema_version project_id title intent target_duration_seconds vocal_mode rights_status caption lyrics bpm keyscale timesignature language seed created_at updated_at]
      raise IntegrityError, "music project record fields are invalid" unless data.keys.sort == expected.sort
      raise IntegrityError, "music project schema is invalid" unless data["schema_version"] == SCHEMA_VERSION && data["project_id"] == id
      validate_inputs!(data.slice(*REQUIRED_INPUTS))
      Time.iso8601(data.fetch("created_at")); Time.iso8601(data.fetch("updated_at"))
    rescue ValidationError, ArgumentError, KeyError => error
      raise IntegrityError, "invalid music project record: #{error.message}"
    end

    def validate_project_id!(value)
      id = value.to_s
      raise ValidationError, "project_id is invalid" unless id.match?(PROJECT_ID)
      id
    end

    def path_for(id) = File.join(@directory, id)

    def assert_safe_components!(path)
      relative = path.delete_prefix(@root).sub(%r{\A/}, "")
      current = @root
      relative.split(File::SEPARATOR).each do |part|
        current = File.join(current, part)
        next unless File.exist?(current) || File.symlink?(current)
        stat = File.lstat(current)
        raise IntegrityError, "music storage path contains a symlink" if stat.symlink?
        raise IntegrityError, "music storage path component is not a directory" unless stat.directory?
      end
    end

    def assert_regular_directory!(path, label)
      stat = File.lstat(path)
      raise IntegrityError, "#{label} must be a regular directory" unless stat.directory? && !stat.symlink?
    end

    def safe_entries(path)
      entries = Dir.children(path)
      raise IntegrityError, "music project limit exceeded" if entries.length > MAX_PROJECTS
      entries.each { |name| raise IntegrityError, "invalid music project entry" unless name.match?(PROJECT_ID) }
      entries
    end

    def atomic_json(path, data)
      body = JSON.pretty_generate(data) + "\n"
      raise IntegrityError, "music JSON exceeds size limit" if body.bytesize > MAX_PROJECT_BYTES
      temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(body); file.flush; file.fsync
      end
      File.rename(temporary, path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def within?(path, parent)
      expanded = File.expand_path(path)
      base = File.expand_path(parent)
      expanded == base || expanded.start_with?(base + File::SEPARATOR)
    end

    def stringify_keys(hash)
      raise ValidationError, "project input must be an object" unless hash.is_a?(Hash)
      hash.to_h { |key, value| [key.to_s, value] }
    end
  end
end
