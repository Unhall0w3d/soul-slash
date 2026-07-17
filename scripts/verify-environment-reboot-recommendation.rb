#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "time"
require_relative "../lib/soul_core/package_manager_assessor"
require_relative "../lib/soul_core/environment_assessor"

failures = []
check = lambda do |name, condition|
  puts "- #{name}: #{condition ? 'ok' : 'FAILED'}"
  failures << name unless condition
end

Result = Struct.new(:stdout, :stderr, :exit_status, :status, :truncated, keyword_init: true) do
  def success? = status == "ok"
end

class RebootFixtureRunner
  def which(name) = %w[pacman checkupdates].include?(name) ? "/usr/bin/#{name}" : nil
  def run(*command, **_options)
    exit_status = command.first == "checkupdates" ? 2 : 1
    Result.new(stdout: "", stderr: "", exit_status: exit_status, status: "failed", truncated: false)
  end
end

puts "Environment reboot recommendation verification:"

Dir.mktmpdir("soul-reboot-evidence-") do |root|
  now = Time.iso8601("2026-07-17T03:00:00-04:00")
  uptime = File.join(root, "uptime")
  log = File.join(root, "pacman.log")
  File.write(uptime, "3600.00 0.00\n")
  runner = RebootFixtureRunner.new

  File.write(log, "[2026-07-17T02:18:47-0400] [ALPM-SCRIPTLET] ==> INFO: Reboot is recommended due to the upgrade of core system package(s).\n")
  report = SoulCore::PackageManagerAssessor.new(runner: runner, clock: -> { now }, pacman_log_path: log, uptime_path: uptime).assess(include_updates: true)
  check.call("post-boot CachyOS hook evidence recommends reboot", report.dig("reboot", "status") == "complete" && report.dig("reboot", "recommended") == true && report.dig("reboot", "fresh") == true)

  environment = SoulCore::EnvironmentAssessor.new(root: root, runner: runner, clock: -> { now }, pacman_log_path: log, uptime_path: uptime).assess(include_updates: true)
  check.call("environment projection adds an operator-timed reboot recommendation", environment["recommendations"].any? { |item| item["title"] == "System reboot recommended" && item["action"].include?("operator-chosen") })

  File.write(log, "[2026-07-17T01:30:00-0400] [ALPM-SCRIPTLET] ==> INFO: Reboot is recommended due to the upgrade of core system package(s).\n")
  report = SoulCore::PackageManagerAssessor.new(runner: runner, clock: -> { now }, pacman_log_path: log, uptime_path: uptime).assess(include_updates: true)
  check.call("recommendation from before this boot is cleared", report.dig("reboot", "recommended") == false)

  File.write(log, "[2026-07-17T02:18:47-0400] [ALPM] running 'cachyos-reboot-required.hook'...\n")
  report = SoulCore::PackageManagerAssessor.new(runner: runner, clock: -> { now }, pacman_log_path: log, uptime_path: uptime).assess(include_updates: true)
  check.call("hook execution without its exact recommendation is not a reboot request", report.dig("reboot", "recommended") == false)

  FileUtils.rm_f(log)
  report = SoulCore::PackageManagerAssessor.new(runner: runner, clock: -> { now }, pacman_log_path: log, uptime_path: uptime).assess(include_updates: true)
  check.call("missing pacman log fails unavailable rather than claiming no reboot", report.dig("reboot", "status") == "unavailable" && report.dig("reboot", "recommended").nil?)

  target = File.join(root, "target.log")
  File.write(target, "")
  File.symlink(target, log)
  report = SoulCore::PackageManagerAssessor.new(runner: runner, clock: -> { now }, pacman_log_path: log, uptime_path: uptime).assess(include_updates: true)
  check.call("symlinked evidence path fails closed", report.dig("reboot", "status") == "unavailable")
end

abort "#{failures.length} verification(s) failed: #{failures.join(', ')}" unless failures.empty?
puts "Environment reboot recommendation verification passed."
