#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "time"
require_relative "../lib/soul_core/package_manager_assessor"
require_relative "../lib/soul_core/host_improvement_plan_service"
require_relative "../lib/soul_core/self_augmentation_service"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/application_facade"

failures = []
check = lambda do |name, condition|
  puts "- #{name}: #{condition ? 'ok' : 'FAILED'}"
  failures << name unless condition
end

Result = Struct.new(:stdout, :stderr, :exit_status, :status, :truncated, keyword_init: true) do
  def success? = status == "ok"
end

class PackageRunner
  attr_reader :commands
  def initialize(checkupdates_result)
    @checkupdates_result = checkupdates_result
    @commands = []
  end
  def which(name)
    %w[pacman checkupdates].include?(name) ? "/usr/bin/#{name}" : nil
  end
  def run(*command, **_options)
    @commands << command
    return @checkupdates_result if command.first == "checkupdates"
    Result.new(stdout: "", stderr: "", exit_status: 1, status: "failed", truncated: false)
  end
end

class FakePackageAssessor
  def initialize(items)
    @items = items
  end
  def assess(include_updates:)
    raise "updates required" unless include_updates
    {
      "managers" => {
        "pacman" => {
          "detected" => true,
          "updates" => {
            "command" => "checkupdates --nocolor", "status" => (@items.empty? ? "no_updates" : "complete"),
            "exit_status" => (@items.empty? ? 2 : 0), "fresh" => true, "count" => @items.length, "items" => @items
          }
        }
      }
    }
  end
end

puts "A1–A3 deterministic verification:"

runner = PackageRunner.new(Result.new(stdout: "linux 6.0 -> 6.1\n", stderr: "", exit_status: 0, status: "ok", truncated: false))
report = SoulCore::PackageManagerAssessor.new(runner: runner).assess(include_updates: true)
check.call("fresh checkupdates output is complete", report.dig("managers","pacman","updates","status") == "complete" && report.dig("managers","pacman","updates","fresh") == true)
check.call("pacman -Qu is never used", runner.commands.none? { |command| command == ["pacman", "-Qu"] })

runner = PackageRunner.new(Result.new(stdout: "", stderr: "", exit_status: 2, status: "failed", truncated: false))
report = SoulCore::PackageManagerAssessor.new(runner: runner).assess(include_updates: true)
check.call("checkupdates exit 2 means no updates", report.dig("managers","pacman","updates","status") == "no_updates")

runner = PackageRunner.new(Result.new(stdout: "", stderr: "network failed", exit_status: 1, status: "failed", truncated: false))
report = SoulCore::PackageManagerAssessor.new(runner: runner).assess(include_updates: true)
check.call("failed update discovery remains failed", report.dig("managers","pacman","updates","status") == "failed" && report.dig("managers","pacman","updates","count") == 0)
check.call("failed update discovery carries bounded diagnostics", report.dig("managers","pacman","updates","error") == "network failed")

