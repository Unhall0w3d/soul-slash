#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../lib/soul_core/memory_projection_deployment_plan"

root = File.expand_path("..", __dir__)
manifest_path = File.join(root, "config", "memory_projection_deployment_a19.json")
manifest = JSON.parse(File.read(manifest_path))
errors = []
checks = 0
check = lambda do |name, condition|
  checks += 1
  errors << name unless condition
end

check.call("manifest remains review gated", manifest["state"] == "candidate_review_required" && manifest["persistent_deployment_authorized"] == false)
check.call("guest is bounded unprivileged Debian without nesting", manifest["central_guest"] == {
  "isolation" => "dedicated_unprivileged_debian_13_lxc",
  "cpu_cores" => 2, "memory_mib" => 2048, "swap_mib" => 512,
  "root_volume_gib" => 24, "autostart" => true,
  "nested_container_runtime" => false, "owner_private_identity_and_address" => true
})
check.call("Qdrant release is exact", manifest.dig("components", "qdrant", "version") == "1.19.0" && manifest.dig("components", "qdrant", "sha256") == "2c73614176642aeb8da5127fb583b4a63398e89c05c87eb2dc12faf1ad9c19ea")
check.call("FalkorDB release is exact", manifest.dig("components", "falkordb", "version") == "4.20.4" && manifest.dig("components", "falkordb", "sha256") == "81ea6b989dc2fd4c9ad905e246018b220b02f0e40c406255f9da4768c1684555")
check.call("Redis 8 comes from signed Debian", manifest.dig("components", "redis", "minimum_version") == "8.0.0" && manifest.dig("components", "redis", "source") == "signed_debian_13_repository")
check.call("licenses are explicit", manifest.dig("components", "qdrant", "license") == "Apache-2.0" && manifest.dig("components", "falkordb", "license") == "SSPL-1.0")
check.call("database network is TLS authenticated and fixed-client", manifest.dig("network", "qdrant_listener") == "tls_6333_fixed_client_only" && manifest.dig("network", "falkordb_listener") == "tls_6379_fixed_client_only" && manifest.dig("network", "database_authentication") == "required")
check.call("no public plaintext or browser surface", manifest.dig("network", "public_ingress") == false && manifest.dig("network", "plaintext_database_ports") == false && manifest.dig("network", "browser_ui") == false)
check.call("projection cannot become authority", manifest.dig("projection", "authority") == "conversation_memory_ledger" && manifest.dig("authority", "canonical_memory_mutation") == "none" && manifest.dig("authority", "remote_to_canonical_sync") == "prohibited")
check.call("raw content remains local", manifest.dig("projection", "raw_memory_text_remote") == false)
check.call("projection remains rebuildable", manifest.dig("durability", "projection_data_backup") == false && manifest.dig("durability", "configuration_and_credentials_backup") == true && manifest.dig("durability", "rebuild_from_canonical") == true)

parameters = {
  "target_alias" => "secondary-host",
  "vmid" => 102,
  "fqdn" => "memory.internal.example",
  "ipv4" => "192.168.50.16",
  "gateway" => "192.168.50.1",
  "client_ipv4" => "192.168.50.3",
  "client_ca_sha256" => "1" * 64,
  "server_certificate_sha256" => "2" * 64,
  "qdrant_api_key_sha256" => "3" * 64,
  "falkordb_password_sha256" => "4" * 64,
  "ssh_public_key_sha256" => "5" * 64
}
planner = SoulCore::MemoryProjectionDeploymentPlan.new(manifest_path: manifest_path)
first = planner.plan(parameters)
second = planner.plan(parameters)
data = first.fetch("data")
check.call("plan is stable and review blocked", first == second && first["lifecycle_state"] == "blocked_for_human_review")
check.call("plan requires exact phrase and digest", data["confirmation_phrase"] == "INSTALL_SOUL_MEMORY_PROJECTION" && data["expected_digest"].match?(/\A[0-9a-f]{64}\z/))
check.call("plan contains bounded phases", data["phases"].length == 11 && data["automatic_retry"] == false)
check.call("receipt contains no secret values or paths", !data.to_s.match?(/\/home\/|\.pem|PRIVATE KEY|BEGIN CERTIFICATE/i))
check.call("plan grants no canonical mutation", data.dig("authority", "canonical_memory_mutation") == "none")

public_address = planner.plan(parameters.merge("ipv4" => "8.8.8.8"))
check.call("public guest address fails closed", public_address["lifecycle_state"] == "failed")
outside_client = planner.plan(parameters.merge("client_ipv4" => "192.168.60.3"))
check.call("out-of-subnet client fails closed", outside_client["lifecycle_state"] == "failed")
same_credentials = planner.plan(parameters.merge("falkordb_password_sha256" => "3" * 64))
check.call("reused database credentials fail closed", same_credentials["lifecycle_state"] == "failed")
missing_tls = parameters.reject { |key, _value| key == "server_certificate_sha256" }
check.call("missing TLS evidence fails closed", planner.plan(missing_tls)["lifecycle_state"] == "failed")

Dir.mktmpdir("soul-a19") do |directory|
  drifted = Marshal.load(Marshal.dump(manifest))
  drifted["projection"]["raw_memory_text_remote"] = true
  path = File.join(directory, "manifest.json")
  File.write(path, JSON.pretty_generate(drifted))
  rejected = SoulCore::MemoryProjectionDeploymentPlan.new(manifest_path: path).plan(parameters)
  check.call("raw remote memory manifest fails closed", rejected["lifecycle_state"] == "failed")
end

public_files = [
  manifest_path,
  File.join(root, "docs", "soul", "MEMORY_PROJECTION_DEPLOYMENT_A19_BRIEF.md"),
  File.join(root, "lib", "soul_core", "memory_projection_deployment_plan.rb")
]
public_text = public_files.map { |path| File.read(path) }.join("\n")
check.call("public assets omit owner deployment identity", !public_text.match?(/192\.168\.124|\b(?:atelier|foundry|bhones)\b/i))

source = File.read(File.join(root, "lib", "soul_core", "memory_projection_deployment_plan.rb"))
check.call("planner performs no network process or persistence work", %w[Net::HTTP TCPSocket system( spawn( exec( fork( File.write FileUtils].none? { |token| source.include?(token) })

abort "Memory projection deployment A19 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Memory projection deployment A19 verification passed (#{checks} checks)."
