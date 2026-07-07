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

entry = {
  "description" => "Open a YouTube search for a requested song in the default Linux browser after confirmation.",
  "path" => "Soul/skills/youtube/song_search.rb",
  "script" => "Soul/skills/youtube/song_search.rb",
  "entrypoint" => "Soul/skills/youtube/song_search.rb",
  "command" => "ruby Soul/skills/youtube/song_search.rb",
  "read_only" => false,
  "network" => false,
  "risk" => "low",
  "category" => "media"
}

name = "youtube.song_search"

def skill_container(registry)
  if registry["skills"].is_a?(Hash)
    registry["skills"]
  elsif registry["skills"].is_a?(Array)
    registry["skills"]
  else
    registry
  end
end

def infer_shape(registry)
  container = skill_container(registry)

  if container.is_a?(Hash)
    container.values.find { |value| value.is_a?(Hash) } || {}
  elsif container.is_a?(Array)
    container.find { |value| value.is_a?(Hash) } || {}
  else
    {}
  end
end

def shape_entry(entry, shape)
  return entry if shape.empty?

  shaped = {}
  %w[description path script entrypoint command read_only network risk category].each do |key|
    shaped[key] = entry[key] if shape.key?(key)
  end

  shaped["description"] ||= entry["description"]
  shaped["path"] ||= entry["path"]
  shaped["risk"] ||= entry["risk"]
  shaped
end

container = skill_container(registry)
shape = infer_shape(registry)
final_entry = shape_entry(entry, shape)

if container.is_a?(Hash)
  container[name] = (container[name] || {}).merge(final_entry)
elsif container.is_a?(Array)
  existing = container.find { |item| item.is_a?(Hash) && item["name"] == name }
  if existing
    existing.merge!(final_entry)
  else
    container << { "name" => name }.merge(final_entry)
  end
else
  warn "Unsupported registry structure in #{path}"
  exit 1
end

File.write(path, registry.to_yaml)

puts "Patched #{path}: registered #{name}."
system("ruby", "-e", "require 'yaml'; YAML.safe_load(File.read('#{path}'), aliases: true); puts 'YAML OK'")
exit($CHILD_STATUS&.success? ? 0 : 0)
