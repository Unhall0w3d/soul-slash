
# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "time"

module SoulCore
  class RubyRuntimeCompatibilityAssessor
    CORE_COMMANDS = [
      {
        "id" => "skills_json",
        "command" => ["ruby", "bin/soul", "skills", "--json"],
        "expect_json" => true,
        "required_json_shape" => "object_or_array"
      },
      {
        "id" => "doctor_json",
        "command" => ["ruby", "bin/soul", "doctor", "--json"],
        "expect_json" => true,
        "required_json_shape" => "object"
      },
      {
        "id" => "repo_curation_json",
        "command" => ["ruby", "bin/soul", "assess", "repo-curation", "--json"],
        "expect_json" => true,
        "required_json_shape" => "object"
      },
      {
        "id" => "skill_loop_text",
        "command" => ["ruby", "bin/soul", "assess", "skill-loop"],
        "expect_json" => false
      },
      {
        "id" => "codex_loop_text",
        "command" => ["ruby", "bin/soul", "assess", "codex-loop"],
        "expect_json" => false
      }
    ].freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      ruby_files = tracked_ruby_files
      syntax_results = syntax_check(ruby_files)
      command_results = run_core_commands

      runtime = runtime_details
      version_status = classify_ruby(runtime["ruby_version"])

      blockers = []
      failed_syntax = syntax_results.reject { |item| item["ok"] }
      failed_commands = command_results.reject { |item| item["ok"] }

      blockers << "Ruby version is older than 3.4.0: #{runtime['ruby_version']}" if version_status == "too_old"
      blockers << "Ruby syntax failure(s): #{failed_syntax.map { |item| item['path'] }.join(', ')}" unless failed_syntax.empty?
      blockers << "Core CLI smoke check failure(s): #{failed_commands.map { |item| item['id'] }.join(', ')}" unless failed_commands.empty?

      {
        "ok" => blockers.empty?,
        "assessment" => "ruby_runtime_compatibility",
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "status" => blockers.empty? ? "compatible" : "blocked",
        "runtime" => runtime,
        "version_status" => version_status,
        "expected_runtime_strategy" => {
          "system_ruby_mutation" => false,
          "project_scoped_ruby" => true,
          "recommended_project_file" => ".ruby-version",
          "recommended_activation" => "rbenv local <version>",
          "note" => "Ruby should be selected per project instead of replacing the OS Ruby."
        },
        "compatibility_expectations" => {
          "minimum_supported_ruby" => "3.4.0",
          "ruby_4_supported_when_checks_pass" => true,
          "stdlib_only_assessment" => true,
          "bundler_required_for_assessment" => false,
          "network_required" => false
        },
        "tracked_ruby_file_count" => ruby_files.length,
        "syntax_results" => syntax_results,
        "core_command_results" => command_results,
        "blockers" => blockers,
        "recommendations" => recommendations(runtime, version_status, blockers),
        "verification" => {
          "read_only" => true,
          "no_files_modified" => true,
          "no_gems_installed" => true,
          "no_bundler_install" => true,
          "no_system_ruby_changes" => true,
          "no_network_access" => true
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Ruby Runtime Compatibility Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << "Ruby: #{report.dig('runtime', 'ruby_description')}"
      lines << "Ruby executable: #{report.dig('runtime', 'ruby_executable')}"
      lines << "RubyGems: #{report.dig('runtime', 'rubygems_version')}"
      lines << "Bundler: #{report.dig('runtime', 'bundler_version')}"
      lines << "Version status: #{report['version_status']}"
      lines << ""
      lines << "Runtime strategy"
      report.fetch("expected_runtime_strategy").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Compatibility expectations"
      report.fetch("compatibility_expectations").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Syntax checks"
      lines << "- tracked Ruby files: #{report['tracked_ruby_file_count']}"
      failed_syntax = report.fetch("syntax_results").reject { |item| item["ok"] }
      if failed_syntax.empty?
        lines << "- failures: None"
      else
        failed_syntax.each { |item| lines << "- #{item['path']}: #{item['stderr']}" }
      end
      lines << ""
      lines << "Core CLI smoke checks"
      report.fetch("core_command_results").each do |item|
        lines << "- #{item['id']}: #{item['ok'] ? 'ok' : 'failed'}"
        lines << "  command: #{item['command'].join(' ')}"
        lines << "  exit_status: #{item['exit_status']}"
        lines << "  note: #{item['note']}" if item["note"] && !item["note"].empty?
      end
      lines << ""
      lines << "Recommendations"
      append_items(lines, report.fetch("recommendations"))
      lines << ""
      lines << "Blockers"
      append_items(lines, report.fetch("blockers"))
      lines << ""
      lines << "Verification"
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines.join("\n")
    end

    private

    def runtime_details
      {
        "ruby_description" => RUBY_DESCRIPTION,
        "ruby_version" => RUBY_VERSION,
        "ruby_engine" => defined?(RUBY_ENGINE) ? RUBY_ENGINE : "ruby",
        "ruby_platform" => RUBY_PLATFORM,
        "ruby_patchlevel" => RUBY_PATCHLEVEL,
        "ruby_executable" => RbConfig.ruby,
        "ruby_bindir" => RbConfig::CONFIG["bindir"],
        "rubygems_version" => rubygems_version,
        "bundler_version" => bundler_version,
        "gem_home" => safe_capture("gem", "env", "home"),
        "gem_path" => safe_capture("gem", "env", "path"),
        "rbenv_version" => safe_capture("rbenv", "version"),
        "rbenv_which_ruby" => safe_capture("rbenv", "which", "ruby"),
        "ruby_version_file" => ruby_version_file
      }
    end

    def rubygems_version
      Gem::VERSION
    rescue StandardError
      nil
    end

    def bundler_version
      require "bundler"
      Bundler::VERSION
    rescue LoadError
      nil
    rescue StandardError => error
      "error: #{error.class}: #{error.message}"
    end

    def ruby_version_file
      path = File.join(@root, ".ruby-version")
      File.exist?(path) ? File.read(path).strip : nil
    end

    def classify_ruby(version)
      segments = version.to_s.split(".").map(&:to_i)
      major = segments[0] || 0
      minor = segments[1] || 0

      return "too_old" if major < 3
      return "too_old" if major == 3 && minor < 4
      return "ruby_4_active" if major >= 4
      return "ruby_3_4_active" if major == 3 && minor == 4

      "supported"
    end

    def tracked_ruby_files
      stdout, _stderr, status = Open3.capture3("git", "ls-files", "*.rb")
      return Dir.glob(File.join(@root, "**/*.rb")).map { |path| relative(path) }.sort unless status.success?

      stdout.lines.map(&:strip).reject(&:empty?).sort
    end

    def syntax_check(paths)
      paths.map do |path|
        stdout, stderr, status = Open3.capture3("ruby", "-c", path, chdir: @root)
        {
          "path" => path,
          "ok" => status.success?,
          "exit_status" => status.exitstatus,
          "stdout" => truncate(stdout.strip),
          "stderr" => truncate(stderr.strip)
        }
      end
    end

    def run_core_commands
      CORE_COMMANDS.map do |item|
        stdout, stderr, status = Open3.capture3(*item.fetch("command"), chdir: @root)
        ok = status.success?
        note = ""

        if ok && item["expect_json"]
          begin
            parsed = JSON.parse(stdout)
            shape = parsed.is_a?(Array) ? "array" : parsed.is_a?(Hash) ? "object" : parsed.class.name
            required = item["required_json_shape"]
            ok = required == "object_or_array" ? parsed.is_a?(Array) || parsed.is_a?(Hash) : shape == required
            note = "json_shape=#{shape}"
          rescue JSON::ParserError => error
            ok = false
            note = "invalid_json=#{error.message}"
          end
        end

        {
          "id" => item.fetch("id"),
          "command" => item.fetch("command"),
          "ok" => ok,
          "exit_status" => status.exitstatus,
          "note" => note,
          "stdout_preview" => truncate(stdout.strip),
          "stderr_preview" => truncate(stderr.strip)
        }
      end
    end

    def recommendations(runtime, version_status, blockers)
      recs = []
      recs << "Keep Ruby project-scoped through rbenv; do not replace the OS Ruby."
      recs << "Leave .ruby-version local until Ruby 4 smoke checks are clean, then decide whether to commit it."
      recs << "Ruby 4 is active for this project; continue only if the assessment remains compatible." if version_status == "ruby_4_active"
      recs << "Ruby is still 3.4.x for this project; switch with rbenv local before evaluating Ruby 4 compatibility." if version_status == "ruby_3_4_active"
      recs << "Resolve blockers before adding more skills or expanding doctor." unless blockers.empty?
      recs << "Current runtime surface is compatible." if blockers.empty?
      recs
    end

    def safe_capture(*cmd)
      stdout, stderr, status = Open3.capture3(*cmd, chdir: @root)
      status.success? ? stdout.strip : "unavailable: #{stderr.strip}"
    rescue Errno::ENOENT
      "unavailable"
    end

    def truncate(text, limit = 800)
      text = text.to_s
      text.length > limit ? "#{text[0, limit]}..." : text
    end

    def relative(path)
      Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s
    rescue StandardError
      path
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
