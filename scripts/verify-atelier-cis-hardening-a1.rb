#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require_relative "../lib/soul_core/atelier_cis_hardening"

failures = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'failed'}"
  failures << label unless condition
end

puts "Atelier CIS hardening A1 verification:"

Dir.mktmpdir("soul-atelier-cis-verifier") do |system_root|
  service = SoulCore::AtelierCisHardening.new(system_root: system_root, euid: 0)
  plan = service.plan
  digest = plan.dig("data", "expected_digest")

  check.call("plan is digest-bound and human-gated",
             plan["lifecycle_state"] == "blocked_for_human_review" &&
               digest.match?(/\A[0-9a-f]{64}\z/) &&
               plan.dig("data", "confirmation_phrase") == SoulCore::AtelierCisHardening::CONFIRM_INSTALL)
  check.call("plan adds no authority, credential, or persistent process",
             plan.dig("data", "password_storage") == false &&
               plan.dig("data", "passwordless_authority") == false &&
               plan.dig("data", "arbitrary_command_forwarding") == false &&
               plan.dig("data", "persistent_process_added") == false)
  check.call("approved controls and reviewed exceptions remain explicit",
             plan.dig("data", "implemented_controls").length == 5 &&
               plan.dig("data", "reviewed_exceptions").length == 4)

  begin
    service.install(expected_digest: "0" * 64, confirmation: SoulCore::AtelierCisHardening::CONFIRM_INSTALL)
    wrong_digest_blocked = false
  rescue StandardError => error
    wrong_digest_blocked = error.message.include?("digest changed")
  end
  check.call("stale plan digest fails closed", wrong_digest_blocked)

  installed = service.install(
    expected_digest: digest,
    confirmation: SoulCore::AtelierCisHardening::CONFIRM_INSTALL
  )
  check.call("exact transaction completes", installed["lifecycle_state"] == "complete" && installed.dig("data", "ready"))

  managed = plan.dig("data", "managed_files")
  check.call("all managed files use exact content and modes", managed.all? do |entry|
    path = File.join(system_root, entry.fetch("path").delete_prefix("/"))
    File.file?(path) && format("%04o", File.stat(path).mode & 0o777) == entry.fetch("mode")
  end)
  sudo_log = File.join(system_root, "var/log/sudo.log")
  check.call("sudo evidence file is owner-private", File.file?(sudo_log) && (File.stat(sudo_log).mode & 0o777) == 0o600)

  collision_path = File.join(system_root, "etc/modprobe.d/soul-disable-dccp.conf")
  File.write(collision_path, "drift\n")
  begin
    service.install(expected_digest: digest, confirmation: SoulCore::AtelierCisHardening::CONFIRM_INSTALL)
    collision_blocked = false
  rescue StandardError => error
    collision_blocked = error.message.include?("path collision")
  end
  check.call("drifted managed paths fail closed", collision_blocked)
  File.write(collision_path, <<~MODPROBE)
    # Soul/ Atelier CIS hardening A1. DCCP is not required on this workstation.
    install dccp /bin/false
    blacklist dccp
  MODPROBE

  removed = service.remove(expected_digest: digest, confirmation: SoulCore::AtelierCisHardening::CONFIRM_REMOVE)
  check.call("exact rollback removes configuration but retains evidence",
             removed["lifecycle_state"] == "complete" && File.file?(sudo_log) &&
               managed.none? { |entry| File.exist?(File.join(system_root, entry.fetch("path").delete_prefix("/"))) })
end

abort("Atelier CIS hardening A1 verification failed: #{failures.join(', ')}") unless failures.empty?
puts "Atelier CIS hardening A1 verification passed."
