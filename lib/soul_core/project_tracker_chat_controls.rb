# frozen_string_literal: true

require_relative "project_tracker_service"

module SoulCore
  class ProjectTrackerChatControls
    READ_PATTERNS = [
      /\A\s*(?:show|list|open)\s+(?:the\s+)?(?:project\s+timeline|implementation\s+tracker)\s*[?.!]*\z/i,
      /\A\s*what(?:'s|\s+is)\s+(?:next|on\s+the\s+project\s+timeline)\s*[?.!]*\z/i
    ].freeze
    STATUS_PATTERN = /\A\s*(?:mark|set)\s+timeline\s+item\s+(.+?)\s+(?:as|to)\s+(planned|in[\s_-]*progress|blocked|needs[\s_-]*review|validated|done|deferred)\s*[?.!]*\z/i
    INSPECT_PATTERN = /\A\s*(?:show|inspect)\s+(?:project\s+)?timeline\s+item\s+(.+?)\s*[?.!]*\z/i
    DETAIL_PATTERN = /\A\s*update\s+timeline\s+item\s+(.+?)\s+(notes?|implementation|technologies|interfaces|commands|references)\s*:\s*(.+)\z/im
    ADD_PATTERN = /\A\s*add\s+timeline\s+item\s*:\s*(.+)\z/im

    def initialize(root: Dir.pwd, service: nil)
      @service = service || ProjectTrackerService.new(root: root)
    end

    def match?(message)
      text = message.to_s
      READ_PATTERNS.any? { |pattern| text.match?(pattern) } ||
        text.match?(INSPECT_PATTERN) || text.match?(STATUS_PATTERN) || text.match?(DETAIL_PATTERN) || text.match?(ADD_PATTERN)
    end

    def respond(message, chat_id: nil)
      text = message.to_s.strip
      return render_snapshot(@service.snapshot.fetch("data")) if READ_PATTERNS.any? { |pattern| text.match?(pattern) }
      inspect_match = INSPECT_PATTERN.match(text)
      return inspect_item(inspect_match[1]) if inspect_match
      status_match = STATUS_PATTERN.match(text)
      return change_status(status_match[1], status_match[2]) if status_match
      detail_match = DETAIL_PATTERN.match(text)
      return change_detail(detail_match[1], detail_match[2], detail_match[3]) if detail_match
      add_match = ADD_PATTERN.match(text)
      return add_item(add_match[1]) if add_match

      help
    end

    private

    def render_snapshot(state)
      items = state.fetch("items")
      lines = ["Project Timeline · revision #{state.fetch('revision')}", ""]
      %w[now next later backlog].each do |horizon|
        records = items.select { |item| item["horizon"] == horizon && !%w[done validated].include?(item["status"]) }
        lines << "#{horizon.capitalize} (#{records.length})"
        if records.empty?
          lines << "- none"
        else
          records.sort_by { |item| [priority_order(item["priority"]), item["title"]] }.each do |item|
            lines << "- #{item['title']} [#{item['status']}]"
            lines << "  #{item['item_id']} · #{item['area']} · #{item['priority']}"
          end
        end
        lines << ""
      end
      implemented = items.select { |item| %w[done validated].include?(item["status"]) }
      lines << "Implemented inventory (#{implemented.length})"
      implemented.sort_by { |item| [item["area"], item["title"]] }.each do |item|
        lines << "- #{item['title']} [#{item['status']}]"
        lines << "  #{item['item_id']} · #{item['area']}"
      end
      lines << ""
      lines << "Changes require an explicit “timeline item” command; discussion never changes this ledger."
      lines.join("\n")
    end

    def change_status(reference, status)
      with_item(reference) do |item|
        normalized = status.downcase.gsub(/[\s-]+/, "_")
        result = @service.update(
          item_id: item.fetch("item_id"),
          expected_revision: item.fetch("revision"),
          attributes: { "status" => normalized }
        )
        render_result(result, item.fetch("title"), "status", normalized)
      end
    end

    def inspect_item(reference)
      with_item(reference) do |item|
        lines = [
          item.fetch("title"),
          "ID: #{item.fetch('item_id')}",
          "State: #{item.fetch('status')} · #{item.fetch('horizon') == 'archive' ? 'implemented inventory' : item.fetch('horizon')} · #{item.fetch('priority')}",
          "Area: #{item.fetch('area')}",
          "",
          "Summary",
          item.fetch("summary")
        ]
        {
          "Implementation" => item["implementation"],
          "Models, languages, and technologies" => item["technologies"],
          "Interfaces" => item["interfaces"],
          "Commands and syntax" => item["commands"],
          "References" => item["references"],
          "Acceptance" => item["acceptance"],
          "Notes" => item["notes"],
          "Source" => item["source"]
        }.each do |heading, value|
          next if value.to_s.strip.empty?

          lines.concat(["", heading, value.to_s])
        end
        lines << ""
        lines << "Revision: #{item.fetch('revision')}"
        lines.join("\n")
      end
    end

    def change_detail(reference, field, value)
      with_item(reference) do |item|
        normalized_field = field.downcase.start_with?("note") ? "notes" : field.downcase
        result = @service.update(
          item_id: item.fetch("item_id"),
          expected_revision: item.fetch("revision"),
          attributes: { normalized_field => value.to_s.strip }
        )
        render_result(result, item.fetch("title"), normalized_field, "updated")
      end
    end

    def add_item(payload)
      values = payload.split("|", -1).map(&:strip)
      return add_help unless values.length == 8

      keys = %w[title area horizon status priority summary acceptance source]
      result = @service.create(attributes: keys.zip(values).to_h.merge("notes" => ""))
      item = result.dig("data", "item")
      return "Timeline item was not created: #{result['message']}" unless result["ok"]

      [
        "Timeline item created.",
        "Item: #{item['title']}",
        "ID: #{item['item_id']}",
        "State: #{item['status']} · #{item['horizon']} · #{item['priority']}",
        "Lifecycle: complete"
      ].join("\n")
    rescue ArgumentError => error
      "Timeline item was not created: #{error.message}"
    end

    def with_item(reference)
      match = @service.find(reference.to_s.strip)
      case match.fetch("status")
      when "found"
        yield match.fetch("item")
      when "ambiguous"
        ids = match.fetch("items").map { |item| "#{item['item_id']} (#{item['title']})" }.join(", ")
        "That timeline reference is ambiguous. Use one exact ID: #{ids}"
      else
        "I could not find that timeline item. Say “show project timeline” to see exact IDs."
      end
    end

    def render_result(result, title, field, value)
      return "Timeline item was not changed: #{result['message']}" unless result["ok"]

      item = result.dig("data", "item")
      [
        "Timeline item updated.",
        "Item: #{title}",
        "#{field.capitalize}: #{value}",
        "Revision: #{item['revision']}",
        "Lifecycle: complete"
      ].join("\n")
    end

    def priority_order(priority)
      { "high" => 0, "medium" => 1, "low" => 2 }.fetch(priority, 3)
    end

    def add_help
      "Use: add timeline item: Title | Area | now/next/later/backlog | planned/in_progress/blocked/needs_review/validated/done/deferred | high/medium/low | Summary | Acceptance | Source"
    end

    def help
      [
        "Project Timeline controls",
        "- show project timeline",
        "- show timeline item <ID or exact title>",
        "- mark timeline item <ID or exact title> as <status>",
        "- update timeline item <ID or exact title> <notes|implementation|technologies|interfaces|commands|references>: <text>",
        "- #{add_help.sub('Use: ', '')}"
      ].join("\n")
    end
  end
end
