# frozen_string_literal: true

require "fileutils"
require "json"

module SoulCore
  class ConversationEvidenceStore
    DEFAULT_ROOT = "Soul/runtime/conversation_evidence"

    def initialize(root: Dir.pwd, evidence_root: DEFAULT_ROOT)
      @project_root = File.expand_path(root)
      @root = File.join(@project_root, evidence_root)
      FileUtils.mkdir_p(@root)
    end

    def append(evidence)
      record = evidence.respond_to?(:to_h) ? evidence.to_h : stringify_keys(evidence)
      File.open(path_for(record.fetch("chat_id")), "a") do |file|
        file.puts(JSON.generate(record))
      end
      record
    end

    def recent(chat_id, limit: 5)
      path = path_for(chat_id)
      return [] unless File.exist?(path)

      File.readlines(path, chomp: true)
        .reject(&:empty?)
        .filter_map { |line| parse_line(line) }
        .last(normalize_limit(limit))
    end

    def latest(chat_id)
      recent(chat_id, limit: 1).last
    end

    def find(chat_id, evidence_id)
      recent(chat_id, limit: 500).find do |record|
        record["evidence_id"] == evidence_id.to_s
      end
    end

    private

    def path_for(chat_id)
      File.join(@root, "#{safe_id(chat_id)}.jsonl")
    end

    def safe_id(value)
      value.to_s.gsub(/[^a-zA-Z0-9_.-]/, "_")
    end

    def normalize_limit(value)
      number = value.to_i
      number.positive? ? [number, 500].min : 5
    end

    def parse_line(line)
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end

    def stringify_keys(hash)
      hash.each_with_object({}) do |(key, value), output|
        output[key.to_s] = value
      end
    end
  end
end
