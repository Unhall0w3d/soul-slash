#!/usr/bin/env ruby
# frozen_string_literal: true
require "json"
require "open3"
errors=[]
def run_cmd(*cmd)=Open3.capture3(*cmd)
puts "Downloads cleanup preview phase 57 verification:"
paths=%w[lib/soul_core/execution_adapter_registry.rb lib/soul_core/execution_adapter_registry_assessor.rb lib/soul_core/read_only_skill_execution_gate.rb lib/soul_core/read_only_skill_execution_gate_assessor.rb lib/soul_core/chat_responder.rb scripts/verify-downloads-cleanup-preview-phase57.rb docs/maintenance/PHASE57_DOWNLOADS_CLEANUP_PREVIEW.md docs/DOWNLOADS_CLEANUP_PREVIEW.md]
paths.each do |path|
  ok=File.exist?(path); ok &&= system("ruby","-c",path,out:File::NULL,err:File::NULL) if path.end_with?(".rb"); puts "- #{path}: #{ok ? 'ok' : 'missing'}"; errors << "#{path} missing or invalid" unless ok
end
stdout,stderr,status=run_cmd("ruby","bin/soul","assess","execution-adapter-registry","--json"); registry=JSON.parse(stdout) rescue nil
ok=status.success? && registry && registry["phase"]==57 && registry.dig("verification","downloads_cleanup_plan_enabled")==true && registry.dig("verification","has_five_enabled_adapters")==true
puts "- registry enables downloads.cleanup_plan: #{ok ? 'ok' : 'missing'}"; errors << "registry check failed: #{stderr} #{stdout}" unless ok
stdout,stderr,status=run_cmd("ruby","bin/soul","assess","read-only-skill-gate","--json"); gate=JSON.parse(stdout) rescue nil
ok=status.success? && gate && gate["phase"]==57 && gate.dig("verification","downloads_cleanup_plan_executes")==true && gate.dig("verification","cleanup_plan_preview_only")==true && gate.dig("verification","cleanup_plan_no_mutation")==true && gate.dig("verification","approval_required_blocked")==true
puts "- gate executes cleanup preview safely: #{ok ? 'ok' : 'missing'}"; errors << "gate check failed: #{stderr} #{stdout}" unless ok
stdout,stderr,status=run_cmd("ruby","bin/soul","chat","clean up downloads"); ok=status.success? && stdout.include?("I executed the Downloads cleanup preview.") && stdout.include?("Action: preview_only") && stdout.include?("Mutation: none") && stdout.include?("Privacy: filenames omitted") && stdout.include?("Executed: true")
puts "- chat executes cleanup preview: #{ok ? 'ok' : 'missing'}"; errors << "chat cleanup preview failed: #{stderr} #{stdout}" unless ok
stdout,stderr,status=run_cmd("ruby","bin/soul","chat","move approved downloads to trash"); ok=status.success? && stdout.include?("Executed: false") && stdout.include?("owner_confirmation_required")
puts "- downloads move/delete remains blocked: #{ok ? 'ok' : 'missing'}"; errors << "trash block failed: #{stderr} #{stdout}" unless ok
doc_ok=File.read("docs/DOWNLOADS_CLEANUP_PREVIEW.md").include?("downloads.cleanup_plan") && File.read("docs/maintenance/PHASE57_DOWNLOADS_CLEANUP_PREVIEW.md").include?("Phase 57")
puts "- phase 57 docs: #{doc_ok ? 'ok' : 'missing'}"; errors << "phase 57 docs missing expected content" unless doc_ok
stdout,stderr,status=run_cmd("ruby","bin/soul","assess","repo-curation","--json"); curation=JSON.parse(stdout) rescue nil; allowed=["scripts/verify-downloads-cleanup-preview-phase57.rb"]; untracked=curation&&curation["untracked_review_candidates"].is_a?(Array) ? curation["untracked_review_candidates"] : []
ok=status.success? && curation && curation.dig("counts","tracked_overlay_notes").to_i==0 && (untracked-allowed).empty?
puts "- repo curation remains clean apart from current phase verifier: #{ok ? 'ok' : 'missing'}"; errors << "repo curation unexpected candidates: #{stderr} #{stdout}" unless ok
if errors.empty?; puts "Verification complete."; else warn "Verification failed:"; errors.each{|e| warn "- #{e}"}; exit 1; end
