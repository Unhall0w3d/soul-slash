#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require "fileutils"
require_relative "../lib/soul_core/alpha_implementation_task_pack_generator"
require_relative "../lib/soul_core/alpha_implementation_review_gate"

def check(label, condition)
  raise label unless condition
  puts "PASS #{label}"
end

Dir.mktmpdir("soul-codex-routing-") do |root|
  proposal = File.join(root, "proposal")
  alpha = File.join(proposal, "alpha")
  FileUtils.mkdir_p(alpha)
  generator = SoulCore::AlphaImplementationTaskPackGenerator.new(root: root)
  report = generator.generate(proposal_path: proposal)
  check("bounded implementation recommends Luna High", report.dig("task_pack", "task", "model_recommendation") == "gpt-6-luna high")
  gate = SoulCore::AlphaImplementationReviewGate.new(root: root)
  contract_path = File.join(alpha, "codex_handoff_contract.json")
  original = JSON.parse(File.read(contract_path))
  models = ["gpt-6-astra medium", "gpt-6-luna low", "gpt-6-luna high",
            "gpt-5.6-sol medium", "gpt-5.6-sol high",
            "gpt-5.6-terra medium", "gpt-5.6-luna low", "gpt-5.6-luna high", "gpt-5.5 medium"]
  models.each do |model|
    contract = Marshal.load(Marshal.dump(original))
    contract.fetch("task")["model_recommendation"] = model
    File.write(contract_path, JSON.generate(contract))
    result = gate.review(proposal_path: proposal)
    check("#{model} remains reviewable", result["ok"] && result.fetch("warnings").none? { |w| w.include?("model recommendation") })
    check("#{model} grants no execution or promotion", %w[promotion_allowed implementation_allowed codex_invoked].all? { |key| result[key] == false })
  end

  original.fetch("task")["model_recommendation"] = "unknown-model"
  File.write(contract_path, JSON.generate(original))
  unknown = gate.review(proposal_path: proposal)
  check("unrecognized model preserves advisory warning", unknown.fetch("warnings").any? { |w| w.include?("model recommendation") })
  check("unrecognized model grants no authority", %w[promotion_allowed implementation_allowed codex_invoked].all? { |key| unknown[key] == false })

  generator.generate(proposal_path: proposal)
  pack_path = File.join(alpha, "implementation_task_pack.json")
  pack = JSON.parse(File.read(pack_path))
  ["Do not invoke Codex.", "Do not write production implementation."].each do |boundary|
    damaged = Marshal.load(Marshal.dump(pack))
    damaged.fetch("boundaries").delete(boundary)
    File.write(pack_path, JSON.generate(damaged))
    check("missing #{boundary} still blocks", gate.review(proposal_path: proposal)["ok"] == false)
  end
  File.write(pack_path, JSON.generate(pack))
  File.unlink(File.join(alpha, "rollback_plan.md"))
  check("missing rollback still blocks", gate.review(proposal_path: proposal)["ok"] == false)
end
puts "Routing compatibility verified using temporary artifacts only."
