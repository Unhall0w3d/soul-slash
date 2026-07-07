#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

path = "Soul/skills/registry.yaml"

unless File.exist?(path)
  warn "Missing #{path}"
  exit 1
end

registry = YAML.safe_load(File.read(path), aliases: true)
registry = {} unless registry.is_a?(Hash)

entries = {
  "cloud.providers.list" => {
    "description" => "List configured cloud LLM providers without making network calls.",
    "path" => "Soul/skills/cloud/providers/list.rb",
    "script" => "Soul/skills/cloud/providers/list.rb",
    "entrypoint" => "Soul/skills/cloud/providers/list.rb",
    "command" => "ruby Soul/skills/cloud/providers/list.rb",
    "read_only" => true,
    "network" => false,
    "category" => "cloud"
  },
  "cloud.providers.test" => {
    "description" => "Run bounded smoke tests for configured cloud LLM providers.",
    "path" => "Soul/skills/cloud/providers/test.rb",
    "script" => "Soul/skills/cloud/providers/test.rb",
    "entrypoint" => "Soul/skills/cloud/providers/test.rb",
    "command" => "ruby Soul/skills/cloud/providers/test.rb",
    "read_only" => true,
    "network" => true,
    "category" => "cloud"
  },
  "skill.brief.draft" => {
    "description" => "Draft a review-only Soul/ skill proposal using a configured cloud provider.",
    "path" => "Soul/skills/skill/brief/draft.rb",
    "script" => "Soul/skills/skill/brief/draft.rb",
    "entrypoint" => "Soul/skills/skill/brief/draft.rb",
    "command" => "ruby Soul/skills/skill/brief/draft.rb",
    "read_only" => true,
    "network" => true,
    "category" => "skill-development"
  },
  "skill.brief.review" => {
    "description" => "Review a Soul/ skill proposal and write a review-only artifact.",
    "path" => "Soul/skills/skill/brief/review.rb",
    "script" => "Soul/skills/skill/brief/review.rb",
    "entrypoint" => "Soul/skills/skill/brief/review.rb",
    "command" => "ruby Soul/skills/skill/brief/review.rb",
    "read_only" => true,
    "network" => true,
    "category" => "skill-development"
  }
}

def infer_entry_shape(registry)
  container =
    if registry["skills"].is_a?(Hash)
      registry["skills"]
    elsif registry.is_a?(Hash)
      registry
    else
      {}
    end

  sample = container.values.find { |value| value.is_a?(Hash) }
  sample || {}
end

def trim_entry_for_shape(entry, shape)
  return entry if shape.empty?

  kept = {}

  %w[path script entrypoint command].each do |key|
    kept[key] = entry[key] if shape.key?(key)
  end

  # Always keep useful metadata. Most YAML-backed runners ignore unknown keys,
  # and humans enjoy descriptions, allegedly.
  kept["description"] = entry["description"]
  kept["read_only"] = entry["read_only"] if shape.key?("read_only")
  kept["network"] = entry["network"] if shape.key?("network")
  kept["category"] = entry["category"] if shape.key?("category")

  # If the existing shape gave us no executable key, keep the common path key.
  kept["path"] ||= entry["path"]

  kept
end

shape = infer_entry_shape(registry)

if registry["skills"].is_a?(Hash)
  entries.each do |name, entry|
    registry["skills"][name] = (registry["skills"][name] || {}).merge(trim_entry_for_shape(entry, shape))
  end
elsif registry["skills"].is_a?(Array)
  existing_names = registry["skills"].filter_map { |item| item["name"] if item.is_a?(Hash) }
  entries.each do |name, entry|
    next if existing_names.include?(name)

    registry["skills"] << { "name" => name }.merge(trim_entry_for_shape(entry, shape))
  end
elsif registry.is_a?(Hash)
  entries.each do |name, entry|
    registry[name] = (registry[name] || {}).merge(trim_entry_for_shape(entry, shape))
  end
else
  warn "Unsupported registry structure in #{path}"
  exit 1
end

File.write(path, registry.to_yaml)

puts "Patched #{path}: registered cloud provider and skill brief skills."
puts "Registered:"
entries.keys.each { |name| puts "- #{name}" }

syntax_ok = system("ruby", "-e", "require 'yaml'; YAML.safe_load(File.read('#{path}'), aliases: true); puts 'YAML OK'")
exit(syntax_ok ? 0 : 1)
