# frozen_string_literal: true
require "json"
module SoulCore
  class ExecutionAdapterRegistry
    Adapter = Struct.new(:skill_id, :label, :risk, :enabled, :kind, :command, :internal_handler, :description, :notes, keyword_init: true) do
      def enabled?
        enabled == true
      end
      def command?
        kind == "command"
      end
      def internal?
        kind == "internal"
      end
      def to_h
        {
          "skill_id" => skill_id, "label" => label, "risk" => risk, "enabled" => enabled?,
          "kind" => kind, "command" => command, "internal_handler" => internal_handler,
          "description" => description, "notes" => notes
        }.reject { |_key, value| value.nil? }
      end
    end
    ADAPTERS = [
      Adapter.new(skill_id: "assistant-skill-catalog", label: "Assistant skill catalog", risk: "read_only", enabled: true, kind: "command", command: ["ruby", "bin/soul", "assess", "assistant-skill-catalog", "--json"], description: "Lists assistant-facing skills."),
      Adapter.new(skill_id: "system.status", label: "System status", risk: "read_only", enabled: true, kind: "command", command: ["ruby", "bin/soul", "assess", "doctor-surface", "--json"], description: "Runs the read-only doctor surface."),
      Adapter.new(skill_id: "execution.history.summary", label: "Execution history summary", risk: "read_only", enabled: true, kind: "internal", internal_handler: "execution_history_summary", description: "Summarizes local execution history."),
      Adapter.new(skill_id: "downloads.inspect", label: "Downloads inspection", risk: "read_only", enabled: true, kind: "internal", internal_handler: "downloads_inspect", description: "Summarizes local Downloads metadata without printing filenames.", notes: "Read-only local adapter."),
      Adapter.new(skill_id: "weather.report", label: "Weather report", risk: "read_only", enabled: false, kind: "missing", description: "Weather through configured provider.", notes: "Needs provider/location design."),
      Adapter.new(skill_id: "cloud.providers.list", label: "Cloud provider list", risk: "network_or_provider_check", enabled: false, kind: "missing", description: "List configured providers.", notes: "Boundary design pending."),
      Adapter.new(skill_id: "youtube.song_search", label: "YouTube song search", risk: "read_only", enabled: false, kind: "missing", description: "Resolve song/video lookup.", notes: "Needs network/provider adapter.")
    ].freeze
    def adapters
      ADAPTERS
    end
    def find(skill_id)
      adapters.find { |adapter| adapter.skill_id == skill_id.to_s }
    end
    def enabled
      adapters.select(&:enabled?)
    end
    def blocked
      adapters.reject(&:enabled?)
    end
    def enabled?(skill_id)
      find(skill_id)&.enabled? == true
    end
    def safe_read_only?(skill_id, risk)
      adapter = find(skill_id)
      adapter && adapter.risk == "read_only" && risk == "read_only"
    end
    def command_for(skill_id)
      find(skill_id)&.command
    end
    def internal_handler_for(skill_id)
      find(skill_id)&.internal_handler
    end
    def summary
      {"adapter_count"=>adapters.length,"enabled_count"=>enabled.length,"blocked_count"=>blocked.length,"enabled_skill_ids"=>enabled.map(&:skill_id),"blocked_skill_ids"=>blocked.map(&:skill_id),"adapters"=>adapters.map(&:to_h)}
    end
    def render
      lines=[]
      lines << "Soul Execution Adapter Registry"
      lines << "Adapters: #{adapters.length}"
      lines << "Enabled: #{enabled.length}"
      lines << "Blocked/missing: #{blocked.length}"
      lines << ""
      lines << "Enabled adapters"
      enabled.each do |adapter|
        lines << "- #{adapter.skill_id}: #{adapter.label}"
        lines << "  kind: #{adapter.kind}"
        lines << "  risk: #{adapter.risk}"
        lines << "  description: #{adapter.description}"
      end
      lines << ""
      lines << "Blocked/missing adapters"
      blocked.each do |adapter|
        lines << "- #{adapter.skill_id}: #{adapter.label}"
        lines << "  kind: #{adapter.kind}"
        lines << "  risk: #{adapter.risk}"
        lines << "  notes: #{adapter.notes}"
      end
      lines.join("\n")
    end
  end
end
