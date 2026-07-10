# frozen_string_literal: true
require "json"
require "time"
require "tmpdir"
require_relative "read_only_skill_execution_gate"
module SoulCore
  class ReadOnlySkillExecutionGateAssessor
    def initialize(root:Dir.pwd); @root=File.expand_path(root) end
    def assess
      Dir.mktmpdir("soul-downloads-inspect-phase56-") do |dir|
        history=ChatExecutionHistory.new(root:@root,path:File.join(dir,"history.jsonl")); gate=ReadOnlySkillExecutionGate.new(root:@root,history:history)
        samples={"inspect my downloads"=>["downloads.inspect",true,nil],"move approved downloads to trash"=>["downloads.move_to_trash",false,"owner_confirmation_required"]}.map do |msg,(skill,executed,blocker)|
          r=gate.evaluate(msg,execute:true); parsed=JSON.parse(r.stdout) rescue {}; matched=r.skill_id==skill && r.executed==executed && (blocker.nil? || r.blocked_by.include?(blocker)); matched &&= parsed["privacy"]=="filenames omitted" if skill=="downloads.inspect"; {"message"=>msg,"actual"=>{"skill_id"=>r.skill_id,"status"=>r.status,"executed"=>r.executed,"blocked_by"=>r.blocked_by},"downloads_payload"=>skill=="downloads.inspect" ? parsed : nil,"matched"=>matched}
        end
        blockers=[]; blockers << "One or more phase 56 gate samples failed" unless samples.all?{|s|s["matched"]}
        {"ok"=>blockers.empty?,"assessment"=>"read_only_skill_execution_gate","phase"=>56,"generated_at"=>Time.now.iso8601,"root"=>@root,"status"=>blockers.empty? ? "ready":"blocked","samples"=>samples,"registry"=>gate.registry.summary,"blockers"=>blockers,"verification"=>{"downloads_inspect_executes"=>samples.any?{|s|s.dig("actual","skill_id")=="downloads.inspect"&&s.dig("actual","executed")==true},"downloads_filenames_omitted"=>samples.any?{|s|s["downloads_payload"].is_a?(Hash)&&s.dig("downloads_payload","privacy")=="filenames omitted"},"approval_required_blocked"=>samples.any?{|s|s.dig("actual","blocked_by").include?("owner_confirmation_required")},"enabled_adapter_count"=>gate.registry.summary["enabled_count"]}}
      end
    end
    def render(report); ["Soul Downloads Inspect Adapter Assessment","Generated: #{report['generated_at']}","Status: #{report['status']}","Enabled adapters: #{report.dig('registry','enabled_count')}","","Samples",*report["samples"].flat_map{|s|["- #{s['message']}: #{s['matched'] ? 'ok':'mismatch'}","  skill_id: #{s.dig('actual','skill_id')}","  executed: #{s.dig('actual','executed')}","  blocked_by: #{s.dig('actual','blocked_by').join(', ')}"]},"","Blockers",*(report["blockers"].empty? ? ["- None"] : report["blockers"].map{|b|"- #{b}"})].join("
") end
  end
end
