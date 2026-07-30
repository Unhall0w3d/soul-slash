
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
      registry_ids = skill_records.map { |skill| skill["id"] }.compact.sort
      documented_ids = documented_skill_ids(docs, registry_ids)
      missing_from_docs = registry_ids - documented_ids
      expected_snapshot = snapshot_body(skill_records)
      snapshot_current = snapshot_present && docs[OUTPUT_DOC_PATH] == expected_snapshot

      blockers = []
      blockers << "Missing skill registry: #{REGISTRY_PATH}" unless File.exist?(full(REGISTRY_PATH))
      blockers << "YAML is unavailable; cannot parse #{REGISTRY_PATH}" unless yaml_available?
      blockers << "No skills could be extracted from #{REGISTRY_PATH}" if skill_records.empty?
      blockers << "Missing input documentation file(s): #{missing_input_docs.join(', ')}" unless missing_input_docs.empty?

      warnings = []
      warnings << "Skill id(s) missing from human documentation: #{missing_from_docs.join(', ')}" unless missing_from_docs.empty?
      warnings << "Snapshot document has not been generated yet: #{OUTPUT_DOC_PATH}" unless snapshot_present
      warnings << "Snapshot is stale relative to #{REGISTRY_PATH}: #{OUTPUT_DOC_PATH}" if snapshot_present && !snapshot_current

      current = blockers.empty? && warnings.empty?

      {
        "ok" => blockers.empty?,
        "assessment" => "documentation_registry_refresh",
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "status" => if !blockers.empty?
                      "blocked"
                    elsif current
                      "ready"
                    else
                      "needs_refresh"
                    end,
        "current" => current,
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
          "snapshot_current" => snapshot_current,
          "missing_input_docs" => missing_input_docs,
          "human_documentation_paths" => INPUT_DOC_PATHS,
          "documented_skill_ids" => documented_ids,
          "missing_from_docs" => missing_from_docs,
          "human_documentation_complete" => missing_input_docs.empty? && missing_from_docs.empty?
        },
        "skill_records" => skill_records,
        "warnings" => warnings,
        "blockers" => blockers,
        "recommendations" => recommendations(blockers, warnings, snapshot_present, snapshot_current),
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
      return [false, "Assessment is blocked: #{report.fetch('blockers').join('; ')}"] unless report.fetch("blockers").empty?

      body = snapshot_body(report.fetch("skill_records"))
      path = full(OUTPUT_DOC_PATH)
      return [true, "#{OUTPUT_DOC_PATH} is already current"] if File.exist?(path) && File.read(path) == body

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
      }.tap do |record|
        copy_metadata(record, "name", data["name"] || data[:name])
        copy_metadata(record, "description", data["description"] || data[:description] || data["summary"] || data[:summary])
        copy_metadata(record, "category", data["category"] || data[:category] || data["group"] || data[:group])
        copy_metadata(record, "status", data["status"] || data[:status])
      end
    end

    def copy_metadata(record, key, value)
      return if value.nil? || value.to_s.strip.empty?

      record[key] = value.to_s
    end

    def documented_skill_ids(docs, registry_ids)
      # Only human-maintained source documents count as human documentation.
      # Match the known registry IDs literally, with skill-ID boundaries, so
      # arbitrary inline-code tokens are never inferred to be skill IDs.
      content = INPUT_DOC_PATHS.filter_map { |path| docs[path] }.join("\n")
      registry_ids.select do |id|
        content.match?(/(?<![A-Za-z0-9_.-])#{Regexp.escape(id)}(?![A-Za-z0-9_.-])/)
      end.sort
    end

    def snapshot_body(skills)
      lines = []
      lines << "# Skill Registry Snapshot"
      lines << ""
      lines << "Source registry:"
      lines << ""
      lines << "```text"
      lines << REGISTRY_PATH
      lines << "```"
      lines << ""
      lines << "This document is a deterministic projection of the registered skill records. Registration does not imply availability when the source record does not declare an availability status."
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
        lines << "name: #{skill.fetch('name', 'not declared')}"
        lines << "category: #{skill.fetch('category', 'not declared')}"
        lines << "status: #{skill.fetch('status', 'registered (availability not declared)')}"
        lines << "```"
        if skill.key?("description")
          lines << ""
          lines << skill["description"]
        else
          lines << ""
          lines << "Description not declared in the registry."
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

    def recommendations(blockers, warnings, snapshot_present, snapshot_current)
      recs = []
      recs << "Resolve blockers before treating documentation as current." unless blockers.empty?
      recs << "Generate or refresh #{OUTPUT_DOC_PATH} with ruby bin/soul improve documentation-registry-refresh." if blockers.empty? && (!snapshot_present || !snapshot_current)
      recs << "Review human-documentation coverage and snapshot synchronization warnings." unless warnings.empty?
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
