#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "time"
require_relative "../lib/soul_core/memory_projection_remote_installer"

errors = []
checks = 0
check = lambda do |label, condition|
  checks += 1
  errors << label unless condition
end

Dir.mktmpdir("memory-projection-a20-") do |root|
  private_root = File.join(root, "Soul", "private", "memory", "projection")
  FileUtils.mkdir_p(private_root, mode: 0o700)
  manifest = JSON.parse(File.binread(File.join(__dir__, "..", "config", "memory_projection_deployment_a19.json")))
  manifest_path = File.join(root, "manifest.json")
  File.write(manifest_path, JSON.generate(manifest), mode: "wb")
  files = %w[ca.crt server.crt server.key ssh.pub qdrant.key falkordb.key qdrant.deb falkordb.so]
  files.each_with_index do |name, index|
    path = File.join(private_root, name)
    File.write(path, "fixture-#{index}-#{"x" * 64}\n", mode: "wb")
    File.chmod(0o600, path)
  end
  evidence_path = File.join(private_root, "preflight.json")
  File.write(evidence_path, JSON.generate({
    "schema_version" => "soul.memory-projection.preflight.a20.v1", "observed_at" => Time.now.utc.iso8601,
    "target_alias" => "foundry", "vmid_free" => true, "address_free" => true,
    "available_memory_bytes" => 8 * 1024 * 1024 * 1024, "available_storage_bytes" => 64 * 1024 * 1024 * 1024
  }), mode: "wb")
  File.chmod(0o600, evidence_path)
  config_path = File.join(private_root, "deployment.json")
  config = {
    "schema_version" => "soul.memory-projection.private.a20.v1", "target_alias" => "foundry", "vmid" => 102,
    "guest_hostname" => "archive", "fqdn" => "archive.herz.soul", "ipv4" => "192.168.124.16",
    "gateway" => "192.168.124.1", "client_ipv4" => "192.168.124.3", "nameserver" => "192.168.124.4",
    "template" => "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst", "preflight_evidence_path" => evidence_path,
    "ca_certificate_path" => File.join(private_root, "ca.crt"), "server_certificate_path" => File.join(private_root, "server.crt"),
    "server_key_path" => File.join(private_root, "server.key"), "ssh_public_key_path" => File.join(private_root, "ssh.pub"),
    "qdrant_api_key_path" => File.join(private_root, "qdrant.key"), "falkordb_password_path" => File.join(private_root, "falkordb.key"),
    "qdrant_artifact_path" => File.join(private_root, "qdrant.deb"), "falkordb_artifact_path" => File.join(private_root, "falkordb.so")
  }
  File.write(config_path, JSON.generate(config), mode: "wb")
  File.chmod(0o600, config_path)

  executed = []
  runner = lambda do |command|
    executed << command
    {"success" => true, "stdout" => "", "stderr" => ""}
  end
  service = SoulCore::MemoryProjectionRemoteInstaller.new(root: root, manifest_path: manifest_path, private_config_path: config_path, runner: runner)
  planned = service.plan
  data = planned.fetch("data")
  check.call("fresh plan is review gated", !planned["ok"] && planned["lifecycle_state"] == "blocked_for_human_review")
  check.call("plan has exact confirmation and digest", data["confirmation_phrase"] == "INSTALL_SOUL_MEMORY_PROJECTION" && data["expected_digest"].match?(/\A[0-9a-f]{64}\z/))
  check.call("plan contains no private paths or secrets", !JSON.generate(planned).include?(private_root) && !JSON.generate(planned).include?("fixture-"))
  check.call("plan binds fresh evidence", data["preflight_evidence_sha256"].match?(/\A[0-9a-f]{64}\z/) && data["preflight_observed_at"])
  rejected = service.install(confirmation: "INSTALL_SOUL_MEMORY_PROJECTION", expected_digest: "0" * 64)
  check.call("stale digest executes nothing", rejected["lifecycle_state"] == "blocked_for_human_review" && executed.empty?)
  installed = service.install(confirmation: data["confirmation_phrase"], expected_digest: data["expected_digest"])
  check.call("exact install completes through four bounded commands", installed["ok"] && executed.length == 4)
  check.call("fixed commands use exact target and guest", executed.flatten.join(" ").include?("foundry") && executed.flatten.join(" ").include?("pct create 102"))
  check.call("credentials never appear in command argv", !executed.flatten.join(" ").include?("fixture-"))
  check.call("installer enforces TLS-only services", service.send(:install_script, config).include?("port 0") && service.send(:install_script, config).include?("enable_tls: true"))
  check.call("installer disables browser and gRPC exposure", service.send(:install_script, config).include?("grpc_port: null") && service.send(:install_script, config).include?("enable_cors: false"))
  check.call("installer applies bounded service memory", service.send(:install_script, config).scan("MemoryMax=768M").length == 2 && service.send(:install_script, config).include?("maxmemory 512mb"))
  check.call("installer limits LAN ingress to exact client", service.send(:install_script, config).include?("ip saddr 192.168.124.3 tcp dport { 22, 6333, 6379 } accept"))
  check.call("unprivileged LXC compatibility is narrow", service.send(:install_script, config).include?("PrivateUsers=false") && !service.send(:install_script, config).include?("nesting=1"))
  check.call("shared TLS key has a dedicated service group", service.send(:install_script, config).include?("soul-memory-tls"))
  check.call("FalkorDB runtime dependency is installed", service.send(:install_script, config).include?("libgomp1") && service.send(:repair_script).include?("libgomp1"))
  check.call("FalkorDB module directory is traversable only by Redis", service.send(:install_script, config).include?("chown root:redis /usr/lib/falkordb") && service.send(:repair_script).include?("chmod 0750 /usr/lib/falkordb"))
  check.call("firewall policy is reloaded before acceptance", service.send(:install_script, config).include?("systemctl restart nftables ssh qdrant redis-server") && service.send(:repair_script).include?("systemctl restart nftables qdrant redis-server"))
  File.write(evidence_path, JSON.generate(JSON.parse(File.binread(evidence_path)).merge("observed_at" => (Time.now.utc - 700).iso8601)), mode: "wb")
  File.chmod(0o600, evidence_path)
  stale = service.plan
  check.call("stale preflight fails closed", stale["lifecycle_state"] == "failed" && stale["reason"].include?("stale"))
end

abort "Memory projection installer A20 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Memory projection installer A20 verification passed (#{checks} checks)."
