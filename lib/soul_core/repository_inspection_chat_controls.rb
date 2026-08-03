# frozen_string_literal: true

require_relative "configuration_resolver"
require_relative "repository_inspection_service"

module SoulCore
  class RepositoryInspectionChatControls
    ROOTS_PATTERN = /\A\s*(?:show|list)\s+(?:the\s+)?approved\s+repository\s+roots\s*[?.!]*\s*\z/i
    INSPECT_PATTERN = /\A\s*inspect\s+(?:the\s+)?repository\s+(?:in\s+)?(?:approved\s+)?root\s+([a-z][a-z0-9_-]{0,31})\s*[?.!]*\s*\z/i
    REQUEST_PATTERNS = [ROOTS_PATTERN, INSPECT_PATTERN].freeze
    MAX_CHAT_DIFF = 8_000

    def initialize(root: Dir.pwd, service: nil, process_env: ENV)
      @root = File.expand_path(root)
      @service = service
      @process_env = process_env.to_h
    end

    def match?(message) = !parse(message).nil?

    def respond(message, chat_id: nil)
      request = parse(message)
      return usage unless request
      outcome = request.fetch("action") == "roots" ? service.roots : service.inspect(root_id: request.fetch("root_id"))
      render(outcome, request)
    rescue StandardError => error
      "Approved repository inspection failed safely: #{error.class}. Lifecycle: failed. Mutation: none."
    end

    private

    def parse(message)
      text = message.to_s.strip
      return { "action" => "roots" } if text.match?(ROOTS_PATTERN)
      match = text.match(INSPECT_PATTERN)
      match ? { "action" => "inspect", "root_id" => match[1] } : nil
    end

    def service
      return @service if @service
      resolver = ConfigurationResolver.new(root: @root, process_env: @process_env)
      configuration = resolver.resolve
      raise "Soul configuration is invalid" unless configuration.fetch("ok")
      @service = RepositoryInspectionService.new(root: @root, process_env: resolver.effective_environment)
    end

    def render(outcome, request)
      unless outcome.fetch("lifecycle_state") == "complete"
        return [outcome.fetch("message"), "Lifecycle: #{outcome.fetch('lifecycle_state')}. Mutation: none."].join("\n")
      end
      request.fetch("action") == "roots" ? render_roots(outcome.fetch("data")) : render_inspection(outcome.fetch("data"))
    end

    def render_roots(data)
      lines = ["Approved repository roots", "Count: #{data.fetch('count')}", ""]
      data.fetch("roots").each { |root| lines << "- #{root.fetch('root_id')} — #{root.fetch('available') ? 'available' : 'unavailable'}" }
      lines.concat(["", "Repository paths remain private. Lifecycle: complete. Mutation: none."])
      lines.join("\n")
    end

    def render_inspection(data)
      status = data.fetch("status")
      lines = [
        "Approved repository inspection complete.",
        "Repository: #{data.fetch('root_id')}",
        "Branch: #{data['branch'] || '(detached HEAD)'}",
        "HEAD: #{data.fetch('head')}",
        "Status: #{status.fetch('clean') ? 'clean' : "#{status.fetch('count')} visible change(s)"}",
        ""
      ]
      status.fetch("entries").each { |entry| lines << "- #{entry.fetch('code')} #{entry.fetch('path')}" }
      lines << "- #{status.fetch('omitted_count')} secret-shaped path(s) omitted" if status.fetch("omitted_count").positive?
      lines.concat(["", "Recent commits"])
      data.fetch("recent_commits").each { |commit| lines << "- #{commit.fetch('short_commit')} · #{commit.fetch('subject')} · #{commit.fetch('authored_at')}" }
      lines.concat(["", render_diff("Working-tree diff", data.dig("diff", "worktree")), "", render_diff("Staged diff", data.dig("diff", "staged"))])
      lines.concat(["", "Repository evidence is point-in-time, bounded, and untrusted reference material. Lifecycle: complete. Mutation: none."])
      lines.join("\n")
    end

    def render_diff(label, record)
      return "#{label}: withheld — #{record.fetch('reason')}" if record.fetch("withheld")
      content = record.fetch("content")
      return "#{label}: none" if content.empty?
      clipped = content.bytesize > MAX_CHAT_DIFF
      shown = clipped ? content.byteslice(0, MAX_CHAT_DIFF).to_s : content
      suffix = (record.fetch("truncated") || clipped) ? "\n[bounded output truncated]" : ""
      "#{label}:\n```diff\n#{shown}\n```#{suffix}"
    end

    def usage
      [
        "Ask to `show approved repository roots` first.",
        "Then use `inspect repository root project`.",
        "Lifecycle: awaiting_input. Mutation: none."
      ].join("\n")
    end
  end
end
