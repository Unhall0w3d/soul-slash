# frozen_string_literal: true
require "json"
require "time"
require_relative "execution_adapter_registry"
module SoulCore
  class ExecutionAdapterRegistryAssessor
    def initialize(root:Dir.pwd); @root=File.expand_path(root); @registry=ExecutionAdapterRegistry.new end
    def assess
      data=@registry.summary; blockers=[]
      blockers << "Expected exactly four enabled adapters" unless data["enabled_count"]==4
      blockers << "Expected downloads.inspect enabled" unless @registry.enabled?("downloads.inspect")
      blockers << "Expected downloads.inspect internal handler" unless @registry.internal_handler_for("downloads.inspect")=="downloads_inspect"
      {"ok"=>blockers.empty?,"assessment"=>"execution_adapter_registry","phase"=>56,"generated_at"=>Time.now.iso8601,"root"=>@root,"status"=>blockers.empty? ? "ready":"blocked","registry"=>data,"blockers"=>blockers,"verification"=>{"has_four_enabled_adapters"=>data["enabled_count"]==4,"downloads_inspect_enabled"=>@registry.enabled?("downloads.inspect"),"downloads_inspect_has_internal_handler"=>@registry.internal_handler_for("downloads.inspect")=="downloads_inspect","has_blocked_adapters"=>data["blocked_count"].to_i>=1}}
    end
    def render(report); [@registry.render,"","Assessment status: #{report['status']}","Blockers:",*(report["blockers"].empty? ? ["- None"] : report["blockers"].map{|b|"- #{b}"})].join("
") end
  end
end
