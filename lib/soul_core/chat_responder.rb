# frozen_string_literal: true
require "json"
require_relative "intent_router"
require_relative "skill_invocation_planner"
require_relative "read_only_skill_execution_gate"
require_relative "chat_execution_history"
require_relative "execution_adapter_registry"
module SoulCore
  class ChatResponder
    def initialize(root: Dir.pwd)
      @root=File.expand_path(root); @router=IntentRouter.new; @planner=SkillInvocationPlanner.new(router:@router); @history=ChatExecutionHistory.new(root:@root); @registry=ExecutionAdapterRegistry.new; @gate=ReadOnlySkillExecutionGate.new(root:@root, planner:@planner, history:@history, registry:@registry)
    end
    def respond(message)
      text=message.to_s.strip; lower=text.downcase; intent=@router.route(text)
      return "I am here. Give me a thread to pull." if lower.empty?
      return @registry.render if lower.match?(/(adapter registry|execution adapters|list adapters|enabled adapters|blocked adapters)/)
      return execute_cleanup(intent,text) if intent.id=="downloads_cleanup_plan"
      return execute_inspect(intent,text) if intent.id=="downloads_inspect"
      case intent.id
      when "downloads_move_to_trash" then gated_skill(intent,text)
      when "skill_catalog", "repo_status", "execution_history_summary" then generic_execute(intent,text)
      else fallback(intent)
      end
    end
    private
    def execute_cleanup(intent,message)
      r=@gate.evaluate(message, execute:true, record_history:true); return gate_blocked("downloads cleanup preview", r) unless r.executed && r.ok
      d=JSON.parse(r.stdout); ext=d["candidate_extensions"]||{}; ages=d["candidate_age_buckets"]||{}; sizes=d["candidate_size_buckets"]||{}
      ["I executed the Downloads cleanup preview.","","Action: #{d['action']}","Mutation: #{d['mutation']}","Rule: #{d['candidate_rule']}","Path: #{d['path']}","Files scanned: #{d['file_count']}","Candidate files: #{d['candidate_count']}","Candidate bytes: #{d['candidate_bytes']}","Candidate extensions: #{ext.empty? ? 'none' : ext.map{|k,v| "#{k}=#{v}"}.join(', ')}","Candidate age buckets: #{ages.empty? ? 'none' : ages.map{|k,v| "#{k}=#{v}"}.join(', ')}","Candidate size buckets: #{sizes.empty? ? 'none' : sizes.map{|k,v| "#{k}=#{v}"}.join(', ')}","","Executed: true","Skill: #{intent.skill_id}","Risk: #{intent.risk}","History recorded: true","Privacy: filenames omitted. Nothing was moved or deleted, because we are not speedrunning regret."].join("
")
    end
    def execute_inspect(intent,message)
      r=@gate.evaluate(message, execute:true, record_history:true); return gate_blocked("downloads inspection", r) unless r.executed && r.ok
      d=JSON.parse(r.stdout); ext=d["extensions"]||{}
      ["I executed the read-only Downloads inspection.","","Path: #{d['path']}","Exists: #{d['exists']}","Entries: #{d['entry_count']}","Files: #{d['file_count']}","Directories: #{d['directory_count']}","Hidden entries: #{d['hidden_entry_count']}","Total bytes: #{d['total_file_bytes']}","Largest file bytes: #{d['largest_file_bytes']}","Extensions: #{ext.empty? ? 'none' : ext.map{|k,v| "#{k}=#{v}"}.join(', ')}","","Executed: true","Skill: #{intent.skill_id}","Risk: #{intent.risk}","History recorded: true","Privacy: filenames omitted."].join("
")
    end
    def generic_execute(intent,message)
      r=@gate.evaluate(message, execute:true, record_history:true); return gate_blocked(intent.skill_id || "skill", r) unless r.executed && r.ok
      "I executed the non-mutating adapter.

Executed: true
Skill: #{intent.skill_id}
Risk: #{intent.risk}
History recorded: true"
    end
    def gate_blocked(label,r); ["I mapped this to #{label}, but the execution gate did not allow it.","Gate status: #{r.status}","Blocked by: #{r.blocked_by.join(', ')}","History recorded: #{!r.history_entry.nil?}",r.message].join("
"); end
    def gated_skill(intent,message); r=@gate.evaluate(message, execute:false, record_history:true); ["I can map this request to the execution gate.","","Intent: #{intent.label}","Skill candidate: #{intent.skill_id || 'none'}","Risk: #{intent.risk}","Confirmation required: #{intent.confirmation_required}","Executed: false","Gate status: #{r.status}","Blocked by: #{r.blocked_by.join(', ')}","History recorded: true","",r.message].join("
"); end
    def fallback(intent); ["I heard you. I can route intents and execute registered non-mutating adapters, but this request did not match an executable path.","","Intent: #{intent.label}","Reason: #{intent.reason}","Next step: #{intent.next_step}"].join("
"); end
  end
end
