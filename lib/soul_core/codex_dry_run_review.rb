
# frozen_string_literal: true

require "json"
require "time"

module SoulCore
  class CodexDryRunReview
    REQUIRED_RESPONSE_SECTIONS = [
      "summary",
      "files_changed",
      "commands_to_verify",
      "risks",
      "rollback",
      "human_review_notes"
    ].freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def review(contract_path:, response_path:)
      contract = read_json(expand_path(contract_path))
      response = read_json(expand_path(response_path))

      blockers = []
      warnings = []

      blockers << "Contract file is missing or invalid JSON." unless contract
      blockers << "Response file is missing or invalid JSON." unless response

      return base_report(contract_path, response_path, contract, response, blockers, warnings) unless contract && response

      allowed_files = Array(contract["allowed_files"])
      forbidden_files = Array(contract["forbidden_files"])
      files_changed = Array(response["files_changed"])

      missing_sections = REQUIRED_RESPONSE_SECTIONS.reject { |section| response.key?(section) }
      blockers << "Response is missing required section(s): #{missing_sections.join(', ')}" unless missing_sections.empty?

      disallowed_files = files_changed.reject { |file| allowed_by_patterns?(file, allowed_files) }
      forbidden_hits = files_changed.select { |file| matched_by_patterns?(file, forbidden_files) }

      blockers << "Response changes files outside allowed list: #{disallowed_files.join(', ')}" unless disallowed_files.empty?
      blockers << "Response touches forbidden files: #{forbidden_hits.join(', ')}" unless forbidden_hits.empty?

      warnings << "Response did not list any changed files." if files_changed.empty?
      warnings << "Response does not include verifier command guidance." if Array(response["commands_to_verify"]).empty?
      warnings << "Response rollback notes are empty." if blank?(response["rollback"])
      warnings << "Response risks are empty." if Array(response["risks"]).empty?

      if response["implementation_patch"]
        warnings << "Implementation patch content is present. Phase 28 reviews only and does not apply patches."
      end

      base_report(contract_path, response_path, contract, response, blockers, warnings).merge(
        "files" => {
          "allowed_patterns" => allowed_files,
          "forbidden_patterns" => forbidden_files,
          "files_changed" => files_changed,
          "disallowed_files" => disallowed_files,
          "forbidden_hits" => forbidden_hits
        },
        "sections" => {
          "required" => REQUIRED_RESPONSE_SECTIONS,
          "present" => REQUIRED_RESPONSE_SECTIONS.select { |section| response.key?(section) },
          "missing" => missing_sections
        }
      )
    end

    def render(report)
      lines = []
      lines << "Soul Codex Dry-Run Review"
      lines << "Generated: #{report['generated_at']}"
      lines << "Readiness: #{report['readiness']}"
      lines << "Contract: #{report['contract_path']}"
      lines << "Response: #{report['response_path']}"
      lines << ""
      lines << "Blockers"
      append_items(lines, report.fetch("blockers"))
      lines << ""
      lines << "Warnings"
      append_items(lines, report.fetch("warnings"))
      if report["files"]
        lines << ""
        lines << "Files changed"
        append_items(lines, report.dig("files", "files_changed"))
        lines << ""
        lines << "Disallowed files"
        append_items(lines, report.dig("files", "disallowed_files"))
        lines << ""
        lines << "Forbidden hits"
        append_items(lines, report.dig("files", "forbidden_hits"))
      end
      if report["sections"]
        lines << ""
        lines << "Missing sections"
        append_items(lines, report.dig("sections", "missing"))
      end
      lines << ""
      lines << "Verification"
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines.join("\n")
    end

    private

    def base_report(contract_path, response_path, contract, response, blockers, warnings)
      {
        "ok" => blockers.empty?,
        "assessment" => "codex_dry_run_review",
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "contract_path" => contract_path,
        "response_path" => response_path,
        "readiness" => blockers.empty? ? "review_ready" : "blocked",
        "contract_valid" => !contract.nil?,
        "response_valid" => !response.nil?,
        "blockers" => blockers,
        "warnings" => warnings,
        "promotion_allowed" => false,
        "application_allowed" => false,
        "verification" => {
          "review_only" => true,
          "no_codex_invoked" => true,
          "no_patches_applied" => true,
          "no_files_modified" => true,
          "no_runtime_configuration_changed" => true,
          "no_secrets_read" => true
        }
      }
    end

    def read_json(path)
      return nil unless File.exist?(path)
      JSON.parse(File.read(path))
    rescue JSON::ParserError
      nil
    end

    def expand_path(path)
      File.expand_path(path, @root)
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def allowed_by_patterns?(file, patterns)
      patterns.any? { |pattern| file_matches_pattern?(file, pattern) }
    end

    def matched_by_patterns?(file, patterns)
      patterns.any? { |pattern| file_matches_pattern?(file, pattern) }
    end

    def file_matches_pattern?(file, pattern)
      return true if file == pattern

      regex = Regexp.escape(pattern)
                   .gsub("\\*\\*", ".*")
                   .gsub("\\*", "[^/]*")
                   .gsub("<new_feature>", "[^/]+")
                   .gsub("<feature>", "[^/]+")
                   .gsub("<PHASE_DOC>", "[^/]+")
                   .gsub("<FEATURE_DOC>", "[^/]+")
      !!(file =~ /\A#{regex}\z/)
    end

    def append_items(lines, items)
      items = Array(items)
      if items.empty?
        lines << "- None"
      else
        items.each { |item| lines << "- #{item}" }
      end
    end
  end
end
