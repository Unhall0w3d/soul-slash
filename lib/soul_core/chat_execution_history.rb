
# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module SoulCore
  class ChatExecutionHistory
    DEFAULT_PATH = File.join("Soul", "runtime", "executions", "chat_executions.jsonl")

    def initialize(root: Dir.pwd, path: DEFAULT_PATH)
      @root = File.expand_path(root)
      @path = File.expand_path(path, @root)
    end

    attr_reader :path

    def record(result, message:, source: "chat")
      FileUtils.mkdir_p(File.dirname(@path))

      entry = {
        "timestamp" => Time.now.iso8601,
        "source" => source,
        "message" => message.to_s,
        "skill_id" => result.skill_id,
        "status" => result.status,
        "ok" => result.ok,
        "executed" => result.executed,
        "risk" => result.risk,
        "confirmation_required" => result.confirmation_required,
        "exit_status" => result.exit_status,
        "blocked_by" => Array(result.blocked_by)
      }

      File.open(@path, "a") { |file| file.puts(JSON.generate(entry)) }
      entry
    end

    def entries(limit: nil)
      return [] unless File.exist?(@path)

      lines = File.readlines(@path, chomp: true)
      selected = limit ? lines.last(limit) : lines
      selected.filter_map do |line|
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end

    def summary(limit: 10)
      rows = entries(limit: limit)
      {
        "path" => relative_path,
        "count" => entries.length,
        "shown" => rows.length,
        "entries" => rows
      }
    end

    def render(limit: 10)
      data = summary(limit: limit)
      lines = []
      lines << "Soul Chat Execution History"
      lines << "Path: #{data['path']}"
      lines << "Total entries: #{data['count']}"
      lines << "Shown: #{data['shown']}"
      lines << ""

      if data["entries"].empty?
        lines << "No execution history recorded yet."
      else
        data["entries"].each do |entry|
          lines << "- #{entry['timestamp']} #{entry['skill_id'] || 'none'}"
          lines << "  status: #{entry['status']}"
          lines << "  executed: #{entry['executed']}"
          lines << "  exit_status: #{entry['exit_status'] || 'none'}"
          lines << "  blocked_by: #{Array(entry['blocked_by']).empty? ? 'none' : Array(entry['blocked_by']).join(', ')}"
        end
      end

      lines.join("\n")
    end

    private

    def relative_path
      Pathname.new(@path).relative_path_from(Pathname.new(@root)).to_s
    rescue StandardError
      @path
    end
  end
end
