
# frozen_string_literal: true

require "json"
require "time"

begin
  require "yaml"
rescue LoadError
  YAML = nil
end

module SoulCore
  class AssistantSkillCatalog
    REGISTRY_PATH = "Soul/skills/registry.yaml"
    OUTPUT_PATH = "docs/ASSISTANT_SKILL_CATALOG.md"

    RISK_RULES = [
      [/move_to_trash|restore|delete|remove|write|apply|promote|cleanup/i, "approval_required"],
      [/test|provider|api|cloud/i, "network_or_provider_check"],
      [/inspect|list|status|report|resolve|search/i, "read_only"],
      [/draft|review|brief/i, "review_only"]
    ].freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      records = skill_records
      blockers = []
      warnings = []

      blockers << "Missing skill registry: #{REGISTRY_PATH}" unless File.exist?(full(REGISTRY_PATH))
      blockers << "YAML unavailable; cannot parse #{REGISTRY_PATH}" unless yaml_available?
      blockers << "No skill records found" if records.empty?

      records.each do |skill|
        warnings << "#{skill['id']} has no description" if skill["description"].to_s.strip.empty?
        warnings << "#{skill['id']} has no example utterances" if skill["example_utterances"].empty?
      end

      {
        "ok" => blockers.empty?,
        "assessment" => "assistant_skill_catalog",
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "status" => blockers.empty? ? "ready" : "blocked",
        "registry" => {
          "path" => REGISTRY_PATH,
          "present" => File.exist?(full(REGISTRY_PATH)),
          "skill_count" => records.length,
          "skill_ids" => records.map { |skill| skill["id"] }.sort
        },
        "catalog" => {
          "output_path" => OUTPUT_PATH,
          "present" => File.exist?(full(OUTPUT_PATH)),
          "purpose" => "Human-readable assistant-facing skill catalog for chat, intent routing, and safe invocation planning."
        },
        "skills" => records,
        "warnings" => warnings,
        "blockers" => blockers,
        "recommendations" => recommendations(blockers, warnings),
        "verification" => {
          "read_only" => true,
          "no_registry_changes" => true,
          "no_skill_behavior_changed" => true,
          "no_runtime_data_written" => true,
          "no_network_access" => true,
          "no_secrets_read" => true
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Assistant Skill Catalog Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Registry"
      lines << "- path: #{report.dig('registry', 'path')}"
      lines << "- present: #{report.dig('registry', 'present')}"
      lines << "- skill_count: #{report.dig('registry', 'skill_count')}"
      lines << ""
      lines << "Catalog"
      lines << "- output_path: #{report.dig('catalog', 'output_path')}"
      lines << "- present: #{report.dig('catalog', 'present')}"
      lines << "- purpose: #{report.dig('catalog', 'purpose')}"
      lines << ""
      lines << "Skills"
      report.fetch("skills").each do |skill|
        lines << "- #{skill['id']}"
        lines << "  name: #{skill['human_name']}"
        lines << "  risk: #{skill['risk']}"
        lines << "  confirmation_required: #{skill['confirmation_required']}"
        lines << "  examples: #{skill['example_utterances'].join(' | ')}"
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

    def generate
      report = assess
      return [false, "Assessment is blocked: #{report.fetch('blockers').join('; ')}"] unless report["ok"]

      File.write(full(OUTPUT_PATH), catalog_markdown(report))
      [true, "Wrote #{OUTPUT_PATH}"]
    end

    private

    def yaml_available?
      defined?(YAML) && YAML
    end

    def skill_records
      registry = load_registry
      raw =
        if registry.is_a?(Hash)
          registry["skills"] || registry[:skills] || registry
        else
          registry
        end

      records =
        case raw
        when Array
          raw.map { |entry| normalize(entry) }
        when Hash
          raw.map { |id, entry| normalize(entry, fallback_id: id) }
        else
          []
        end

      records.compact.sort_by { |skill| skill["id"] }
    end

    def load_registry
      return {} unless File.exist?(full(REGISTRY_PATH))
      return {} unless yaml_available?

      YAML.load_file(full(REGISTRY_PATH)) || {}
    rescue StandardError
      {}
    end

    def normalize(entry, fallback_id: nil)
      data = entry.is_a?(Hash) ? entry : {}
      id = data["id"] || data[:id] || fallback_id
      return nil if id.to_s.strip.empty?

      description = (data["description"] || data[:description] || data["summary"] || data[:summary] || "").to_s.strip
      human_name = humanize(id.to_s)
      risk = infer_risk(id.to_s, description)
      confirmation_required = risk == "approval_required"

      {
        "id" => id.to_s,
        "human_name" => human_name,
        "description" => description,
        "category" => (data["category"] || data[:category] || "uncategorized").to_s,
        "status" => (data["status"] || data[:status] || "unknown").to_s,
        "risk" => risk,
        "confirmation_required" => confirmation_required,
        "example_utterances" => examples_for(id.to_s, human_name, risk)
      }
    end

    def infer_risk(id, description)
      text = "#{id} #{description}"
      match = RISK_RULES.find { |regex, _risk| text.match?(regex) }
      match ? match[1] : "unknown"
    end

    def humanize(id)
      id.to_s.split(/[._:-]/).map(&:capitalize).join(" ")
    end

    def examples_for(id, human_name, risk)
      base = case id
             when /skill\.brief\.draft/
               ["draft a skill brief", "help me design a new skill"]
             when /skill\.brief\.review/
               ["review this skill brief", "check whether this skill proposal is safe"]
             when /downloads\.inspect/
               ["inspect my downloads", "show me what is in downloads"]
             when /downloads\.cleanup_plan/
               ["plan a downloads cleanup", "what can be cleaned up safely"]
             when /downloads\.move_to_trash/
               ["move approved downloads to trash", "execute the cleanup plan"]
             when /downloads\.restore_last_cleanup/
               ["restore the last downloads cleanup", "undo the last cleanup"]
             when /weather\.report/
               ["get the weather", "what is the weather report"]
             when /system\.status/
               ["check system status", "how is the system doing"]
             when /cloud\.providers\.list/
               ["list cloud providers", "what cloud providers are configured"]
             when /cloud\.providers\.test/
               ["test cloud providers", "check provider connectivity"]
             when /youtube\.song_search/
               ["search YouTube for a song", "find this song on YouTube"]
             when /youtube\.video_resolve/
               ["resolve a YouTube video", "find the best YouTube video candidate"]
             else
               ["use #{human_name.downcase}", "run #{id}"]
             end

      risk == "approval_required" ? base + ["prepare this first and ask before changing anything"] : base
    end

    def catalog_markdown(report)
      lines = []
      lines << "# Assistant Skill Catalog"
      lines << ""
      lines << "Generated: #{Time.now.iso8601}"
      lines << ""
      lines << "Source registry:"
      lines << ""
      lines << "```text"
      lines << REGISTRY_PATH
      lines << "```"
      lines << ""
      lines << "This catalog explains registered Soul skills in language suitable for chat, intent routing, and safe skill invocation planning."
      lines << ""
      lines << "It does not activate, disable, or modify any skill."
      lines << ""
      lines << "## Skill count"
      lines << ""
      lines << "```text"
      lines << report.dig("registry", "skill_count").to_s
      lines << "```"
      lines << ""
      lines << "## Skills"
      lines << ""

      report.fetch("skills").each do |skill|
        lines << "### #{skill['human_name']}"
        lines << ""
        lines << "```text"
        lines << "id: #{skill['id']}"
        lines << "category: #{skill['category']}"
        lines << "status: #{skill['status']}"
        lines << "risk: #{skill['risk']}"
        lines << "confirmation_required: #{skill['confirmation_required']}"
        lines << "```"
        lines << ""
        lines << (skill["description"].empty? ? "No description is currently available." : skill["description"])
        lines << ""
        lines << "Example ways the owner might ask for this:"
        lines << ""
        skill["example_utterances"].each { |example| lines << "- #{example}" }
        lines << ""
      end

      lines << "## Risk language"
      lines << ""
      lines << "```text"
      lines << "read_only: can inspect or report without changing local state"
      lines << "review_only: drafts or reviews artifacts without promotion"
      lines << "network_or_provider_check: may involve configured provider/API testing"
      lines << "approval_required: must ask before changing local state"
      lines << "unknown: needs routing caution until classified"
      lines << "```"
      lines << ""
      lines << "## Future use"
      lines << ""
      lines << "This catalog should feed chat explanations, intent routing, and skill invocation planning."
      lines << ""
      lines.join("\n")
    end

    def recommendations(blockers, warnings)
      recs = []
      recs << "Resolve blockers before using the skill catalog for chat routing." unless blockers.empty?
      recs << "Generate #{OUTPUT_PATH} with ruby bin/soul improve assistant-skill-catalog." if blockers.empty?
      recs << "Review warnings and enrich registry metadata over time." unless warnings.empty?
      recs << "Use this catalog as input for intent routing, not as an execution permission source."
      recs << "Assistant-facing skill catalog is ready." if blockers.empty? && warnings.empty?
      recs
    end

    def full(path)
      File.join(@root, path)
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
