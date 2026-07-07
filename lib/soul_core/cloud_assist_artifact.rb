# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module SoulCore
  # CloudAssistArtifact provides a small, boring, review-only landing zone for
  # cloud-assisted outputs. Cloud models should draft artifacts, not mutate repo
  # code or approve their own work. Yes, apparently this needs a class.
  class CloudAssistArtifact
    DEFAULT_ARTIFACT_ROOT = "Soul/artifacts/cloud_assist"
    DEFAULT_SKILL_PROPOSAL_ROOT = "Soul/proposals/skills"

    SAFE_SLUG_PATTERN = /[^a-zA-Z0-9._-]+/

    attr_reader :root, :kind, :purpose, :slug, :created_at, :path

    def initialize(kind:, purpose:, slug: nil, root: nil, created_at: Time.now.utc)
      @kind = kind.to_s
      @purpose = purpose.to_s
      @created_at = created_at
      @slug = safe_slug(slug || purpose)
      @root = root || root_for_kind(@kind)
      @path = build_path
    end

    def self.create(kind:, purpose:, slug: nil, root: nil, metadata: {}, files: {})
      artifact = new(kind: kind, purpose: purpose, slug: slug, root: root)
      artifact.write(metadata: metadata, files: files)
      artifact
    end

    def write(metadata: {}, files: {})
      FileUtils.mkdir_p(path)

      full_metadata = default_metadata.merge(stringify_keys(metadata))
      write_json("metadata.json", full_metadata)

      files.each do |relative_path, content|
        write_file(relative_path, content)
      end

      self
    end

    def relative_path
      path
    end

    def to_h
      {
        "kind" => kind,
        "purpose" => purpose,
        "slug" => slug,
        "path" => path,
        "created_at" => created_at.iso8601
      }
    end

    def write_json(relative_path, object)
      write_file(relative_path, JSON.pretty_generate(object) + "\n")
    end

    def write_file(relative_path, content)
      clean = clean_relative_path(relative_path)
      full = File.join(path, clean)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content.to_s)
      full
    end

    private

    def root_for_kind(kind)
      case kind
      when "skill_proposal"
        DEFAULT_SKILL_PROPOSAL_ROOT
      else
        DEFAULT_ARTIFACT_ROOT
      end
    end

    def build_path
      stamp = created_at.strftime("%Y%m%dT%H%M%SZ")
      File.join(root, "#{stamp}-#{slug}")
    end

    def safe_slug(value)
      value.to_s.strip.downcase.gsub(SAFE_SLUG_PATTERN, "-").gsub(/\A-+|-+\z/, "")[0, 80].then do |item|
        item.empty? ? "cloud-artifact" : item
      end
    end

    def clean_relative_path(relative_path)
      parts = relative_path.to_s.split(/[\\\/]+/).reject do |part|
        part.empty? || part == "." || part == ".."
      end
      raise ArgumentError, "relative_path must not be empty" if parts.empty?

      parts.join("/")
    end

    def default_metadata
      {
        "artifact_type" => kind,
        "purpose" => purpose,
        "created_at" => created_at.iso8601,
        "output_mode" => "review_artifact_only",
        "direct_repo_mutation" => false,
        "human_review_required" => true
      }
    end

    def stringify_keys(hash)
      hash.each_with_object({}) do |(key, value), out|
        out[key.to_s] = value
      end
    end
  end
end
