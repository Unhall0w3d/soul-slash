#!/usr/bin/env ruby
# frozen_string_literal: true

architecture = File.read(File.join(__dir__, "../docs/soul/SELF_AUGMENTATION_AND_HOST_IMPROVEMENT_ARCHITECTURE.md"))
review = File.read(File.join(__dir__, "../docs/assessments/SELF_AUGMENTATION_AND_HOST_IMPROVEMENT_RESEARCH.md"))

checks = {
  "design authorizes only A1-A3 and no host mutation" =>
    architecture.include?("implementation_authorized: A1-A3 only") && architecture.include?("host_mutation_authorized: no"),
  "assessment host improvement and augmentation have separate authority" =>
    %w[Self\ Assessment Host\ Improvement Self\ Augmentation].all? { |phrase| architecture.include?(phrase.gsub("\\ ", " ")) },
  "skill and augmentation boundaries are explicit" =>
    architecture.include?("not a skill factory") && architecture.include?("augmentation proposes") && architecture.include?("changes to that architecture"),
  "all required lifecycle terminal states are declared" =>
    %w[complete failed awaiting_input canceled blocked_for_human_review].all? { |state| architecture.include?(state) },
  "host plan uses argv and immutable revision evidence" =>
    architecture.include?("exact_argv[]") && architecture.include?("source_assessment_digest") && architecture.include?("No shell string is authoritative"),
  "Arch assessment uses checkupdates and forbids partial upgrades" =>
    architecture.include?("checkupdates --nocolor") && architecture.include?("pacman -Syu") && architecture.include?("partial-upgrade"),
  "privilege remains outside dashboard credentials" =>
    architecture.include?("never contains a sudo password input") && architecture.include?("privileged executor is intentionally deferred"),
  "augmentation reads tracked files and excludes private state" =>
    architecture.include?("git ls-files -z") && architecture.include?("untracked files") && architecture.include?("config/secrets/**"),
  "augmentation requires isolated worktree and two gates" =>
    architecture.include?("linked Git worktree") && architecture.include?("Gate A1") && architecture.include?("Gate A2"),
  "Codex is never invoked or integrated automatically" =>
    architecture.include?("automatic_codex_invocation_authorized: no") && architecture.include?("Soul does not integrate itself"),
  "general chat does not qualify capability-specific model behavior" =>
    architecture.include?("General chat acceptance does not qualify a model"),
  "operations are separated by namespace with no generic execute" =>
    architecture.include?("host_improvement.plans.*") && architecture.include?("self_augmentation.experiments.*") && architecture.include?("There is no generic `execute` operation"),
  "first implementation block stops before worktree creation" =>
    architecture.include?("A3 is the first clean product stopping point") && review.include?("stop before worktree creation"),
  "primary-source research is recorded" =>
    %w[checkupdates.8.en pacman.8.en git-worktree systemd-run.1 polkit.8.html].all? { |source| review.include?(source) },
  "review keeps privileged broker and automatic Codex deferred" =>
    review.include?("privileged broker and automatic Codex invocation remain deferred")
}

checks.each { |name, passed| puts "#{passed ? 'PASS' : 'FAIL'}: #{name}" }
failed = checks.reject { |_name, passed| passed }
abort("Self augmentation and host improvement design verification failed: #{failed.keys.join(', ')}") unless failed.empty?

puts "Self augmentation and host improvement research/design verification complete."
