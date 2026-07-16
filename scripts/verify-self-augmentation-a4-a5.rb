#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "time"
require_relative "../lib/soul_core/self_augmentation_experiment_service"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/application_facade"

failures=[]
check=lambda{|name,value|puts "- #{name}: #{value ? 'ok' : 'FAILED'}";failures << name unless value}
run=lambda do |*command,chdir: nil|
  stdout,stderr,status=Open3.capture3(*command,**(chdir ? {chdir:chdir} : {}));raise "#{command.join(' ')} failed: #{stderr}" unless status.success?;stdout
end

puts "Self Augmentation A4–A5 verification:"
Dir.mktmpdir(".verify-soul-augmentation-a4-a5-",Dir.pwd) do |root|
  FileUtils.mkdir_p(File.join(root,"lib"));FileUtils.mkdir_p(File.join(root,"scripts"));FileUtils.mkdir_p(File.join(root,"Soul","augmentation","proposals","aug_1111111111111111"))
  File.write(File.join(root,".gitignore"),"Soul/augmentation/\n")
  File.write(File.join(root,"lib","candidate.rb"),"module Candidate\n  VALUE = 1\nend\n")
  File.symlink("candidate.rb",File.join(root,"lib","linked-candidate.rb"))
  File.write(File.join(root,"scripts","verify-candidate.rb"),"# frozen_string_literal: true\nrequire 'open3'\n_out, status = Open3.capture2('git', 'rev-parse', 'HEAD')\nabort 'git unavailable' unless status.success?\nputs 'candidate verifier ok'\n")
  run.call("git","init","-q",root);run.call("git","add",".gitignore","lib/candidate.rb","lib/linked-candidate.rb","scripts/verify-candidate.rb",chdir:root)
  run.call("git","-c","user.name=Soul Test","-c","user.email=soul@example.invalid","commit","-qm","base",chdir:root)
  base=run.call("git","rev-parse","HEAD",chdir:root).strip
  proposal={"schema_version"=>"soul.self_augmentation.proposal.v1","proposal_id"=>"aug_1111111111111111","created_at"=>Time.utc(2026,7,16).iso8601,"objective"=>"Improve a shared architectural contract with explicit review evidence.","why_not_skill"=>"The change affects shared orchestration rather than one bounded foreground capability.","source_digest"=>"a"*64,"head"=>base,"implementation_authorized"=>false,"human_review_required"=>true,"stage"=>"proposal_review","risk_class"=>"class_4"}
  File.write(File.join(root,"Soul","augmentation","proposals","aug_1111111111111111","proposal.json"),JSON.pretty_generate(proposal))
  service=SoulCore::SelfAugmentationExperimentService.new(root:root,clock:->{Time.utc(2026,7,16,12,0,0)})
  allowed_files=["lib/candidate.rb","scripts/verify-candidate.rb"]
  symlink_preview=service.gate_a1_preview(proposal_id:proposal["proposal_id"],allowed_files:["lib/linked-candidate.rb"])
  check.call("Gate A1 rejects allowed scope through a tracked symlink",symlink_preview["lifecycle_state"]=="blocked_for_human_review"&&symlink_preview["reason"].include?("symlink"))
  preview=service.gate_a1_preview(proposal_id:proposal["proposal_id"],allowed_files:allowed_files)
  check.call("Gate A1 preview is read-only and digest-bound",preview["ok"]&&Dir.glob(File.join(root,"Soul","augmentation","worktrees","exp_*" )).empty?)
  wrong=service.prepare_experiment(proposal_id:proposal["proposal_id"],allowed_files:allowed_files,confirmation:"WRONG",expected_digest:preview.dig("data","expected_digest"))
  check.call("Gate A1 wrong confirmation creates no worktree",wrong["lifecycle_state"]=="blocked_for_human_review"&&Dir.glob(File.join(root,"Soul","augmentation","worktrees","exp_*" )).empty?)
  prepared=service.prepare_experiment(proposal_id:proposal["proposal_id"],allowed_files:allowed_files,confirmation:SoulCore::SelfAugmentationExperimentService::GATE_A1_CONFIRMATION,expected_digest:preview.dig("data","expected_digest"))
  record=prepared.dig("data","experiment");worktree=File.join(root,record.fetch("worktree"))
  check.call("Gate A1 creates one detached worktree and handoff only",prepared["lifecycle_state"]=="blocked_for_human_review"&&File.directory?(worktree)&&record["codex_invoked"]==false&&run.call("git","branch","--show-current",chdir:worktree).empty?)
  facade=SoulCore::ApplicationFacade.new(root:root,self_augmentation_experiment_service:service,clock:->{Time.utc(2026,7,16,12,0,0)})
  api=facade.call({"schema_version"=>"soul.application.v1","request_id"=>"augmentation:a4a5:list","operation"=>"self_augmentation.experiments.list","parameters"=>{"limit"=>10},"context"=>{"interface"=>"dashboard_test"}})
  check.call("application facade exposes bounded experiment inventory",api["lifecycle_state"]=="complete"&&api.dig("data","count")==1)

  File.write(File.join(worktree,"lib","candidate.rb"),"module Candidate\n  VALUE = 2\nend\n")
  File.open(File.join(worktree,"scripts","verify-candidate.rb"),"a") {|file| file.write("# candidate revision\n") }
  run.call("git","add","lib/candidate.rb","scripts/verify-candidate.rb",chdir:worktree)
  run.call("git","-c","user.name=Soul Test","-c","user.email=soul@example.invalid","commit","-qm","candidate",chdir:worktree)
  candidate=run.call("git","rev-parse","HEAD",chdir:worktree).strip
  model_preview=service.model_qualification_preview(experiment_id:record.fetch("experiment_id"),suite_id:"candidate_contract_v1",model_profile:"soul-model-amd",result:"passed",evidence_digest:"b"*64)
  model_record=service.record_model_qualification(experiment_id:record.fetch("experiment_id"),suite_id:"candidate_contract_v1",model_profile:"soul-model-amd",result:"passed",evidence_digest:"b"*64,confirmation:SoulCore::SelfAugmentationExperimentService::MODEL_CONFIRMATION,expected_digest:model_preview.dig("data","expected_digest"))
  check.call("external local-model evidence is digest-gated and non-authorizing",model_record["ok"]&&model_record.dig("data","model_output_authorized_nothing")==true)
  dossier_result=service.generate_dossier(experiment_id:record.fetch("experiment_id"));dossier=dossier_result.dig("data","dossier")
  warn JSON.pretty_generate(dossier_result) unless dossier_result["lifecycle_state"]=="complete"
  check.call("A5 dossier binds commits paths and sandboxed Git-aware checks",dossier_result["lifecycle_state"]=="complete"&&dossier["base_commit"]==base&&dossier["candidate_commit"]==candidate&&dossier["changed_files"].map{|row|row["path"]}.sort==allowed_files.sort&&dossier["diff_numstat"].lines.length==2&&dossier["deterministic_tests"].length==3&&dossier["deterministic_tests"].all?{|test|test["sandboxed"]&&test["network"]==false&&test["status"]=="passed"})
  a2=service.gate_a2_preview(experiment_id:record.fetch("experiment_id"))
  rejected=service.approve_for_integration(experiment_id:record.fetch("experiment_id"),confirmation:"WRONG",expected_digest:a2.dig("data","expected_digest"))
  check.call("Gate A2 wrong confirmation integrates nothing",rejected["lifecycle_state"]=="blocked_for_human_review"&&!File.exist?(File.join(root,"Soul","augmentation","experiments",record.fetch("experiment_id"),"gate_a2.json")))
  approved=service.approve_for_integration(experiment_id:record.fetch("experiment_id"),confirmation:SoulCore::SelfAugmentationExperimentService::GATE_A2_CONFIRMATION,expected_digest:a2.dig("data","expected_digest"))
  check.call("Gate A2 writes external handoff without integration",approved["lifecycle_state"]=="blocked_for_human_review"&&approved.dig("data","integration_executed")==false&&File.file?(File.join(root,approved.dig("data","handoff")))&&run.call("git","rev-parse","HEAD",chdir:root).strip==base)
  record_path=File.join(root,"Soul","augmentation","experiments",record.fetch("experiment_id"),"record.json");stored_record=File.binread(record_path);tampered=JSON.parse(stored_record).merge("worktree"=>"../unapproved-target");File.write(record_path,JSON.pretty_generate(tampered))
  tampered_cleanup=service.cleanup_preview(experiment_id:record.fetch("experiment_id"));File.write(record_path,stored_record)
  check.call("tampered experiment paths fail closed",tampered_cleanup["lifecycle_state"]=="awaiting_input"&&File.directory?(worktree))
  File.write(File.join(worktree,"unreviewed.tmp"),"dirty\n")
  dirty_cleanup=service.cleanup_preview(experiment_id:record.fetch("experiment_id"))
  check.call("dirty worktree cleanup is refused",dirty_cleanup["lifecycle_state"]=="blocked_for_human_review"&&File.directory?(worktree))
  File.delete(File.join(worktree,"unreviewed.tmp"))
  cleanup_preview=service.cleanup_preview(experiment_id:record.fetch("experiment_id"))
  cleaned=service.cleanup(experiment_id:record.fetch("experiment_id"),confirmation:SoulCore::SelfAugmentationExperimentService::CLEANUP_CONFIRMATION,expected_digest:cleanup_preview.dig("data","expected_digest"))
  check.call("clean worktree cleanup is explicit and non-forced",cleaned["lifecycle_state"]=="canceled"&&!File.exist?(worktree)&&File.file?(File.join(root,"Soul","augmentation","experiments",record.fetch("experiment_id"),"record.json")))
