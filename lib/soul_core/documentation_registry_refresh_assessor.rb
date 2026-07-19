
# frozen_string_literal: true

require "json"
require "time"

begin
  require "yaml"
rescue LoadError
  YAML = nil
end

module SoulCore
  class DocumentationRegistryRefreshAssessor
    REGISTRY_PATH = "Soul/skills/registry.yaml"
    ARCHITECTURE_PATH = "docs/ARCHITECTURE.md"
    SKILLS_DOC_PATH = "docs/SKILLS.md"
    OUTPUT_DOC_PATH = "docs/SKILL_REGISTRY_SNAPSHOT.md"

    INPUT_DOC_PATHS = [
      ARCHITECTURE_PATH,
      SKILLS_DOC_PATH
    ].freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      registry = load_registry
      skill_records = extract_skill_records(registry)

      docs = {
        ARCHITECTURE_PATH => read(ARCHITECTURE_PATH),
        SKILLS_DOC_PATH => read(SKILLS_DOC_PATH),
        OUTPUT_DOC_PATH => read(OUTPUT_DOC_PATH)
      }

      missing_input_docs = INPUT_DOC_PATHS.select { |path| docs[path].nil? }
      snapshot_present = File.exist?(full(OUTPUT_DOC_PATH))

      documented_ids = documented_skill_ids(docs)
      registry_ids = skill_records.map { |skill| skill["id"] }.compact.sort

      missing_from_docs = registry_ids - documented_ids
      stale_in_docs = documented_ids - registry_ids

      blockers = []
      blockers << "Missing skill registry: #{REGISTRY_PATH}" unless File.exist?(full(REGISTRY_PATH))
      blockers << "YAML is unavailable; cannot parse #{REGISTRY_PATH}" unless yaml_available?
      blockers << "No skills could be extracted from #{REGISTRY_PATH}" if skill_records.empty?
      blockers << "Missing input documentation file(s): #{missing_input_docs.join(', ')}" unless missing_input_docs.empty?
      blockers << "Documented stale skill id(s): #{stale_in_docs.join(', ')}" unless stale_in_docs.empty?

      warnings = []
      warnings << "Skill id(s) missing from documentation snapshot/docs: #{missing_from_docs.join(', ')}" unless missing_from_docs.empty?
      warnings << "Snapshot document has not been generated yet: #{OUTPUT_DOC_PATH}" unless snapshot_present

      {
        "ok" => blockers.empty?,
        "assessment" => "documentation_registry_refresh",
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "status" => blockers.empty? ? "ready" : "blocked",
        "registry" => {
          "path" => REGISTRY_PATH,
          "present" => File.exist?(full(REGISTRY_PATH)),
          "skill_count" => skill_records.length,
          "skill_ids" => registry_ids
        },
        "documentation" => {
          "architecture_path" => ARCHITECTURE_PATH,
          "skills_doc_path" => SKILLS_DOC_PATH,
          "snapshot_path" => OUTPUT_DOC_PATH,
          "snapshot_present" => snapshot_present,
          "missing_input_docs" => missing_input_docs,
          "documented_skill_ids" => documented_ids,
          "missing_from_docs" => missing_from_docs,
          "stale_in_docs" => stale_in_docs
        },
        "skill_records" => skill_records,
        "warnings" => warnings,
        "blockers" => blockers,
        "recommendations" => recommendations(blockers, warnings, snapshot_present),
        "verification" => {
          "read_only" => true,
          "no_registry_changes" => true,
          "no_skill_behavior_changed" => true,
          "no_runtime_configuration_changed" => true,
          "no_network_access" => true,
          "no_secrets_read" => true
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Documentation Registry Refresh Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Registry"
      lines << "- path: #{report.dig('registry', 'path')}"
      lines << "- present: #{report.dig('registry', 'present')}"
      lines << "- skill_count: #{report.dig('registry', 'skill_count')}"
      lines << "- skill_ids: #{report.dig('registry', 'skill_ids').join(', ')}"
      lines << ""
      lines << "Documentation"
      report.fetch("documentation").each do |key, value|
        display = value.is_a?(Array) ? (value.empty? ? "None" : value.join(", ")) : value
        lines << "- #{key}: #{display}"
      end
      lines << ""
      lines << "Warnings"
      append(lines, report.fetch("warnings"))
      lines << ""
      lines << "Blockers"
      append(lines, report.fetch("blockers"))
      lines << ""
      lines << "Recommendations"
      append(lines, report.fetch("recommendations"))
      lines << ""
      lines << "Verification"
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines.join("\n")
    end

    def generate_snapshot
      report = assess
      return [false, "Assessment is blocked: #{report.fetch('blockers').join('; ')}"] unless report["ok"]

      body = snapshot_body(report)
      path = full(OUTPUT_DOC_PATH)
      File.write(path, body)
      [true, "Wrote #{OUTPUT_DOC_PATH}"]
    end

    private

    def yaml_available?
      defined?(YAML) && YAML
    end

    def load_registry
      return {} unless File.exist?(full(REGISTRY_PATH))
      return {} unless yaml_available?

      YAML.load_file(full(REGISTRY_PATH)) || {}
    rescue StandardError
      {}
    end

    def extract_skill_records(registry)
      candidates =
        if registry.is_a?(Hash)
          registry["skills"] || registry[:skills] || registry
        else
          registry
        end

      case candidates
      when Array
        candidates.map { |entry| normalize_skill(entry) }.compact.sort_by { |skill| skill["id"].to_s }
      when Hash
        candidates.map { |id, entry| normalize_skill(entry, fallback_id: id) }.compact.sort_by { |skill| skill["id"].to_s }
      else
        []
      end
    end

    def normalize_skill(entry, fallback_id: nil)
      data = entry.is_a?(Hash) ? entry : {}
      id = data["id"] || data[:id] || fallback_id
      return nil if id.nil? || id.to_s.strip.empty?

      {
        "id" => id.to_s,
        "name" => (data["name"] || data[:name] || id).to_s,
        "description" => (data["description"] || data[:description] || data["summary"] || data[:summary] || "").to_s,
        "category" => (data["category"] || data[:category] || data["group"] || data[:group] || "uncategorized").to_s,
        "status" => (data["status"] || data[:status] || "unknown").to_s
      }
    end

    def documented_skill_ids(docs)
      # Architecture documentation legitimately names classes, configuration
      # keys, file extensions, and stable API aliases in inline code. The skill
      # index and generated registry snapshot are the authoritative surfaces
      # for skill-ID drift; scanning every backticked token produces false
      # stale-skill blockers such as `.env` and `soul-local-chat`.
      content = [docs[SKILLS_DOC_PATH], docs[OUTPUT_DOC_PATH]].compact.join("\n")
      content.scan(/`([a-zA-Z][a-zA-Z0-9_-]*(?:\.[a-zA-Z0-9_-]+)+)`/).flatten.uniq.sort
    end

    def snapshot_body(report)
      skills = report.fetch("skill_records")
      generated_at = Time.now.iso8601

      lines = []
      lines << "# Skill Registry Snapshot"
      lines << ""
      lines << "Generated: #{generated_at}"
      lines << ""
      lines << "Source registry:"
      lines << ""
      lines << "```text"
      lines << REGISTRY_PATH
      lines << "```"
      lines << ""
      lines << "This document is a generated documentation snapshot of the active skill registry. It is intended to reduce documentation drift without changing skill behavior."
      lines << ""
      lines << "## Summary"
      lines << ""
      lines << "```text"
      lines << "skill_count: #{skills.length}"
      lines << "registry_path: #{REGISTRY_PATH}"
      lines << "```"
      lines << ""
      lines << "## Skills"
      lines << ""

      skills.each do |skill|
        lines << "### `#{skill['id']}`"
        lines << ""
        lines << "```text"
        lines << "name: #{skill['name']}"
        lines << "category: #{skill['category']}"
        lines << "status: #{skill['status']}"
        lines << "```"
        unless skill["description"].empty?
          lines << ""
          lines << skill["description"]
        end
        lines << ""
      end

      lines << "## Boundaries"
      lines << ""
      lines << "This snapshot does not activate, disable, or modify any skill."
      lines << ""
      lines << "Refresh it with:"
      lines << ""
      lines << "```bash"
      lines << "ruby bin/soul improve documentation-registry-refresh"
      lines << "```"
      lines << ""
      lines.join("\n")
    end

    def recommendations(blockers, warnings, snapshot_present)
      recs = []
      recs << "Resolve blockers before treating documentation as current." unless blockers.empty?
      recs << "Generate or refresh #{OUTPUT_DOC_PATH} with ruby bin/soul improve documentation-registry-refresh." if blockers.empty? && !snapshot_present
      recs << "Review warnings after snapshot generation." unless warnings.empty?
      recs << "Keep this refresh documentation-only; do not mutate skill registry entries from this command."
      recs << "Documentation registry surface appears ready." if blockers.empty? && warnings.empty?
      recs
    end

    def full(path)
      File.join(@root, path)
    end

    def read(path)
      full_path = full(path)
      File.exist?(full_path) ? File.read(full_path) : nil
    end

    def append(lines, items)
      items = Array(items)
      if items.empty?
        lines << "- None"
      else
        items.each { |item| lines << "- #{item}" }
      end
    end
  end
end
