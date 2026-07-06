# frozen_string_literal: true

require "yaml"

module SoulCore
  class SkillRegistry
    def initialize(path: "Soul/skills/registry.yaml")
      @path = path
      @data = File.exist?(path) ? YAML.load_file(path) : { "skills" => {} }
    end

    def list
      @data.fetch("skills", {})
    end

    def fetch(name)
      skill = list[name]
      raise ArgumentError, "unknown skill: #{name}" unless skill

      skill
    end
  end
end
