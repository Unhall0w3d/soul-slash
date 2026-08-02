#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "time"
require_relative "../lib/soul_core/package_manager_assessor"
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

  facade = SoulCore::ApplicationFacade.new(root: repo, self_augmentation_service: service, clock: -> { Time.utc(2026,7,16,12,0,0) })
  request = lambda do |operation, parameters = {}|
    facade.call({"schema_version"=>"soul.application.v1","request_id"=>"a1a3:#{Digest::SHA256.hexdigest(operation + JSON.generate(parameters))[0,12]}","operation"=>operation,"parameters"=>parameters,"context"=>{"interface"=>"dashboard_test"}})
  end
  api_census = request.call("self_augmentation.census")
  check.call("application facade exposes bounded augmentation projections", api_census["lifecycle_state"] == "complete")

  File.symlink("lib/sample.rb", File.join(repo, "linked-source"))
  system("git", "-C", repo, "add", "linked-source") or raise "git add symlink failed"
  check.call("tracked symlinks fail the census closed", service.census["lifecycle_state"] == "failed")
end

operations = SoulCore::ApplicationContract::OPERATIONS
check.call("typed augmentation operations remain allowlisted", %w[self_augmentation.census self_augmentation.proposals.preview self_augmentation.proposals.execute].all? { |operation| operations.key?(operation) })
check.call("retired Arch handoff operations are not callable", operations.keys.grep(/\Ahost_improvement\./).empty?)

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("dashboard retains augmentation and removes the overlapping Arch handoff", html.include?('id="augmentation-tab"') && html.include?('id="augmentation-panel"') && !html.include?('id="preview-host-plan"'))
check.call("A1–A3 surfaces remain present after later gate expansion", html.include?("Observe</strong>") && html.include?("Propose</strong>") && html.include?('id="augmentation-objective"'))
bounded_surfaces = js[/function renderAugmentationProposals\(records\).*?function reviewEmpty\(/m].to_s
check.call("new surfaces do not poll or schedule", !bounded_surfaces.match?(/setInterval|setTimeout|requestAnimationFrame/))
check.call("brief preserves prohibited boundaries", File.read(File.expand_path("../docs/soul/SELF_AUGMENTATION_HOST_IMPROVEMENT_A1_A3_BRIEF.md", __dir__)).include?("Invoking Codex") )

abort "Verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Verification complete."
