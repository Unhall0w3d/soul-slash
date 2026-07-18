#!/usr/bin/env ruby
# frozen_string_literal: true

root = File.expand_path("..", __dir__)
javascript = File.read(File.join(root, "assets", "dashboard", "dashboard.js"))
html = File.read(File.join(root, "assets", "dashboard", "index.html"))
helper = javascript[/function prefillApprovalGate[\s\S]*?\n}\nfunction lifecycle/] || ""

failures = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAILED'}"
  failures << label unless condition
end

affirmative_inputs = %w[
  music-reference-confirmation music-reference-reanalysis-confirmation
  music-reference-synthesis-confirmation music-generation-confirmation
  model-runtime-confirmation proposal-confirmation beta-build-confirmation
  beta-run-confirmation beta-promotion-confirmation
  production-promotion-confirmation improvement-proposal-confirmation
  host-plan-confirmation augmentation-confirmation
  augmentation-experiment-confirmation augmentation-gate-a2-confirmation
  augmentation-model-confirmation
]
destructive_inputs = %w[
  music-project-delete-confirmation music-reference-delete-confirmation
  music-reference-synthesis-reject-confirmation proposal-close-confirmation
  augmentation-cleanup-confirmation clear-confirmation forget-confirmation
]

check.call("affirmative gate helper pre-fills an exact read-only phrase and enables only a valid action",
  javascript.include?("function prefillApprovalGate") && javascript.include?("input.readOnly = enabled") && javascript.include?("button.disabled = !enabled || exact.length === 0"))
check.call("all fixed affirmative approval surfaces use click authorization",
  affirmative_inputs.all? { |id| javascript.include?("prefillApprovalGate(\"#{id}\"") })
check.call("destructive subtractive gates remain manually typed",
  destructive_inputs.none? { |id| javascript.include?("prefillApprovalGate(\"#{id}\"") } &&
    destructive_inputs.all? { |id| html.include?("id=\"#{id}\"") })
check.call("dynamic analysis revision and export approvals are prefilled but candidate rejection is not",
  javascript.include?("prefillApprovalGate(input, run, data.confirmation_phrase)") &&
    javascript.include?("prefillApprovalGate(input, start, preview.confirmation_phrase)") &&
    javascript.include?('if (kind === "export") prefillApprovalGate(input, execute, data.confirmation_phrase)'))
check.call("prefilling never invokes an action automatically",
  !helper.include?(".click(") &&
    javascript.include?('byId("start-music-generation").addEventListener("click", startMusicGeneration)'))
check.call("backend-bound phrases and initially disabled controls remain visible",
  html.include?("START_MUSIC_GENERATION") && html.include?('id="start-music-generation"') && html.include?("disabled"))

abort "#{failures.length} click-approval verification(s) failed: #{failures.join(', ')}" unless failures.empty?
puts "Dashboard click-approval deterministic verification passed."
