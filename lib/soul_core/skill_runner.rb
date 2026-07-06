# frozen_string_literal: true

require "json"
require "open3"

module SoulCore
  class SkillRunner
    def initialize(registry:)
      @registry = registry
    end

    def run(name, args: [])
      skill = @registry.fetch(name)
      path = skill.fetch("path")
      risk = skill.fetch("risk")

      raise "skill path does not exist: #{path}" unless File.exist?(path)

      unless risk == "read_only"
        explicit_execution = args.include?("--execute")
        confirmation_phrase = skill.fetch("confirmation_phrase", nil)
        explicit_confirmation =
          confirmation_phrase &&
          args.each_cons(2).any? { |key, value| key == "--confirm" && value == confirmation_phrase }

        if explicit_execution && !explicit_confirmation
          raise "write skill requires exact confirmation: --confirm #{confirmation_phrase || '<missing confirmation_phrase>'}"
        end
      end

      stdout, stderr, status = Open3.capture3("ruby", path, *args)

      parsed = begin
        JSON.parse(stdout)
      rescue JSON::ParserError
        nil
      end

      {
        skill: name,
        args: args,
        ok: status.success? && !parsed.nil?,
        exit_status: status.exitstatus,
        stdout: stdout,
        stderr: stderr,
        json: parsed
      }
    end
  end
end
