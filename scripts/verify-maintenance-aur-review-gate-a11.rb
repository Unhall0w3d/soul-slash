#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/maintenance_aur_review_runner"
require_relative "../lib/soul_core/maintenance_desktop_handoff"

failures = []
puts "Maintenance AUR review gate A11 verification:"
check = lambda do |description, condition|
  puts "- #{description}: #{condition ? 'ok' : 'FAILED'}"
  failures << description unless condition
end

vector = SoulCore::MaintenanceAurReviewRunner::FIXED_YAY_VECTOR
check.call(
  "fixed AUR vector is interactive, AUR-only, and removes configured auto-answers",
  vector.take(3) == ["/usr/bin/yay", "--aur", "-Sua"] &&
    %w[--cleanmenu --diffmenu --editmenu --noanswerclean --noanswerdiff --noansweredit --noanswerupgrade].all? { |flag| vector.include?(flag) } &&
    !vector.include?("--noconfirm") && !vector.any? { |item| item.start_with?("--answer") } &&
    !vector.any? { |item| item.include?(";") || item.include?("|") }
)

calls = []
runner = SoulCore::MaintenanceAurReviewRunner.new(
  command_executor: lambda do |argv, timeout|
    calls << [argv, timeout]
    0
  end,
  output: StringIO.new
)
complete = runner.run
check.call(
  "review runner authenticates once, runs only the fixed vector, and invalidates sudo",
  complete["lifecycle_state"] == "complete" && complete["password_prompts"] == 1 &&
    complete["sudo_ticket_invalidated"] == true &&
    calls.map(&:first) == [["/usr/bin/sudo", "-v"], vector, ["/usr/bin/sudo", "-k"]]
)

failed_calls = []
failed_runner = SoulCore::MaintenanceAurReviewRunner.new(
  command_executor: lambda do |argv, _timeout|
    failed_calls << argv
    argv == vector ? 1 : 0
  end,
  output: StringIO.new
)
failed = failed_runner.run
check.call(
  "declined or failed AUR review terminates and still invalidates sudo",
  failed["lifecycle_state"] == "failed" && failed_calls.last == ["/usr/bin/sudo", "-k"]
)

class A11Assessor
  attr_accessor :items

  def initialize(items)
    @items = items
  end

  def assess(include_updates:)
    raise "updates must be requested" unless include_updates
    {
      "status" => "ok",
      "read_only" => true,
      "preferred_aur_helper" => "yay",
      "managers" => {
        "pacman" => {"detected" => true, "updates" => {"status" => "no_updates", "count" => 0, "items" => [], "truncated" => false}},
        "yay" => {"detected" => true, "updates" => {"status" => "complete", "count" => @items.length, "items" => @items, "truncated" => false}},
        "flatpak" => {"detected" => true, "updates" => {"status" => "no_results", "count" => 0, "items" => [], "truncated" => false}}
      },
      "reboot" => {"status" => "complete", "fresh" => true, "recommended" => false}
    }
  end
end

class A11ReviewRunner
  attr_reader :calls

  def initialize
    @calls = 0
  end

  def run
    @calls += 1
    {
      "lifecycle_state" => "complete",
      "exit_status" => 0,
      "reason" => "reviewed package set completed",
      "password_prompts" => 1,
      "sudo_ticket_invalidated" => true
    }
  end
end

Dir.mktmpdir("soul-aur-review-a11") do |temporary|
  now = Time.utc(2026, 8, 2, 12, 0, 0)
  assessor = A11Assessor.new(["webex-bin 46.6.1-1 -> 46.7.0-1"])
  review_runner = A11ReviewRunner.new
  ids = %w[0123456789abcdef fedcba9876543210 0011223344556677].each
  handoff = SoulCore::MaintenanceDesktopHandoff.new(
    root: temporary,
    home: temporary,
    clock: -> { now },
    package_assessor: assessor,
    aur_review_runner_factory: -> { review_runner },
    id_generator: -> { ids.next }
  )

  evidence = handoff.reserve_evidence
  evidence_result = handoff.handle_uri(evidence.fetch("launch_uri"))
  reservation = handoff.reserve_aur_review
  check.call(
    "fresh native evidence creates a bounded digest-bound AUR review URI",
    evidence_result["ok"] &&
      reservation["launch_uri"].match?(%r{\Asoul-maintenance://aur-review/maintenance_aur_review_[a-f0-9]{16}/[a-f0-9]{64}\z}) &&
      reservation["package_items"] == assessor.items
  )

  result = handoff.handle_uri(reservation.fetch("launch_uri"))
  receipt = result.dig("data", "aur_review_receipt") || {}
  check.call(
    "unchanged reviewed package set invokes one runner and writes a redacted receipt",
    result["ok"] && result["lifecycle_state"] == "complete" && review_runner.calls == 1 &&
      receipt["package_names"] == ["webex-bin"] && receipt["interactive_review_required"] == true &&
      receipt["redacted"] == true && receipt["sudo_ticket_invalidated"] == true
  )

  replay = handoff.handle_uri(reservation.fetch("launch_uri"))
  check.call("AUR review URI is single-use", !replay["ok"] && review_runner.calls == 1)

  fresh = handoff.reserve_aur_review
  assessor.items = ["webex-bin 46.6.1-1 -> 46.7.0-1", "new-aur-package 1 -> 2"]
  changed = handoff.handle_uri(fresh.fetch("launch_uri"))
  check.call(
    "changed AUR package set fails closed before execution",
    !changed["ok"] && changed["reason"].include?("package set changed") && review_runner.calls == 1
  )
end

dashboard = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
markup = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
contract = File.read(File.expand_path("../lib/soul_core/application_contract.rb", __dir__))
check.call(
  "Dashboard and API expose a separate AUR review operation with strict URI handling",
  dashboard.include?("maintenance.aur_review.reserve") && dashboard.include?("reviewAurUpdates") &&
    dashboard.include?("aur-review") && markup.include?("review-aur-updates") &&
    contract.include?(%q{"maintenance.aur_review.reserve"})
)

if failures.empty?
  puts "Maintenance AUR review gate A11 verification passed."
  exit 0
end

warn "Maintenance AUR review gate A11 verification failed: #{failures.join(', ')}"
exit 1
