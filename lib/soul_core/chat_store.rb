# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"

module SoulCore
  class ChatStore
    DEFAULT_ROOT = "Soul/runtime/chats"

    attr_reader :project_root, :root

    def initialize(root: Dir.pwd, chat_root: DEFAULT_ROOT)
      @project_root = File.expand_path(root)
      @root = File.join(@project_root, chat_root)
      FileUtils.mkdir_p(@root)
    end

    def create_chat(initial_title: nil)
      now = Time.now.iso8601
      id = "chat_#{now.gsub(/[^0-9]/, '')}_#{SecureRandom.hex(3)}"
      record = {
        "id" => id,
        "title" => initial_title || "New Soul chat",
        "created_at" => now,
        "updated_at" => now,
        "pinned" => false,
        "pin_order" => nil,
        "archived" => false,
        "summary" => "",
        "metadata" => { "schema" => "phase41_jsonl" }
      }
      File.write(metadata_path(id), "#{JSON.pretty_generate(record)}\n")
      File.write(messages_path(id), "")
      record
    end

    def chat(id)
      path = metadata_path(id)
      return nil unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      nil
    end

    def list_chats
      Dir.glob(File.join(@root, "*.json"))
        .map { |path| JSON.parse(File.read(path)) rescue nil }
        .compact
        .sort_by { |item| item["updated_at"].to_s }
        .reverse
    end

    def add_message(chat_id, role:, content:, metadata: {})
      chat_record = chat(chat_id)
      raise ArgumentError, "Unknown chat id: #{chat_id}" unless chat_record

      now = Time.now.iso8601
      message = {
        "id" => "msg_#{now.gsub(/[^0-9]/, '')}_#{SecureRandom.hex(3)}",
        "chat_id" => chat_id,
        "role" => role.to_s,
        "content" => content.to_s,
        "created_at" => now,
        "metadata" => metadata || {}
      }
      File.open(messages_path(chat_id), "a") { |file| file.puts(JSON.generate(message)) }

      chat_record["updated_at"] = now
      if chat_record["title"].to_s == "New Soul chat" && role.to_s == "user" && !content.to_s.strip.empty?
        chat_record["title"] = title_from(content)
      end
      File.write(metadata_path(chat_id), "#{JSON.pretty_generate(chat_record)}\n")
      message
    end

    def messages(chat_id)
      path = messages_path(chat_id)
      return [] unless File.exist?(path)

      File.readlines(path).map { |line| JSON.parse(line) rescue nil }.compact
    end

    def search(query)
      needle = query.to_s.downcase
      return [] if needle.empty?

      list_chats.select do |chat_record|
        chat_record.to_json.downcase.include?(needle) ||
          messages(chat_record.fetch("id")).any? { |message| message.to_json.downcase.include?(needle) }
      end
    end

    def pin(chat_id)
      update_flag(chat_id, "pinned", true)
    end

    def unpin(chat_id)
      update_flag(chat_id, "pinned", false)
    end

    private

    def metadata_path(id)
      safe = safe_id(id)
      File.join(@root, "#{safe}.json")
    end

    def messages_path(id)
      safe = safe_id(id)
      File.join(@root, "#{safe}.jsonl")
    end

    def safe_id(id)
      id.to_s.gsub(/[^a-zA-Z0-9_.-]/, "_")
    end

    def title_from(content)
      text = content.to_s.strip.gsub(/\s+/, " ")
      text = text[0, 60]
      text.empty? ? "New Soul chat" : text
    end

    def update_flag(chat_id, key, value)
      chat_record = chat(chat_id)
      raise ArgumentError, "Unknown chat id: #{chat_id}" unless chat_record

      chat_record[key] = value
      chat_record["updated_at"] = Time.now.iso8601
      File.write(metadata_path(chat_id), "#{JSON.pretty_generate(chat_record)}\n")
      chat_record
    end
  end
end
