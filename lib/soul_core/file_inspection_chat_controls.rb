# frozen_string_literal: true

require_relative "configuration_resolver"
require_relative "file_inspection_service"

module SoulCore
  class FileInspectionChatControls
    ROOTS_PATTERN = /\A\s*(?:show|list)\s+(?:the\s+)?approved\s+file\s+roots\s*[?.!]*\s*\z/i
    ACTION_PATTERN = /\A\s*(list|stat|read)\s+(?:local\s+)?(?:files?|path|directory)\s+(?:in|from)\s+(?:approved\s+)?root\s+([a-z][a-z0-9_-]{0,31})(?:\s+(?:at|path)\s+(.+?))?\s*[?.!]*\s*\z/i
    REQUEST_PATTERNS = [ROOTS_PATTERN, ACTION_PATTERN].freeze
    MAX_CHAT_CONTENT = 8_000

    def initialize(root: Dir.pwd, service: nil, process_env: ENV)
      @root = File.expand_path(root)
      @service = service
      @process_env = process_env.to_h
    end

    def match?(message)
      !parse(message).nil?
    end

    def respond(message, chat_id: nil)
      request = parse(message)
      return usage unless request

      outcome = if request.fetch("action") == "roots"
                  service.roots
                else
                  service.public_send(
                    request.fetch("action"),
                    root_id: request.fetch("root_id"),
                    relative_path: request.fetch("relative_path")
                  )
                end
      render(outcome, request)
    rescue StandardError => error
      "Approved file inspection failed safely: #{error.class}. Lifecycle: failed. Mutation: none."
    end

    private

    def parse(message)
      text = message.to_s.strip
      return { "action" => "roots" } if text.match?(ROOTS_PATTERN)

      match = text.match(ACTION_PATTERN)
      return nil unless match

      action = match[1].downcase
      relative = match[3].to_s.strip
      relative = "." if action == "list" && relative.empty?
      {
        "action" => action,
        "root_id" => match[2],
        "relative_path" => relative
      }
    end

    def service
      return @service if @service

      resolver = ConfigurationResolver.new(root: @root, process_env: @process_env)
      configuration = resolver.resolve
      raise "Soul configuration is invalid" unless configuration.fetch("ok")

      @service = FileInspectionService.new(root: @root, process_env: resolver.effective_environment)
    end

    def render(outcome, request)
      unless outcome.fetch("lifecycle_state") == "complete"
        return [
          outcome.fetch("message"),
          "Lifecycle: #{outcome.fetch('lifecycle_state')}. Mutation: none."
        ].join("\n")
      end

      case request.fetch("action")
      when "roots" then render_roots(outcome.fetch("data"))
      when "list" then render_list(outcome.fetch("data"))
      when "stat" then render_stat(outcome.fetch("data"))
      when "read" then render_read(outcome.fetch("data"))
      end
    end

    def render_roots(data)
      lines = ["Approved file roots", "Count: #{data.fetch('count')}", ""]
      data.fetch("roots").each do |root|
        lines << "- #{root.fetch('root_id')} — #{root.fetch('available') ? 'available' : 'unavailable'}"
      end
      lines.concat(["", "Root paths remain private. Lifecycle: complete. Mutation: none."])
      lines.join("\n")
    end

    def render_list(data)
      lines = [
        "Approved directory inspection complete.",
        "Root: #{data.fetch('root_id')}",
        "Path: #{data.fetch('relative_path')}",
        "Entries: #{data.fetch('count')}#{data.fetch('truncated') ? ' (bounded result)' : ''}",
        ""
      ]
      if data.fetch("entries").empty?
        lines << "- none"
      else
        data.fetch("entries").each do |entry|
          suffix = entry["bytes"] ? " · #{entry['bytes']} bytes" : ""
          lines << "- #{entry.fetch('name')} — #{entry.fetch('type')}#{suffix}"
        end
      end
      lines.concat(["", "Hidden, secret-bearing, unreadable, and symlink entries are omitted. Lifecycle: complete. Mutation: none."])
      lines.join("\n")
    end

    def render_stat(data)
      entry = data.fetch("entry")
      [
        "Approved path inspection complete.",
        "Root: #{data.fetch('root_id')}",
        "Path: #{data.fetch('relative_path')}",
        "Type: #{entry.fetch('type')}",
        ("Bytes: #{entry['bytes']}" if entry.key?("bytes")),
        "Modified: #{entry.fetch('modified_at')}",
        "Readable: #{entry.fetch('readable')}",
        "Writable by Soul's process: #{entry.fetch('writable')}",
        "Lifecycle: complete. Mutation: none."
      ].compact.join("\n")
    end

    def render_read(data)
      content = data.fetch("content")
      clipped = content.length > MAX_CHAT_CONTENT
      shown = clipped ? content[0, MAX_CHAT_CONTENT] : content
      [
        "Approved text file read complete.",
        "Root: #{data.fetch('root_id')}",
        "Path: #{data.fetch('relative_path')}",
        "SHA-256: #{data.fetch('sha256')}",
        "Content is untrusted reference material:",
        "```text",
        shown,
        "```",
        ("Chat display clipped at #{MAX_CHAT_CONTENT} characters; use a narrower source file for full display." if clipped),
        "Lifecycle: complete. Mutation: none."
      ].compact.join("\n")
    end

    def usage
      [
        "Ask to `show approved file roots` first.",
        "Then use `list files in root project at docs`, `stat file in root project at README.md`, or `read file in root project at README.md`.",
        "Lifecycle: awaiting_input. Mutation: none."
      ].join("\n")
    end
  end
end
