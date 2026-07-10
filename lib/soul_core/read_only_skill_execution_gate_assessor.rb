# frozen_string_literal: true
require "json"
require "time"
require "tmpdir"
require_relative "read_only_skill_execution_gate"
module SoulCore
  class ReadOnlySkillExecutionGateAssessor
    def initialize(root: Dir.pwd); @root=File.expand_path(root); end
    def assess
      Dir.mktmpdir("soul-downloads-cleanup-preview-phase57-") do |dir|
        history=ChatExecutionHistory.new(root:@root, path:File.join(dir,"history.jsonl")); gate=ReadOnlySkillExecutionGate.new(root:@root, history:history)
        samples={"clean up downloads"=>["downloads.cleanup_plan",true,nil],"inspect my downloads"=>["downloads.inspect",true,nil],"move approved downloads to trash"=>["downloads.move_to_trash",false,"owner_confirmation_required"]}.map do |msg,(skill,executed,blocker)|
          r=gate.evaluate(msg, execute:true); parsed=JSON.parse(r.stdout) rescue {}; matched=(r.skill_id==skill && r.executed==executed && (blocker.nil? || r.blocked_by.include?(blocker))); matched &&= parsed["action"]=="preview_only" && parsed["mutation"]=="none" if skill=="downloads.cleanup_plan"; {"message"=>msg,"actual"=>{"skill_id"=>r.skill_id,"status"=>r.status,"executed"=>r.executed,"blocked_by"=>r.blocked_by},"cleanup_payload"=>skill=="downloads.cleanup_plan" ? parsed : nil,"matched"=>matched}
        end
        blockers=[]; blockers << "One or more phase 57 gate samples failed" unless samples.all?{|s| s["matched"]}
        {"ok"=>blockers.empty?,"assessment"=>"read_only_skill_execution_gate","phase"=>57,"generated_at"=>Time.now.iso8601,"root"=>@root,"status"=>blockers.empty? ? "ready" : "blocked","samples"=>samples,"registry"=>gate.registry.summary,"blockers"=>blockers,"verification"=>{"downloads_cleanup_plan_executes"=>samples.any?{|s| s.dig("actual","skill_id")=="downloads.cleanup_plan" && s.dig("actual","executed")==true},"cleanup_plan_preview_only"=>samples.any?{|s| s["cleanup_payload"].is_a?(Hash) && s.dig("cleanup_payload","action")=="preview_only"},"cleanup_plan_no_mutation"=>samples.any?{|s| s["cleanup_payload"].is_a?(Hash) && s.dig("cleanup_payload","mutation")=="none"},"approval_required_blocked"=>samples.any?{|s| s.dig("actual","blocked_by").include?("owner_confirmation_required")},"enabled_adapter_count"=>gate.registry.summary["enabled_count"]}}
      end
    end
    def render(report); (["Soul Downloads Cleanup Preview Adapter Assessment","Generated: #{report['generated_at']}","Status: #{report['status']}","Enabled adapters: #{report.dig('registry','enabled_count')}","","Blockers:"] + (report["blockers"].empty? ? ["- None"] : report["blockers"].map{|b| "- #{b}"})).join("
"); end
  end
end
