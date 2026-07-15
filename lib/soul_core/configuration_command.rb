# frozen_string_literal: true

require "json"
require_relative "configuration_resolver"

module SoulCore
  class ConfigurationCommand
    def initialize(argv:, root: Dir.pwd, process_env: ENV, output: $stdout)
      @argv = argv.dup
      @root = File.expand_path(root)
      @process_env = process_env.to_h
      @output = output
    end

    def run
      action = @argv.shift
      return render_terminal("awaiting_input", "Choose config show, explain, or validate.") unless action
      return render_terminal("canceled", "Configuration request canceled.") if action == "cancel"

      json = remove_flag("--json")
      overrides, override_error = extract_overrides
      return render_terminal("failed", override_error, json: json) if override_error

      report = ConfigurationResolver.new(
        root: @root,
        process_env: @process_env,
        overrides: overrides
      ).resolve

      case action
      when "show", "validate"
        render_report(report, json: json, validation_only: action == "validate")
      when "explain"
        key = @argv.shift
        return render_terminal("awaiting_input", "config explain requires one canonical key.", json: json) if key.to_s.empty?

        setting = report.fetch("settings").find { |record| record.fetch("key") == key }
        return render_terminal("failed", "Unknown configuration key #{key}.", json: json) unless setting

        focused = report.merge("settings" => [setting], "setting_count" => 1)
        render_report(focused, json: json)
      else
        render_terminal("failed", "Unknown configuration action #{action}.", json: json)
      end
    end

    private

    def remove_flag(flag)
      present = @argv.include?(flag)
      @argv.delete(flag)
      present
    end

    def extract_overrides
      overrides = []
      remaining = []
      index = 0
      while index < @argv.length
        if @argv[index] == "--set"
          value = @argv[index + 1]
          return [[], "--set requires canonical.key=value."] if value.nil?
          overrides << value
          index += 2
        else
          remaining << @argv[index]
          index += 1
        end
      end
      @argv = remaining
      [overrides, nil]
    end

    def render_report(report, json:, validation_only: false)
      if json
        @output.puts JSON.pretty_generate(report)
      else
        @output.puts "Soul configuration"
        @output.puts "Lifecycle: #{report.fetch('lifecycle_state')}"
        @output.puts "Mutation: none"
        @output.puts "Dotenv: #{report.fetch('dotenv_loaded') ? "loaded #{report['dotenv_path']}" : 'not loaded'}"
        @output.puts "Validation errors: #{report.fetch('error_count')}"
        unless validation_only
          report.fetch("settings").each do |setting|
            value = setting["secret"] ? (setting["configured"] ? "[REDACTED] (configured)" : "not configured") : setting["value"].inspect
            @output.puts "- #{setting['key']}: #{value} [#{setting['source']}]"
            @output.puts "  #{setting['behavioral_effect']}"
            @output.puts "  Privacy/risk: #{setting['privacy_risk']} Restart required: #{setting['restart_required'] ? 'yes' : 'no'}"
          end
        end
        report.fetch("errors").each do |error|
          if error.is_a?(Hash)
            @output.puts "Error: #{error['key']}: #{error['reason']}"
          else
            @output.puts "Error: #{error}"
          end
        end
      end
      report.fetch("ok") ? 0 : 1
    end

    def render_terminal(lifecycle, reason, json: false)
      report = {
        "ok" => lifecycle == "complete",
        "lifecycle_state" => lifecycle,
        "reason" => reason,
        "mutation" => "none"
      }
      @output.puts(json ? JSON.pretty_generate(report) : "Lifecycle: #{lifecycle}\n#{reason}\nMutation: none")
      lifecycle == "complete" || lifecycle == "canceled" ? 0 : 1
    end
  end
end
