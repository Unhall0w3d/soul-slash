# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "rbconfig"
require "time"
require "timeout"
require_relative "bounded_command_runner"

module SoulCore
  class SelfAugmentationExperimentService
    EXPERIMENT_SCHEMA = "soul.self_augmentation.experiment.v1"
    DOSSIER_SCHEMA = "soul.self_augmentation.dossier.v1"
    PROPOSALS_ROOT = File.join("Soul", "augmentation", "proposals")
    EXPERIMENTS_ROOT = File.join("Soul", "augmentation", "experiments")
    WORKTREES_ROOT = File.join("Soul", "augmentation", "worktrees")
    GATE_A1_CONFIRMATION = "APPROVE_AUGMENTATION_EXPERIMENT"
    GATE_A2_CONFIRMATION = "APPROVE_AUGMENTATION_FOR_INTEGRATION_REVIEW"
    MODEL_CONFIRMATION = "RECORD_AUGMENTATION_MODEL_QUALIFICATION"
    CLEANUP_CONFIRMATION = "REMOVE_CLEAN_AUGMENTATION_WORKTREE"
    MAX_RECORDS = 100
    MAX_PATHS = 100
    MAX_FILE_BYTES = 1024 * 1024
    FORBIDDEN = %r{(?:\A|/)(?:\.git|\.env(?:\.[^/]*)?|secrets?|credentials?|Soul/(?:runtime|memory|config|augmentation/works?trees?))(?:/|\z)|\.(?:pem|key)\z}i
    CLASS_FIVE = /(?:auth(?:entication|orization)?|privilege|sudo|polkit|persistent|daemon|service|destructive|delete|memory policy|provider privacy|unattended)/i
    MODEL_FACING = %r{\A(?:lib/soul_core/(?:conversation|model|capability|prompt|persona|self_augmentation)|assets/dashboard/|docs/(?:CONVERSATION|MODEL|.*PERSONA))}i

    def initialize(root: Dir.pwd, clock: -> { Time.now }, runner: BoundedCommandRunner.new, bubblewrap_path: nil)
      @root = File.expand_path(root)
      @clock = clock
      @runner = runner
      @bubblewrap_path = bubblewrap_path || @runner.which("bwrap")
    end

    def gate_a1_preview(proposal_id:, allowed_files:)
      proposal = proposal_record(proposal_id)
      return awaiting("unknown augmentation proposal") unless proposal
      return blocked("Class 5 subject requires a proposal-specific human brief") if class_five?(proposal)
      paths = normalize_allowed_files(allowed_files)
      base = proposal.fetch("head")
      blockers = primary_blockers(base)
      blockers << "allowed file scope traverses a symlink" if paths.any? { |path| path_traverses_symlink?(path) }
      return blocked(blockers.join("; ")) unless blockers.empty?
      payload = a1_payload(proposal, paths)
      success({"proposal"=>proposal,"allowed_files"=>paths,"base_commit"=>base,"expected_digest"=>digest(payload),"confirmation_phrase"=>GATE_A1_CONFIRMATION,"read_only"=>true})
    rescue ArgumentError => error
      awaiting(error.message)
    end

    def prepare_experiment(proposal_id:, allowed_files:, confirmation:, expected_digest:)
      created_worktree = nil
      return awaiting("preview digest is required") unless sha?(expected_digest)
      return blocked("exact confirmation is required") unless confirmation.to_s == GATE_A1_CONFIRMATION
      preview = gate_a1_preview(proposal_id: proposal_id, allowed_files: allowed_files)
      return preview unless preview["ok"]
      data = preview.fetch("data")
      payload = a1_payload(data.fetch("proposal"), data.fetch("allowed_files"))
      return blocked("proposal or repository evidence changed; preview again") unless secure_equal?(digest(payload), expected_digest.to_s)
      experiment_id = "exp_#{digest(payload)[0,16]}"
      return blocked("an experiment already exists for this exact proposal scope") if experiment_record(experiment_id)
      return blocked("experiment inventory limit reached") if experiment_ids.length >= MAX_RECORDS
      ensure_roots!
      worktree = worktree_path(experiment_id)
      record_dir = experiment_path(experiment_id)
      return blocked("experiment target already exists") if File.exist?(worktree) || File.symlink?(worktree) || File.exist?(record_dir) || File.symlink?(record_dir)

      result = git("worktree", "add", "--detach", worktree, data.fetch("base_commit"), timeout: 30)
      return failed("Git worktree creation failed safely: #{bounded_error(result)}") unless result.success?
      created_worktree = worktree
      Dir.mkdir(record_dir, 0o700)
      record = {
        "schema_version"=>EXPERIMENT_SCHEMA,"experiment_id"=>experiment_id,"proposal_id"=>proposal_id,"created_at"=>@clock.call.iso8601,
        "base_commit"=>data.fetch("base_commit"),"allowed_files"=>data.fetch("allowed_files"),"worktree"=>relative(worktree),
        "stage"=>"awaiting_external_implementation","codex_invoked"=>false,"primary_worktree_modified"=>false,"human_review_required"=>true
      }
      atomic_write(File.join(record_dir,"record.json"), JSON.pretty_generate(record)+"\n")
      atomic_write(File.join(record_dir,"CODEX_HANDOFF.md"), handoff(record, data.fetch("proposal")))
      atomic_write(File.join(record_dir,"CANDIDATE_RESULTS.json"), JSON.pretty_generate(candidate_results_template(record))+"\n")
      blocked("experiment awaits explicit human/Codex implementation", data: {"experiment"=>record,"handoff"=>relative(File.join(record_dir,"CODEX_HANDOFF.md"))}, mutation: "augmentation_experiment_prepared")
    rescue StandardError => error
      git("worktree","remove",created_worktree,timeout:30) if created_worktree && File.directory?(created_worktree)
      failed("experiment preparation failed safely: #{error.class}")
    end

    def inventory(limit: MAX_RECORDS)
      ensure_roots!
      maximum = [Integer(limit), MAX_RECORDS].min
      records = experiment_ids.first(maximum).filter_map { |id| experiment_record(id) }
      success({"records"=>records,"count"=>records.length,"limit"=>maximum,"read_only"=>true})
    end

    def generate_dossier(experiment_id:)
      record = experiment_record(experiment_id)
      return awaiting("unknown augmentation experiment") unless record
      inspection = Timeout.timeout(120) { inspect_candidate(record, run_tests: true) }
      dossier = inspection.fetch("dossier")
      path = File.join(experiment_path(record.fetch("experiment_id")), "dossier.json")
      atomic_replace(path, JSON.pretty_generate(dossier)+"\n")
      lifecycle = dossier.fetch("blockers").empty? ? "complete" : "blocked_for_human_review"
      outcome(lifecycle, dossier.fetch("blockers").empty?, {"dossier"=>dossier,"packet"=>relative(path)}, mutation: "augmentation_dossier_written", reason: dossier.fetch("blockers").join("; "))
    rescue StandardError => error
      failed("candidate review failed safely: #{error.class}")
    end

    def gate_a2_preview(experiment_id:)
      record = experiment_record(experiment_id)
      return awaiting("unknown augmentation experiment") unless record
      inspection = Timeout.timeout(120) { inspect_candidate(record, run_tests: true) }
      dossier = inspection.fetch("dossier")
      return blocked(dossier.fetch("blockers").join("; "), data: {"dossier"=>dossier}) unless dossier.fetch("blockers").empty?
      success({"dossier"=>dossier,"expected_digest"=>dossier_digest(dossier),"confirmation_phrase"=>GATE_A2_CONFIRMATION,"read_only"=>true})
    rescue StandardError => error
      failed("Gate A2 preview failed safely: #{error.class}")
    end

    def approve_for_integration(experiment_id:, confirmation:, expected_digest:)
      return awaiting("preview digest is required") unless sha?(expected_digest)
      return blocked("exact confirmation is required") unless confirmation.to_s == GATE_A2_CONFIRMATION
      preview = gate_a2_preview(experiment_id: experiment_id)
      return preview unless preview["ok"]
      dossier = preview.dig("data","dossier")
      return blocked("candidate evidence changed; preview again") unless secure_equal?(dossier_digest(dossier), expected_digest.to_s)
      directory = experiment_path(experiment_id)
      approval = {"schema_version"=>"soul.self_augmentation.gate_a2.v1","experiment_id"=>experiment_id,"candidate_commit"=>dossier.fetch("candidate_commit"),"dossier_digest"=>dossier_digest(dossier),"approved_at"=>@clock.call.iso8601,"integration_executed"=>false,"human_review_required"=>true}
      atomic_replace(File.join(directory,"gate_a2.json"), JSON.pretty_generate(approval)+"\n")
      atomic_replace(File.join(directory,"INTEGRATION_HANDOFF.md"), integration_handoff(approval,dossier))
      update_record(experiment_id,"stage"=>"approved_for_external_integration_review","candidate_commit"=>dossier.fetch("candidate_commit"))
      blocked("candidate is approved only for external integration review", data: {"approval"=>approval,"handoff"=>relative(File.join(directory,"INTEGRATION_HANDOFF.md")),"integration_executed"=>false}, mutation: "augmentation_gate_a2_approved")
    end

    def model_qualification_preview(experiment_id:, suite_id:, model_profile:, result:, evidence_digest:)
      record=experiment_record(experiment_id); return awaiting("unknown augmentation experiment") unless record
      suite=bounded_token(suite_id,"suite_id"); profile=bounded_token(model_profile,"model_profile")
      outcome_value=result.to_s; return awaiting("result must be passed or failed") unless %w[passed failed].include?(outcome_value)
      return awaiting("evidence_digest must be a SHA-256 digest") unless sha?(evidence_digest)
      payload={"schema_version"=>"soul.self_augmentation.model_qualification.v1","experiment_id"=>experiment_id,"candidate_commit"=>candidate_head(record),"suite_id"=>suite,"model_profile"=>profile,"status"=>outcome_value,"evidence_digest"=>evidence_digest,"source"=>"human_attested_external_local_eval","authorization_effect"=>"none"}
      success({"record"=>payload,"expected_digest"=>digest(payload),"confirmation_phrase"=>MODEL_CONFIRMATION,"read_only"=>true})
    rescue ArgumentError=>error; awaiting(error.message); end

    def record_model_qualification(experiment_id:, suite_id:, model_profile:, result:, evidence_digest:, confirmation:, expected_digest:)
      return awaiting("preview digest is required") unless sha?(expected_digest)
      return blocked("exact confirmation is required") unless confirmation.to_s==MODEL_CONFIRMATION
      preview=model_qualification_preview(experiment_id:experiment_id,suite_id:suite_id,model_profile:model_profile,result:result,evidence_digest:evidence_digest);return preview unless preview["ok"]
      record=preview.dig("data","record");return blocked("qualification evidence changed; preview again") unless secure_equal?(digest(record),expected_digest.to_s)
      record=record.merge("recorded_at"=>@clock.call.iso8601,"human_review_required"=>true)
      atomic_replace(File.join(experiment_path(experiment_id),"model_qualification.json"),JSON.pretty_generate(record)+"\n")
      success({"record"=>record,"model_output_authorized_nothing"=>true}).merge("mutation"=>"augmentation_model_qualification_recorded")
    end

    def cleanup_preview(experiment_id:)
      record = experiment_record(experiment_id)
      return awaiting("unknown augmentation experiment") unless record
      status = worktree_status(record)
      return blocked("experiment worktree is dirty; Soul will not remove it") unless status.empty?
      payload={"experiment_id"=>experiment_id,"candidate_commit"=>candidate_head(record),"worktree"=>record.fetch("worktree")}
      success(payload.merge("expected_digest"=>digest(payload),"confirmation_phrase"=>CLEANUP_CONFIRMATION,"read_only"=>true))
    end

    def cleanup(experiment_id:, confirmation:, expected_digest:)
      return awaiting("preview digest is required") unless sha?(expected_digest)
      return blocked("exact confirmation is required") unless confirmation.to_s == CLEANUP_CONFIRMATION
      preview=cleanup_preview(experiment_id: experiment_id); return preview unless preview["ok"]
      payload=preview.fetch("data").reject{|key,_| %w[expected_digest confirmation_phrase read_only].include?(key)}
      return blocked("worktree evidence changed; preview again") unless secure_equal?(digest(payload), expected_digest.to_s)
      record=experiment_record(experiment_id); result=git("worktree","remove",absolute_worktree(record),timeout:30)
      return failed("clean worktree removal failed safely") unless result.success?
      update_record(experiment_id,"stage"=>"canceled","worktree_removed_at"=>@clock.call.iso8601)
      outcome("canceled",true,{"experiment_id"=>experiment_id,"worktree_removed"=>true},mutation:"augmentation_worktree_removed")
    end

    private

    def inspect_candidate(record, run_tests:)
      base=record.fetch("base_commit"); candidate=candidate_head(record); status=worktree_status(record)
      changed = diff_names(base,candidate,record)
      blockers=[]
      blockers << "candidate worktree is dirty" unless status.empty?
      blockers << "candidate must contain a committed change" if candidate==base
      ancestor=git_in(record,"merge-base","--is-ancestor",base,candidate)
      blockers << "candidate is not descended from its exact base" unless ancestor.success?
      allowed=record.fetch("allowed_files")
      unexpected=changed.map{|row|row.fetch("path")}-allowed
      blockers << "candidate changed more than #{MAX_PATHS} paths" if changed.length > MAX_PATHS
      blockers << "candidate changed files outside the approved scope: #{unexpected.join(', ')}" unless unexpected.empty?
      blockers << "candidate contains a forbidden path" if changed.any?{|row| forbidden_path?(row.fetch("path"))}
      blockers << "candidate contains a symlink or submodule" if changed.any?{|row| %w[120000 160000].include?(row["mode"])}
      tests=run_tests ? sandbox_checks(record,changed) : []
      blockers << "sandboxed deterministic verification failed" if tests.any?{|test|test["status"]!="passed"}
      model_required=changed.any?{|row|row.fetch("path").match?(MODEL_FACING)}
      model_result=read_model_result(record)
      blockers << "capability-specific local-model qualification is required" if model_required && model_result["status"]!="passed"
      stat_result=git_in(record,"diff","--stat","--no-ext-diff",base+".."+candidate);raise "candidate diff statistics failed" unless stat_result.success?&&!stat_result.truncated
      numstat_result=git_in(record,"diff","--numstat","--no-ext-diff",base+".."+candidate);raise "candidate numeric diff statistics failed" unless numstat_result.success?&&!numstat_result.truncated
      dossier={
        "schema_version"=>DOSSIER_SCHEMA,"experiment_id"=>record.fetch("experiment_id"),"proposal_id"=>record.fetch("proposal_id"),"generated_at"=>@clock.call.iso8601,
        "base_commit"=>base,"candidate_commit"=>candidate,"changed_files"=>changed,"changed_file_count"=>changed.length,"unexpected_files"=>unexpected,
        "diff_stat"=>stat_result.stdout.byteslice(0,64*1024),"diff_numstat"=>numstat_result.stdout.byteslice(0,64*1024),
        "deterministic_tests"=>tests,"model_qualification_required"=>model_required,"model_qualification"=>model_result,
        "dependency_changes"=>changed.map{|row|row.fetch("path")}.grep(/(?:Gemfile|\.gemspec|package(?:-lock)?\.json|Cargo\.(?:toml|lock))\z/),
        "configuration_schema_migration_changes"=>changed.map{|row|row.fetch("path")}.grep(/(?:config|schema|migration)/i),
        "memory_privacy_host_persistence_effects"=>"human review required; no effects executed by Soul", "blockers"=>blockers,
        "known_weaknesses"=>["Sandbox checks cannot prove semantic correctness.","External integration and post-integration verification remain separate."],
        "rollback"=>["Do not integrate the candidate.","Remove the clean worktree through the explicit cleanup gate."],"human_review_required"=>true,"integration_authorized"=>false
      }
      {"dossier"=>dossier}
    end

    def sandbox_checks(record, changed)
      commands=[]
      changed.each do |row|
        path=row.fetch("path")
        commands << [RbConfig.ruby,"-c",path] if path.end_with?(".rb")
        commands << [@runner.which("node"),"--check",path] if path.end_with?(".js") && @runner.which("node")
      end
      changed.map{|row|row.fetch("path")}.grep(%r{\Ascripts/verify-[A-Za-z0-9_.-]+\.rb\z}).first(10).each{|path|commands << [RbConfig.ruby,path]}
      commands.uniq.first(30).map{|command|run_sandbox(record,command)}
    end

    def run_sandbox(record, command)
      return {"command"=>command,"status"=>"blocked","exit_status"=>nil,"output"=>"Bubblewrap is unavailable"} unless @bubblewrap_path
      worktree=absolute_worktree(record); ruby_root=File.expand_path("../..",RbConfig.ruby)
      argv=[@bubblewrap_path,"--unshare-all","--die-with-parent","--new-session","--ro-bind","/usr","/usr"]
      cursor="";@root.split(File::SEPARATOR).reject(&:empty?).each{|part|cursor+=File::SEPARATOR+part;argv.concat(["--dir",cursor])}
      [["/lib","/lib"],["/lib64","/lib64"],[ruby_root,ruby_root]].each{|source,target|argv.concat(["--ro-bind",source,target]) if File.exist?(source)}
      argv.concat(["--ro-bind",File.join(@root,".git"),File.join(@root,".git"),"--ro-bind",worktree,"/workspace","--proc","/proc","--dev","/dev","--tmpfs","/tmp","--setenv","HOME","/tmp","--chdir","/workspace","--"]+command)
      result=@runner.run(*argv,timeout_seconds:30,max_output_bytes:256*1024)
      {"command"=>command,"status"=>result.success? ? "passed" : "failed","exit_status"=>result.exit_status,"output"=>(result.stdout.to_s+result.stderr.to_s).byteslice(0,4096),"sandboxed"=>true,"network"=>false}
    end

    def diff_names(base,candidate,record)
      result=git_in(record,"diff","--name-status","--no-renames","--no-ext-diff",base+".."+candidate)
      raise "candidate diff inventory failed" unless result.success? && !result.truncated
      result.stdout.lines.map do |line|
        status,path=line.strip.split("\t",2); raise "invalid changed path" unless path
        mode_result=git_in(record,"ls-tree",candidate,"--",path)
        mode=mode_result.stdout.split.first
        {"status"=>status,"path"=>path,"mode"=>mode}
      end
    end

    def normalize_allowed_files(values)
      raise ArgumentError,"allowed_files must contain 1 to #{MAX_PATHS} exact paths" unless values.is_a?(Array)&&values.length.between?(1,MAX_PATHS)&&values.uniq.length==values.length
      values.map do |value|
        path=value.to_s.strip
        raise ArgumentError,"allowed file path is invalid" unless path.match?(/\A[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*\z/)&&!forbidden_path?(path)
        path
      end.sort
    end
    def bounded_token(value,name)
      text=value.to_s.strip;raise ArgumentError,"#{name} is invalid" unless text.match?(/\A[A-Za-z0-9_.:-]{3,120}\z/);text
    end
    def forbidden_path?(path)=path.match?(FORBIDDEN)||path.start_with?("Soul/augmentation/")
    def path_traverses_symlink?(path)
      cursor=@root
      path.split("/").any? do |part|
        cursor=File.join(cursor,part)
        File.symlink?(cursor)
      end
    end
    def class_five?(proposal)=[proposal["objective"],proposal["why_not_skill"]].join(" ").match?(CLASS_FIVE)
    def primary_blockers(base)
      blockers=[]; status=git("status","--porcelain","--untracked-files=all");head=git("rev-parse","HEAD");submodules=git("submodule","status")
      blockers << "primary Git status failed" unless status.success?&&!status.truncated
      blockers << "primary worktree is dirty" if status.success?&&!status.stdout.strip.empty?
      blockers << "primary HEAD inspection failed" unless head.success?
      blockers << "primary HEAD differs from proposal base" if head.success?&&head.stdout.strip!=base
      blockers << "submodule inspection failed" unless submodules.success?
      blockers << "submodules are not supported" if submodules.success?&&!submodules.stdout.strip.empty?
      blockers
    end
    def a1_payload(proposal,paths)={"proposal_id"=>proposal.fetch("proposal_id"),"proposal_digest"=>digest(proposal),"base_commit"=>proposal.fetch("head"),"allowed_files"=>paths}
    def proposal_record(id)
      return nil unless id.to_s.match?(/\Aaug_[a-f0-9]{16}\z/)
      directory=File.join(@root,PROPOSALS_ROOT,id.to_s);return nil if File.symlink?(directory)
      record=read_json(File.join(directory,"proposal.json"))
      return nil unless record&&record["schema_version"]=="soul.self_augmentation.proposal.v1"&&record["proposal_id"]==id.to_s&&git_oid?(record["head"])&&record["objective"].is_a?(String)&&record["why_not_skill"].is_a?(String)
      record
    end
    def experiment_record(id)
      return nil unless id.to_s.match?(/\Aexp_[a-f0-9]{16}\z/)
      directory=experiment_path(id);return nil if File.symlink?(directory)
      record=read_json(File.join(directory,"record.json"));return nil unless record&&record["schema_version"]==EXPERIMENT_SCHEMA&&record["experiment_id"]==id.to_s&&record["proposal_id"].to_s.match?(/\Aaug_[a-f0-9]{16}\z/)&&git_oid?(record["base_commit"])&&record["worktree"]==relative(worktree_path(id))
      begin
        return nil unless normalize_allowed_files(record["allowed_files"])==record["allowed_files"]
      rescue ArgumentError
        return nil
      end
      record
    end
    def experiment_ids
      ensure_roots!; Dir.children(File.join(@root,EXPERIMENTS_ROOT)).grep(/\Aexp_[a-f0-9]{16}\z/).sort.reverse
    end
    def ensure_roots!
      [EXPERIMENTS_ROOT,WORKTREES_ROOT].each do |relative_path|
        cursor=@root; relative_path.split("/").each{|part|cursor=File.join(cursor,part);raise "augmentation path traverses a symlink" if File.symlink?(cursor);Dir.mkdir(cursor,0o700) unless File.exist?(cursor);raise "augmentation path component is not a directory" unless File.directory?(cursor)}
      end
    end
    def experiment_path(id)=File.join(@root,EXPERIMENTS_ROOT,id.to_s)
    def worktree_path(id)=File.join(@root,WORKTREES_ROOT,id.to_s)
    def absolute_worktree(record)=File.join(@root,record.fetch("worktree"))
    def worktree_status(record)
      result=git_in(record,"status","--porcelain","--untracked-files=all");raise "candidate Git status failed" unless result.success?&&!result.truncated;result.stdout.lines.map(&:strip).reject(&:empty?)
    end
    def candidate_head(record)
      result=git_in(record,"rev-parse","HEAD");raise "candidate HEAD inspection failed" unless result.success?;result.stdout.strip
    end
    def git(*args,timeout:20)=@runner.run("git",*args,timeout_seconds:timeout,max_output_bytes:512*1024,chdir:@root)
    def git_in(record,*args)=@runner.run("git",*args,timeout_seconds:20,max_output_bytes:512*1024,chdir:absolute_worktree(record))
    def bounded_error(result)=result.stderr.to_s.strip.byteslice(0,300)
    def read_model_result(record)
      result=read_json(File.join(experiment_path(record.fetch("experiment_id")),"model_qualification.json"));return {"status"=>"not_run"} unless result
      valid=result["schema_version"]=="soul.self_augmentation.model_qualification.v1"&&result["experiment_id"]==record["experiment_id"]&&result["candidate_commit"]==candidate_head(record)&&result["source"]=="human_attested_external_local_eval"&&sha?(result["evidence_digest"])&&%w[passed failed].include?(result["status"])
      valid ? result : {"status"=>"invalid","reason"=>"qualification record failed deterministic validation"}
    end
    def read_json(path)
      return nil unless File.file?(path)&&!File.symlink?(path)&&File.size(path)<=MAX_FILE_BYTES
      JSON.parse(File.binread(path,MAX_FILE_BYTES))
    rescue JSON::ParserError,Errno::ENOENT; nil; end
    def update_record(id,fields)
      record=experiment_record(id) or raise "unknown experiment"; atomic_replace(File.join(experiment_path(id),"record.json"),JSON.pretty_generate(record.merge(fields))+"\n")
    end
    def atomic_write(path,content)
      raise "target already exists" if File.exist?(path)||File.symlink?(path); temp="#{path}.tmp-#{Process.pid}";File.open(temp,File::WRONLY|File::CREAT|File::EXCL,0o600){|f|f.write(content);f.flush;f.fsync};File.rename(temp,path)
    ensure File.delete(temp) if defined?(temp)&&File.file?(temp); end
    def atomic_replace(path,content)
      raise "target must not be a symlink" if File.symlink?(path);temp="#{path}.tmp-#{Process.pid}";File.open(temp,File::WRONLY|File::CREAT|File::EXCL,0o600){|f|f.write(content);f.flush;f.fsync};File.rename(temp,path)
    ensure File.delete(temp) if defined?(temp)&&File.file?(temp); end
    def handoff(record,proposal)=<<~MD
      # Self Augmentation Experiment Handoff

      Experiment: `#{record.fetch("experiment_id")}`
      Base: `#{record.fetch("base_commit")}`
      Worktree: `#{record.fetch("worktree")}`

      Objective: #{proposal.fetch("objective")}
      Why this is not a skill: #{proposal.fetch("why_not_skill")}

      Allowed files:
      #{record.fetch("allowed_files").map{|path|"- `#{path}`"}.join("\n")}

      Codex was not invoked. Work only in the linked worktree, preserve the
      forbidden boundaries, add deterministic tests, commit the candidate in the
      detached worktree, and return to Soul for a dossier.
    MD
    def candidate_results_template(record)={"schema_version"=>"soul.self_augmentation.candidate_results.v1","experiment_id"=>record.fetch("experiment_id"),"commands_run"=>[],"local_model_qualification"=>{"status"=>"not_run"},"known_weaknesses"=>[],"human_review_required"=>true}
    def integration_handoff(approval,dossier)=<<~MD
      # External Integration Handoff

      Experiment: `#{approval.fetch("experiment_id")}`
      Candidate: `#{approval.fetch("candidate_commit")}`
      Dossier digest: `#{approval.fetch("dossier_digest")}`

      Gate A2 approves this exact candidate only for integration consideration.
      Soul did not create a branch, merge, push, deploy, migrate data, or change
      the host. A human/Codex operator must re-review the dossier and perform any
      repository integration explicitly outside this workflow.
    MD
    def relative(path)=path.delete_prefix(@root+File::SEPARATOR)
    def digest(value)=Digest::SHA256.hexdigest(JSON.generate(value))
    def dossier_digest(dossier)=digest(dossier.reject{|key,_|key=="generated_at"})
    def sha?(value)=value.to_s.match?(/\A[a-f0-9]{64}\z/)
    def git_oid?(value)=value.to_s.match?(/\A(?:[a-f0-9]{40}|[a-f0-9]{64})\z/)
    def secure_equal?(a,b)=a.bytesize==b.bytesize&&a.bytes.zip(b.bytes).reduce(0){|memo,p|memo|(p[0]^p[1])}.zero?
    def success(data)={"ok"=>true,"lifecycle_state"=>"complete","data"=>data,"mutation"=>"none"}
    def awaiting(reason)={"ok"=>false,"lifecycle_state"=>"awaiting_input","reason"=>reason,"data"=>{},"mutation"=>"none"}
    def blocked(reason,data:nil,mutation:"none")=outcome("blocked_for_human_review",false,data||{},mutation:mutation,reason:reason)
    def failed(reason)=outcome("failed",false,{},reason:reason)
    def outcome(lifecycle,ok,data,mutation:"none",reason:nil)
      result={"ok"=>ok,"lifecycle_state"=>lifecycle,"data"=>data,"mutation"=>mutation};result["reason"]=reason unless reason.to_s.empty?;result
    end
  end
end
