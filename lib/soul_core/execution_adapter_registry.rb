# frozen_string_literal: true
require "json"
module SoulCore
  class ExecutionAdapterRegistry
    Adapter = Struct.new(:skill_id,:label,:risk,:enabled,:kind,:command,:internal_handler,:description,:notes, keyword_init: true) do
      def enabled?; enabled == true; end
      def command?; kind == "command"; end
      def internal?; kind == "internal"; end
      def to_h
        {"skill_id"=>skill_id,"label"=>label,"risk"=>risk,"enabled"=>enabled?,"kind"=>kind,"command"=>command,"internal_handler"=>internal_handler,"description"=>description,"notes"=>notes}.reject{|_,v| v.nil?}
      end
    end
    ADAPTERS = [
      Adapter.new(skill_id:"assistant-skill-catalog", label:"Assistant skill catalog", risk:"read_only", enabled:true, kind:"command", command:["ruby","bin/soul","assess","assistant-skill-catalog","--json"], description:"Lists assistant-facing skills."),
      Adapter.new(skill_id:"system.status", label:"System status", risk:"read_only", enabled:true, kind:"command", command:["ruby","bin/soul","assess","doctor-surface","--json"], description:"Runs the read-only doctor surface."),
      Adapter.new(skill_id:"execution.history.summary", label:"Execution history summary", risk:"read_only", enabled:true, kind:"internal", internal_handler:"execution_history_summary", description:"Summarizes local execution history."),
      Adapter.new(skill_id:"downloads.inspect", label:"Downloads inspection", risk:"read_only", enabled:true, kind:"internal", internal_handler:"downloads_inspect", description:"Summarizes Downloads metadata without filenames."),
      Adapter.new(skill_id:"downloads.cleanup_plan", label:"Downloads cleanup preview", risk:"review_only", enabled:true, kind:"internal", internal_handler:"downloads_cleanup_plan", description:"Builds a non-mutating cleanup preview.", notes:"Preview-only. No files are moved or deleted."),
      Adapter.new(skill_id:"weather.report", label:"Weather report", risk:"read_only", enabled:false, kind:"missing", description:"Weather through configured provider.", notes:"Needs provider/location design."),
      Adapter.new(skill_id:"cloud.providers.list", label:"Cloud provider list", risk:"network_or_provider_check", enabled:false, kind:"missing", description:"List configured providers.", notes:"Boundary design pending."),
      Adapter.new(skill_id:"youtube.song_search", label:"YouTube song search", risk:"read_only", enabled:false, kind:"missing", description:"Resolve song/video lookup.", notes:"Needs network/provider adapter.")
    ].freeze
    def adapters; ADAPTERS; end
    def find(skill_id); adapters.find{|a| a.skill_id == skill_id.to_s}; end
    def enabled; adapters.select(&:enabled?); end
    def blocked; adapters.reject(&:enabled?); end
    def enabled?(skill_id); find(skill_id)&.enabled? == true; end
    def safe_non_mutating?(skill_id, risk); (a=find(skill_id)) && a.risk == risk && %w[read_only review_only].include?(risk); end
    alias safe_read_only? safe_non_mutating?
    def command_for(skill_id); find(skill_id)&.command; end
    def internal_handler_for(skill_id); find(skill_id)&.internal_handler; end
    def summary
      {"adapter_count"=>adapters.length,"enabled_count"=>enabled.length,"blocked_count"=>blocked.length,"enabled_skill_ids"=>enabled.map(&:skill_id),"blocked_skill_ids"=>blocked.map(&:skill_id),"adapters"=>adapters.map(&:to_h)}
    end
    def render
      lines=["Soul Execution Adapter Registry","Adapters: #{adapters.length}","Enabled: #{enabled.length}","Blocked/missing: #{blocked.length}","","Enabled adapters"]
      enabled.each{|a| lines << "- #{a.skill_id}: #{a.label}" << "  kind: #{a.kind}" << "  risk: #{a.risk}" << "  description: #{a.description}"}
      lines << "" << "Blocked/missing adapters"
      blocked.each{|a| lines << "- #{a.skill_id}: #{a.label}" << "  kind: #{a.kind}" << "  risk: #{a.risk}" << "  notes: #{a.notes}"}
      lines.join("
")
    end
  end
end