Dir.mktmpdir("soul-a1-a3-") do |root|
  FileUtils.mkdir_p(File.join(root, "Soul", "host_improvement", "plans"))
  assessor = FakePackageAssessor.new(["linux 6.0 -> 6.1"])
  pacman_log = File.join(root, "pacman.log")
  File.write(pacman_log, "[2026-07-16T11:00:00-0400] [ALPM] upgraded linux (6.0 -> 6.1)\n")
  host = SoulCore::HostImprovementPlanService.new(root: root, clock: -> { Time.utc(2026,7,16,12,0,0) }, package_assessor: assessor, pacman_log_path: pacman_log)
  preview = host.preview_arch_upgrade
  check.call("host preview is read-only", preview["ok"] && Dir.children(File.join(root,"Soul","host_improvement","plans")).empty?)
  wrong = host.create_arch_handoff(confirmation: "WRONG", expected_digest: preview.dig("data","expected_digest"))
  check.call("wrong host confirmation writes nothing", wrong["lifecycle_state"] == "blocked_for_human_review" && Dir.children(File.join(root,"Soul","host_improvement","plans")).empty?)
  created = host.create_arch_handoff(confirmation: SoulCore::HostImprovementPlanService::CONFIRMATION, expected_digest: preview.dig("data","expected_digest"))
  packet = created.dig("data","packet")
  handoff = packet && File.read(File.join(root, packet, "TERMINAL_HANDOFF.md"))
  check.call("exact gate creates only a review handoff", created["lifecycle_state"] == "blocked_for_human_review" && created.dig("data","host_command_executed") == false && handoff.include?("Soul did not execute"))
  receipt = host.verify(plan_id: created.dig("data","plan","plan_id"))
  check.call("host verification persists bounded typed receipt evidence", receipt.dig("data","receipt","schema_version") == "soul.host_improvement.receipt.v1" && receipt.dig("data","receipt","receipt_persisted") == true && receipt.dig("data","receipt","pacman_log_evidence","entry_count") == 1 && File.file?(File.join(root, receipt.dig("data","receipt","packet"))))

  repo = File.join(root, "repo")
  FileUtils.mkdir_p(File.join(repo, "lib")); FileUtils.mkdir_p(File.join(repo, "scripts")); FileUtils.mkdir_p(File.join(repo, "Soul", "augmentation", "proposals"))
  File.write(File.join(repo,"lib","sample.rb"), "module Sample; end\n")
  File.write(File.join(repo,"scripts","verify-sample.rb"), "puts 'ok'\n")
  File.write(File.join(repo,".env"), "SECRET=not-read\n")
  system("git", "init", "-q", repo) or raise "git init failed"
  system("git", "-C", repo, "add", "lib/sample.rb", "scripts/verify-sample.rb", ".env") or raise "git add failed"
  system("git", "-C", repo, "-c", "user.name=Soul Test", "-c", "user.email=soul@example.invalid", "commit", "-qm", "fixture") or raise "git commit failed"
  service = SoulCore::SelfAugmentationService.new(root: repo, clock: -> { Time.utc(2026,7,16,12,0,0) })
  census = service.census
  check.call("census is tracked, bounded, and excludes .env", census.dig("data","census","tracked_path_count") == 3 && census.dig("data","census","excluded_count") == 1 && census.dig("data","census","verifier_count") == 1)
  objective = "Introduce an explicit compatibility contract for core orchestration changes."
  why = "This changes shared application orchestration and cannot terminate as one bounded skill invocation."
  aug_preview = service.preview(objective: objective, why_not_skill: why)
  check.call("augmentation preview writes nothing", aug_preview["ok"] && Dir.children(File.join(repo,"Soul","augmentation","proposals")).empty?)
  blocked = service.create_proposal(objective: objective, why_not_skill: why, confirmation: "WRONG", expected_digest: aug_preview.dig("data","expected_digest"))
  check.call("wrong augmentation confirmation writes nothing", blocked["lifecycle_state"] == "blocked_for_human_review" && Dir.children(File.join(repo,"Soul","augmentation","proposals")).empty?)
  proposal = service.create_proposal(objective: objective, why_not_skill: why, confirmation: SoulCore::SelfAugmentationService::CONFIRMATION, expected_digest: aug_preview.dig("data","expected_digest"))
  check.call("exact gate creates proposal but no implementation", proposal["lifecycle_state"] == "blocked_for_human_review" && proposal.dig("data","implementation_started") == false && File.file?(File.join(repo,proposal.dig("data","packet"),"REVIEW.md")))

  facade = SoulCore::ApplicationFacade.new(root: repo, host_improvement_plan_service: host, self_augmentation_service: service, clock: -> { Time.utc(2026,7,16,12,0,0) })
  request = lambda do |operation, parameters = {}|
    facade.call({"schema_version"=>"soul.application.v1","request_id"=>"a1a3:#{Digest::SHA256.hexdigest(operation + JSON.generate(parameters))[0,12]}","operation"=>operation,"parameters"=>parameters,"context"=>{"interface"=>"dashboard_test"}})
  end
  api_census = request.call("self_augmentation.census")
  api_plans = request.call("host_improvement.plans.list", {"limit"=>10})
  check.call("application facade exposes bounded A2 and A3 projections", api_census["lifecycle_state"] == "complete" && api_plans["lifecycle_state"] == "complete" && api_plans.dig("data","count") == 1)

  File.symlink("lib/sample.rb", File.join(repo, "linked-source"))
  system("git", "-C", repo, "add", "linked-source") or raise "git add symlink failed"
  check.call("tracked symlinks fail the census closed", service.census["lifecycle_state"] == "failed")
end

operations = SoulCore::ApplicationContract::OPERATIONS
check.call("typed API operations are allowlisted", %w[host_improvement.arch_upgrade.preview host_improvement.arch_upgrade.handoff host_improvement.plans.verify self_augmentation.census self_augmentation.proposals.preview self_augmentation.proposals.execute].all? { |operation| operations.key?(operation) })

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("dashboard exposes four-tab augmentation and host surfaces", html.include?('id="augmentation-tab"') && html.include?('id="augmentation-panel"') && html.include?('id="preview-host-plan"'))
check.call("deferred augmentation stages are visibly locked", html.include?("Experiment</strong><small>Locked") && html.include?("Review</strong><small>Locked"))
check.call("new surfaces do not poll or schedule", !js.match?(/setInterval|setTimeout|requestAnimationFrame/))
check.call("brief preserves prohibited boundaries", File.read(File.expand_path("../docs/soul/SELF_AUGMENTATION_HOST_IMPROVEMENT_A1_A3_BRIEF.md", __dir__)).include?("Invoking Codex") )

abort "Verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Verification complete."
