#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../lib/soul_core/atelier_cis_hardening_a2"

failures = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'failed'}"
  failures << label unless condition
end

puts "Atelier CIS hardening A2 verification:"
root_service = SoulCore::AtelierCisHardeningA2.new(system_root: "/", euid: 1)
check.call("live root paths remain contained without requiring a double slash",
  root_service.send(:system_path, SoulCore::AtelierCisHardeningA2::SYSCTL_PATH) == SoulCore::AtelierCisHardeningA2::SYSCTL_PATH)
check.call("shared bounded runner receives its supported timeout interface",
  root_service.send(:run, "/usr/bin/true", timeout: 1).success?)
Dir.mktmpdir("soul-atelier-cis-a2") do |root|
  pam = File.join(root, "etc/pam.d/su")
  FileUtils.mkdir_p(File.dirname(pam))
  File.binwrite(pam, SoulCore::AtelierCisHardeningA2::PAM_ORIGINAL)
  service = SoulCore::AtelierCisHardeningA2.new(system_root: root, euid: 0)
  plan = service.plan
  digest = plan.dig("data", "expected_digest")

  check.call("plan is digest-bound and explicitly gated", digest.match?(/\A[0-9a-f]{64}\z/) &&
    plan.dig("data", "confirmation_phrase") == SoulCore::AtelierCisHardeningA2::CONFIRM_INSTALL)
  check.call("plan preserves forwarding, password policy, var/tmp, and process boundaries",
    !plan.dig("data", "ipv4_forwarding_changed") && !plan.dig("data", "password_policy_changed") &&
    !plan.dig("data", "var_tmp_layout_changed") && !plan.dig("data", "persistent_process_added"))

  begin
    service.install(expected_digest: "0" * 64, confirmation: SoulCore::AtelierCisHardeningA2::CONFIRM_INSTALL)
    blocked = false
  rescue StandardError => error
    blocked = error.message.include?("digest changed")
  end
  check.call("stale digest fails closed", blocked)

  installed = service.install(expected_digest: digest, confirmation: SoulCore::AtelierCisHardeningA2::CONFIRM_INSTALL)
  check.call("exact transaction completes", installed["lifecycle_state"] == "complete" && installed.dig("data", "ready"))
  check.call("PAM enables required wheel membership without trust",
    File.read(pam).match?(/^auth\s+required\s+pam_wheel\.so\s+use_uid$/) &&
    !File.read(pam).match?(/^auth\s+sufficient\s+pam_wheel\.so/))
  check.call("sysctl scope excludes forwarding", !File.read(File.join(root, SoulCore::AtelierCisHardeningA2::SYSCTL_PATH.delete_prefix("/"))).include?("ip_forward"))
  check.call("mount auditing covers both ABIs", %w[b64 b32].all? { |arch| File.read(File.join(root, SoulCore::AtelierCisHardeningA2::AUDIT_PATH.delete_prefix("/"))).include?("arch=#{arch} -S mount") })
  check.call("live activation adds and rollback deletes only exact mount rules",
    SoulCore::AtelierCisHardeningA2::AUDIT_RULE_ARGUMENTS.values.all? { |arguments| arguments.first == "-a" && arguments.include?("mount") && arguments.include?("mounts") })

  File.write(File.join(root, SoulCore::AtelierCisHardeningA2::SYSCTL_PATH.delete_prefix("/")), "drift\n")
  begin
    service.install(expected_digest: digest, confirmation: SoulCore::AtelierCisHardeningA2::CONFIRM_INSTALL)
    collision = false
  rescue StandardError => error
    collision = error.message.include?("collision")
  end
  check.call("managed-file drift fails closed", collision)
  File.binwrite(File.join(root, SoulCore::AtelierCisHardeningA2::SYSCTL_PATH.delete_prefix("/")), SoulCore::AtelierCisHardeningA2::SYSCTL_CONTENT)

  removed = service.remove(expected_digest: digest, confirmation: SoulCore::AtelierCisHardeningA2::CONFIRM_REMOVE)
  check.call("rollback removes additions and restores PAM baseline", removed["lifecycle_state"] == "complete" &&
    File.binread(pam) == SoulCore::AtelierCisHardeningA2::PAM_ORIGINAL &&
    !File.exist?(File.join(root, SoulCore::AtelierCisHardeningA2::SYSCTL_PATH.delete_prefix("/"))) &&
    !File.exist?(File.join(root, SoulCore::AtelierCisHardeningA2::AUDIT_PATH.delete_prefix("/"))))
end

abort("Atelier CIS hardening A2 failed: #{failures.join(', ')}") unless failures.empty?
puts "Atelier CIS hardening A2 verification passed."
