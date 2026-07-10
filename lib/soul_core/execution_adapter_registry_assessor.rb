# frozen_string_literal: true
require "time"
require_relative "execution_adapter_registry"
module SoulCore
  class ExecutionAdapterRegistryAssessor
    def initialize(root: Dir.pwd); @root=File.expand_path(root); @registry=ExecutionAdapterRegistry.new; end
    def assess
      data=@registry.summary; blockers=[]
      blockers << "Expected at least eight registered adapters" unless data["adapter_count"].to_i >= 8
      blockers << "Expected exactly five enabled adapters" unless data["enabled_count"] == 5
      blockers << "Expected downloads.cleanup_plan enabled" unless @registry.enabled?("downloads.cleanup_plan")
      blockers << "Expected downloads.cleanup_plan internal handler" unless @registry.internal_handler_for("downloads.cleanup_plan") == "downloads_cleanup_plan"
      blockers << "Expected downloads.cleanup_plan risk review_only" unless @registry.find("downloads.cleanup_plan")&.risk == "review_only"
      {"ok"=>blockers.empty?,"assessment"=>"execution_adapter_registry","phase"=>57,"generated_at"=>Time.now.iso8601,"root"=>@root,"status"=>blockers.empty? ? "ready" : "blocked","registry"=>data,"blockers"=>blockers,"verification"=>{"has_five_enabled_adapters"=>data["enabled_count"]==5,"downloads_cleanup_plan_enabled"=>@registry.enabled?("downloads.cleanup_plan"),"downloads_cleanup_plan_has_internal_handler"=>@registry.internal_handler_for("downloads.cleanup_plan")=="downloads_cleanup_plan","downloads_cleanup_plan_review_only"=>@registry.find("downloads.cleanup_plan")&.risk=="review_only","has_blocked_adapters"=>data["blocked_count"].to_i>=1}}
    end
    def render(report); [@registry.render,"","Assessment status: #{report['status']}","Blockers:",*(report["blockers"].empty? ? ["- None"] : report["blockers"].map{|b| "- #{b}"})].join("
"); end
  end
end