end

source=File.read(File.expand_path("../lib/soul_core/self_augmentation_experiment_service.rb",__dir__))
integration_calls=%w[merge push branch commit tag].any?{|name|source.include?(%Q{git("#{name}"})||source.include?(%Q{git_in(record,"#{name}"})}
check.call("service contains no Codex invocation or Git integration command",!source.match?(/(?:system|spawn|exec|run)\s*\([^\n]*["']codex/i)&&!integration_calls&&source.include?('"worktree","remove"')&&!source.include?("--force"))
check.call("candidate execution requires no-network Bubblewrap",source.include?("--unshare-all")&&source.include?("--ro-bind")&&source.include?('"network"=>false'))
operations=SoulCore::ApplicationContract::OPERATIONS
check.call("A4–A5 API operations are explicitly allowlisted",%w[self_augmentation.experiments.gate_a1.preview self_augmentation.experiments.gate_a1.execute self_augmentation.reviews.generate self_augmentation.reviews.gate_a2.preview self_augmentation.reviews.gate_a2.execute self_augmentation.experiments.cleanup.preview].all?{|operation|operations.key?(operation)})
html=File.read(File.expand_path("../assets/dashboard/index.html",__dir__));javascript=File.read(File.expand_path("../assets/dashboard/dashboard.js",__dir__))
check.call("dashboard exposes both gates and exact confirmations",%w[preview-augmentation-experiment create-augmentation-experiment generate-augmentation-dossier preview-augmentation-gate-a2 execute-augmentation-gate-a2].all?{|id|html.include?(%Q{id="#{id}"})}&&html.include?(SoulCore::SelfAugmentationExperimentService::GATE_A1_CONFIRMATION)&&html.include?(SoulCore::SelfAugmentationExperimentService::GATE_A2_CONFIRMATION))
check.call("dashboard adds no polling or automatic implementation",!javascript.match?(/setInterval|setTimeout|WebSocket|EventSource|callSoul\([^\n]*(?:codex|merge|push|deploy)/i))
abort "Verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Verification complete."
