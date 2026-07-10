# frozen_string_literal: true
require "json"
require "open3"
require "time"
require_relative "skill_invocation_planner"
require_relative "chat_execution_history"
require_relative "execution_adapter_registry"
module SoulCore
  class ReadOnlySkillExecutionGate
    Execution = Struct.new(:ok,:status,:message,:skill_id,:risk,:confirmation_required,:executed,:stdout,:stderr,:exit_status,:blocked_by,:generated_at,:history_entry, keyword_init: true) do
      def to_h
        {"ok"=>ok,"status"=>status,"message"=>message,"skill_id"=>skill_id,"risk"=>risk,"confirmation_required"=>confirmation_required,"executed"=>executed,"stdout"=>stdout,"stderr"=>stderr,"exit_status"=>exit_status,"blocked_by"=>blocked_by,"generated_at"=>generated_at,"history_entry"=>history_entry}
      end
    end
    attr_reader :registry
    def initialize(root: Dir.pwd, planner: SkillInvocationPlanner.new, history: nil, registry: ExecutionAdapterRegistry.new)
      @root=File.expand_path(root); @planner=planner; @history=history || ChatExecutionHistory.new(root:@root); @registry=registry
    end
    def evaluate(message, execute: false, record_history: false)
      result=evaluate_plan(@planner.plan(message), execute: execute); result.history_entry=@history.record(result, message: message) if record_history; result
    end
    def evaluate_plan(plan, execute: false)
      skill_id=plan.skill_id; risk=plan.risk || "unknown"
      return blocked(plan,"No candidate skill was mapped.",["no_candidate_skill"]) unless skill_id
      return blocked(plan,"This skill requires explicit owner confirmation before execution.",["owner_confirmation_required"]) if plan.confirmation_required || risk == "approval_required"
      adapter=@registry.find(skill_id)
      return blocked(plan,"This skill is not registered in the execution adapter registry.",["adapter_not_registered"]) unless adapter
      return blocked(plan,"This skill is not classified as a safe non-mutating adapter.",["not_safe_non_mutating"]) unless @registry.safe_non_mutating?(skill_id,risk)
      return blocked(plan,"This skill is registered but not enabled for execution.",["adapter_not_enabled"]) unless adapter.enabled?
      return dry_run(plan,"Non-mutating execution is allowed for #{skill_id}, but execution was not requested.",["dry_run_not_execute_requested"]) unless execute
      case adapter.internal_handler
      when "execution_history_summary" then history_summary(plan)
      when "downloads_inspect" then downloads_inspect(plan)
      when "downloads_cleanup_plan" then downloads_cleanup_plan(plan)
      else
        return run_command(plan, adapter) if adapter.command?
        blocked(plan,"Registered adapter has no executable handler.",["adapter_handler_missing"])
      end
    end
    def explain(message, execute: false, record_history: false)
      r=evaluate(message, execute: execute, record_history: record_history)
      (["Read-only skill execution gate","skill_id: #{r.skill_id || 'none'}","risk: #{r.risk || 'unknown'}","confirmation_required: #{r.confirmation_required}","executed: #{r.executed}","status: #{r.status}","message: #{r.message}","history_recorded: #{!r.history_entry.nil?}","blocked_by:"] + (r.blocked_by.empty? ? ["- none"] : r.blocked_by.map{|b| "- #{b}"})).join("
")
    end
    private
    def run_command(plan, adapter)
      stdout,stderr,status=Open3.capture3(*adapter.command, chdir:@root)
      Execution.new(ok:status.success?,status:status.success? ? "executed" : "failed",message:"Executed non-mutating skill #{plan.skill_id}.",skill_id:plan.skill_id,risk:plan.risk,confirmation_required:false,executed:true,stdout:stdout,stderr:stderr,exit_status:status.exitstatus,blocked_by:[],generated_at:Time.now.iso8601,history_entry:nil)
    end
    def history_summary(plan)
      by_status=Hash.new(0); by_skill=Hash.new(0); rows=@history.entries
      rows.each{|e| by_status[e["status"] || "unknown"] += 1; by_skill[e["skill_id"] || "none"] += 1}
      successful(plan,{"ok"=>true,"skill_id"=>plan.skill_id,"total_entries"=>rows.length,"shown_entries"=>@history.summary(limit:10)["shown"],"counts_by_status"=>by_status.sort.to_h,"counts_by_skill"=>by_skill.sort.to_h,"latest"=>rows.last})
    end
    def downloads_inspect(plan)
      successful(plan, downloads_stats.merge("ok"=>true,"skill_id"=>plan.skill_id,"privacy"=>"filenames omitted"))
    end
    def downloads_cleanup_plan(plan)
      stats=downloads_stats(include_candidates:true)
      successful(plan, stats.merge("ok"=>true,"skill_id"=>plan.skill_id,"action"=>"preview_only","candidate_rule"=>"files older than 30 days or larger than 100 MiB","privacy"=>"filenames omitted","mutation"=>"none"))
    end
    def downloads_stats(include_candidates:false)
      dir=File.join(Dir.home,"Downloads"); exists=Dir.exist?(dir); names=exists ? Dir.children(dir) : []; now=Time.now
      files=dirs=hidden=total=largest=candidate_count=candidate_bytes=0
      ext=Hash.new(0); ages=Hash.new(0); sizes=Hash.new(0); c_ext=Hash.new(0); c_ages=Hash.new(0); c_sizes=Hash.new(0)
      names.each do |name|
        hidden += 1 if name.start_with?("."); path=File.join(dir,name)
        if File.directory?(path); dirs += 1; next; end
        next unless File.file?(path)
        files += 1; size=(File.size(path) rescue 0); total += size; largest=[largest,size].max
        e=File.extname(name).downcase; e="[no extension]" if e.empty?; ext[e]+=1
        days=((now - File.mtime(path))/86400).floor rescue 0; age=bucket_age(days); siz=bucket_size(size); ages[age]+=1; sizes[siz]+=1
        next unless include_candidates && (days > 30 || size > 100*1024*1024)
        candidate_count += 1; candidate_bytes += size; c_ext[e]+=1; c_ages[age]+=1; c_sizes[siz]+=1
      end
      {"path"=>"~/Downloads","exists"=>exists,"entry_count"=>names.length,"file_count"=>files,"directory_count"=>dirs,"hidden_entry_count"=>hidden,"total_file_bytes"=>total,"largest_file_bytes"=>largest,"extensions"=>sorted(ext),"age_buckets"=>sorted(ages),"size_buckets"=>sorted(sizes),"candidate_count"=>candidate_count,"candidate_bytes"=>candidate_bytes,"candidate_extensions"=>sorted(c_ext),"candidate_age_buckets"=>sorted(c_ages),"candidate_size_buckets"=>sorted(c_sizes)}
    end
    def bucket_age(days); days <= 7 ? "0-7 days" : days <= 30 ? "8-30 days" : days <= 90 ? "31-90 days" : "91+ days"; end
    def bucket_size(bytes); m=1024*1024; bytes < m ? "0-1 MiB" : bytes < 10*m ? "1-10 MiB" : bytes < 100*m ? "10-100 MiB" : "100+ MiB"; end
    def sorted(h); h.sort_by{|k,v| [-v,k]}.to_h; end
    def successful(plan,payload); Execution.new(ok:true,status:"executed",message:"Executed non-mutating skill #{plan.skill_id}.",skill_id:plan.skill_id,risk:plan.risk,confirmation_required:false,executed:true,stdout:JSON.pretty_generate(payload)+"
",stderr:"",exit_status:0,blocked_by:[],generated_at:Time.now.iso8601,history_entry:nil); end
    def dry_run(plan,message,blocked_by); Execution.new(ok:true,status:"ready",message:message,skill_id:plan.skill_id,risk:plan.risk,confirmation_required:false,executed:false,stdout:"",stderr:"",exit_status:nil,blocked_by:blocked_by,generated_at:Time.now.iso8601,history_entry:nil); end
    def blocked(plan,message,blocked_by); Execution.new(ok:false,status:"blocked",message:message,skill_id:plan.skill_id,risk:plan.risk,confirmation_required:plan.confirmation_required,executed:false,stdout:"",stderr:"",exit_status:nil,blocked_by:blocked_by,generated_at:Time.now.iso8601,history_entry:nil); end
  end
end
