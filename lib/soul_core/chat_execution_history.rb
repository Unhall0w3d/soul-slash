
# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "time"

module SoulCore
  class ChatExecutionHistory
    DEFAULT_PATH = File.join("Soul", "runtime", "executions", "chat_executions.jsonl")
    DEFAULT_EXPORT_DIR = File.join("Soul", "runtime", "exports", "execution_history")

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
      { "path" => relative_path(@path), "count" => entries.length, "shown" => rows.length, "entries" => rows }
    end

    def export(format: "json", limit: nil, export_dir: DEFAULT_EXPORT_DIR)
      rows = entries(limit: limit)
      dir = File.expand_path(export_dir, @root)
      FileUtils.mkdir_p(dir)
      timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")

      case format.to_s
      when "json"
        target = File.join(dir, "chat_executions_#{timestamp}.json")
        File.write(target, JSON.pretty_generate({ "exported_at" => Time.now.iso8601, "entries" => rows }) + "\n")
      when "jsonl"
        target = File.join(dir, "chat_executions_#{timestamp}.jsonl")
        File.open(target, "w") { |file| rows.each { |entry| file.puts(JSON.generate(entry)) } }
      else
        raise ArgumentError, "Unsupported export format: #{format}"
      end

      { "ok" => true, "path" => relative_path(target), "format" => format.to_s, "count" => rows.length }
    end

    def clear(confirm: false)
      unless confirm
        return {
          "ok" => false,
          "status" => "blocked",
          "message" => "History clear requires confirm: true.",
          "path" => relative_path(@path),
          "deleted" => false
        }
      end

      existed = File.exist?(@path)
      FileUtils.rm_f(@path)
      {
        "ok" => true,
        "status" => "cleared",
        "message" => existed ? "Execution history cleared." : "Execution history file did not exist.",
        "path" => relative_path(@path),
        "deleted" => existed
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

    def relative_path(target)
      Pathname.new(target).relative_path_from(Pathname.new(@root)).to_s
    rescue StandardError
      target
    end
  end
end
