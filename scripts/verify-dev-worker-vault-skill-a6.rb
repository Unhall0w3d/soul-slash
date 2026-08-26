#!/usr/bin/env ruby
# frozen_string_literal: true

skill = File.read(File.join(__dir__, "../.codex/skills/soul-dev-worker/SKILL.md"))
guide = File.read(File.join(__dir__, "../docs/guides/DEV_WORKER.md"))
brief = File.read(File.join(__dir__, "../docs/soul/ALETHEIAUC_VAULT_DEV_SKILL_A6_BRIEF.md"))

errors = []
checks = 0
check = lambda do |description, condition|
  checks += 1
  condition ? puts("PASS: #{description}") : (errors << description; warn("FAIL: #{description}"))
end

check.call("skill names the reviewed vault request schema", skill.include?("dev_worker_vault_request.schema.json"))
check.call("skill retains the manual request schema", skill.include?("dev_worker_request.schema.json"))
check.call("skill uses bounded vault commands", skill.include?("dev-worker-vault preview") && skill.include?("dev-worker-vault execute"))
check.call("skill retains exact confirmation and digest review", skill.include?("RUN_SOUL_DEV_WORKER <request_id>") && skill.include?("<preview_digest>"))
check.call("skill and guide require repository verification", skill.include?("Verify every factual claim against repository evidence") && guide.include?("verify all proposed paths"))
check.call("skill treats vault notes as untrusted evidence", skill.include?("untrusted context") && skill.include?("not as current repository truth"))
check.call("skill stops on insufficient local context", skill.include?("awaiting_input") && skill.include?("do not silently broaden"))
check.call("guide identifies AletheiaUC as qualified", guide.include?("AletheiaUC is the first qualified corpus"))
check.call("guide retains manual fallback", guide.match?(/Manual parent-supplied\s+context remains the fallback/))
check.call("brief prohibits authority expansion", brief.include?("adds no model call") && brief.include?("approval bypass"))
check.call("skill does not claim automatic application", !skill.match?(/automatically apply|apply the candidate automatically/i))

abort "#{errors.length} vault-aware Dev Worker skill checks failed: #{errors.join('; ')}" unless errors.empty?
puts "Vault-aware Dev Worker skill A6 verification passed (#{checks} checks)."
