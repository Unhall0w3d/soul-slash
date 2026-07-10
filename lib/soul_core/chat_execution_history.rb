
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

    def entries(limit: nil, filters: {})
      rows = all_entries
      rows = filter_entries(rows, filters)
      limit ? rows.last(limit) : rows
    end

    def summary(limit: 10, filters: {})
      rows = entries(limit: limit, filters: filters)
      total = filter_entries(all_entries, filters).length
      {
        "path" => relative_path(@path),
        "count" => total,
        "shown" => rows.length,
        "filters" => normalize_filters(filters),
        "entries" => rows
      }
    end

    def export(format: "json", limit: nil, export_dir: DEFAULT_EXPORT_DIR, filters: {})
      rows = entries(limit: limit, filters: filters)
      dir = File.expand_path(export_dir, @root)
      FileUtils.mkdir_p(dir)
      timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")

      case format.to_s
      when "json"
        target = File.join(dir, "chat_executions_#{timestamp}.json")
        File.write(target, JSON.pretty_generate({ "exported_at" => Time.now.iso8601, "filters" => normalize_filters(filters), "entries" => rows }) + "\n")
      when "jsonl"
        target = File.join(dir, "chat_executions_#{timestamp}.jsonl")
        File.open(target, "w") { |file| rows.each { |entry| file.puts(JSON.generate(entry)) } }
      else
        raise ArgumentError, "Unsupported export format: #{format}"
      end

      { "ok" => true, "path" => relative_path(target), "format" => format.to_s, "count" => rows.length, "filters" => normalize_filters(filters) }
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

    def prune(keep:, confirm: false, export_before_delete: true, export_dir: DEFAULT_EXPORT_DIR)
      keep_count = Integer(keep)
      raise ArgumentError, "keep must be zero or greater" if keep_count.negative?

      rows = all_entries
      remove_count = [rows.length - keep_count, 0].max
      kept = keep_count.zero? ? [] : rows.last(keep_count)
      removed = remove_count.zero? ? [] : rows.first(remove_count)

      preview = {
        "ok" => true,
        "status" => "preview",
        "path" => relative_path(@path),
        "total_before" => rows.length,
        "keep" => keep_count,
        "would_remove" => remove_count,
        "would_keep" => kept.length,
        "confirm_required" => true,
        "export_before_delete" => export_before_delete,
        "export" => nil,
        "pruned" => false
      }

      return preview unless confirm

      export_result = nil
      if export_before_delete && removed.any?
        export_result = export_rows(removed, format: "json", export_dir: export_dir, prefix: "chat_executions_pruned")
      end

      FileUtils.mkdir_p(File.dirname(@path))
      if kept.empty?
        FileUtils.rm_f(@path)
      else
        File.open(@path, "w") { |file| kept.each { |entry| file.puts(JSON.generate(entry)) } }
      end

      preview.merge(
        "status" => "pruned",
        "total_after" => kept.length,
        "export" => export_result,
        "pruned" => true
      )
    end

    def render(limit: 10, filters: {})
      data = summary(limit: limit, filters: filters)
      lines = []
      lines << "Soul Chat Execution History"
      lines << "Path: #{data['path']}"
      lines << "Total matching entries: #{data['count']}"
      lines << "Shown: #{data['shown']}"
      unless data["filters"].empty?
        lines << "Filters: #{data['filters'].map { |key, value| "#{key}=#{value}" }.join(', ')}"
      end
      lines << ""

      if data["entries"].empty?
        lines << "No execution history matched."
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

    def self.filters_from_text(text)
      lower = text.to_s.downcase
      filters = {}

      if lower =~ /\bskill(?:_id)?[:= ]+([a-z0-9_.-]+)\b/
        filters["skill_id"] = Regexp.last_match(1)
      elsif lower =~ /\b(system\.status|assistant-skill-catalog|downloads\.[a-z0-9_.-]+|weather\.report|cloud\.providers\.list|youtube\.song_search)\b/
        filters["skill_id"] = Regexp.last_match(1)
      end

      if lower =~ /\bstatus[:= ]+(executed|blocked|ready|failed)\b/
        filters["status"] = Regexp.last_match(1)
      elsif lower.match?(/\bblocked\b/)
        filters["status"] = "blocked"
      elsif lower.match?(/\bfailed\b/)
        filters["status"] = "failed"
      end

      if lower.match?(/\bexecuted only\b|\bonly executed\b|\bexecuted entries\b|\bexecuted history\b/)
        filters["executed"] = true
      elsif lower.match?(/\bnot executed\b|\bunexecuted\b|\bblocked only\b/)
        filters["executed"] = false
      end

      filters
    end

    def self.keep_count_from_text(text, default: 10)
      lower = text.to_s.downcase
      return Regexp.last_match(1).to_i if lower =~ /\bkeep[:= ]+(\d+)\b/
      return Regexp.last_match(1).to_i if lower =~ /\blast[:= ]+(\d+)\b/
      return Regexp.last_match(1).to_i if lower =~ /\bkeep\s+last\s+(\d+)\b/
      return Regexp.last_match(1).to_i if lower =~ /\blast\s+(\d+)\b/

      default
    end

    private

    def all_entries
      return [] unless File.exist?(@path)

      File.readlines(@path, chomp: true).filter_map do |line|
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end

    def export_rows(rows, format:, export_dir:, prefix:)
      dir = File.expand_path(export_dir, @root)
      FileUtils.mkdir_p(dir)
      timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
      target = File.join(dir, "#{prefix}_#{timestamp}.#{format}")

      case format.to_s
      when "json"
        File.write(target, JSON.pretty_generate({ "exported_at" => Time.now.iso8601, "entries" => rows }) + "\n")
      when "jsonl"
        File.open(target, "w") { |file| rows.each { |entry| file.puts(JSON.generate(entry)) } }
      else
        raise ArgumentError, "Unsupported export format: #{format}"
      end

      { "ok" => true, "path" => relative_path(target), "format" => format.to_s, "count" => rows.length }
    end

    def filter_entries(rows, filters)
      normalized = normalize_filters(filters)
      rows.select do |entry|
        normalized.all? do |key, value|
          case key
          when "skill_id", "status", "source", "risk"
            entry[key].to_s == value.to_s
          when "executed", "ok", "confirmation_required"
            entry[key] == value
          else
            true
          end
        end
      end
    end

    def normalize_filters(filters)
      filters.each_with_object({}) do |(key, value), out|
        next if value.nil? || value == ""

        normalized_key = key.to_s
        normalized_value =
          if %w[executed ok confirmation_required].include?(normalized_key)
            value == true || value.to_s == "true"
          else
            value.to_s
          end
        out[normalized_key] = normalized_value
      end
    end

    def relative_path(target)
      Pathname.new(target).relative_path_from(Pathname.new(@root)).to_s
    rescue StandardError
      target
    end
  end
end
