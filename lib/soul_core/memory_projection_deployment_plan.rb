# frozen_string_literal: true

require "digest"
require "ipaddr"
require "json"

module SoulCore
  class MemoryProjectionDeploymentPlan
    SCHEMA = "soul.memory_projection_deployment_plan.a19.v1"
    CONFIRM_INSTALL = "INSTALL_SOUL_MEMORY_PROJECTION"
    REQUIRED_DIGEST_KEYS = %w[
      client_ca_sha256 server_certificate_sha256 qdrant_api_key_sha256
      falkordb_password_sha256 ssh_public_key_sha256
    ].freeze

    def initialize(manifest_path:)
      @manifest_path = File.expand_path(manifest_path.to_s)
    end

    def plan(parameters)
      manifest = load_manifest
      normalized = normalize_parameters(parameters)
      phases = [
        "fresh_foundry_capacity_and_collision_preflight",
        "create_exact_unprivileged_debian_guest",
        "install_signed_debian_redis_8",
        "verify_and_install_pinned_qdrant_release",
        "verify_and_install_pinned_falkordb_module",
        "install_owner_private_tls_and_credentials",
        "apply_fixed_client_firewall",
        "start_and_verify_hardened_services",
        "build_and_verify_initial_projection_generation",
        "prove_local_fallback_and_rollback",
        "retain_content_free_deployment_receipt"
      ]
      scope = {
        "schema" => SCHEMA,
        "manifest_digest" => Digest::SHA256.hexdigest(File.binread(@manifest_path)),
        "target" => normalized.slice("target_alias", "vmid", "fqdn", "ipv4", "gateway", "client_ipv4"),
        "evidence_digests" => normalized.slice(*REQUIRED_DIGEST_KEYS),
        "guest" => manifest.fetch("central_guest"),
        "components" => manifest.fetch("components"),
        "network" => manifest.fetch("network"),
        "projection" => manifest.fetch("projection"),
        "durability" => manifest.fetch("durability"),
        "authority" => manifest.fetch("authority"),
        "rollback" => manifest.fetch("rollback"),
        "phases" => phases,
        "automatic_retry" => false,
        "external_publication" => false
      }
      {
        "ok" => false,
        "lifecycle_state" => "blocked_for_human_review",
        "reason" => "Memory projection deployment requires exact reviewed confirmation.",
        "data" => scope.merge(
          "confirmation_phrase" => CONFIRM_INSTALL,
          "expected_digest" => digest(scope),
          "content_included" => false,
          "mutation" => "none"
        ),
        "mutation" => "none"
      }
    rescue StandardError => error
      {
        "ok" => false,
        "lifecycle_state" => "failed",
        "reason" => "Memory projection deployment plan failed safely: #{error.class}: #{error.message}",
        "mutation" => "none"
      }
    end

    private

    def load_manifest
      raise "deployment manifest is absent" unless File.file?(@manifest_path) && !File.symlink?(@manifest_path)
      manifest = JSON.parse(File.binread(@manifest_path))
      raise "deployment manifest schema mismatch" unless manifest["schema_version"] == "soul.memory-projection.deployment.a19.v1"
      raise "persistent deployment must remain review gated" unless manifest["persistent_deployment_authorized"] == false
      raise "nested container runtime is prohibited" unless manifest.dig("central_guest", "nested_container_runtime") == false
      raise "raw remote memory content is prohibited" unless manifest.dig("projection", "raw_memory_text_remote") == false
      raise "reverse synchronization is prohibited" unless manifest.dig("projection", "reverse_synchronization") == false
      raise "canonical mutation authority is prohibited" unless manifest.dig("authority", "canonical_memory_mutation") == "none"
      raise "public ingress is prohibited" unless manifest.dig("network", "public_ingress") == false
      raise "plaintext database ports are prohibited" unless manifest.dig("network", "plaintext_database_ports") == false
      raise "database browser UI is prohibited" unless manifest.dig("network", "browser_ui") == false
      validate_component!(manifest.fetch("components").fetch("qdrant"), expected_version: "1.19.0")
      validate_component!(manifest.fetch("components").fetch("falkordb"), expected_version: "4.20.4")
      raise "Redis source is not signed Debian 13" unless manifest.dig("components", "redis", "source") == "signed_debian_13_repository"
      raise "Redis minimum version is invalid" unless manifest.dig("components", "redis", "minimum_version") == "8.0.0"
      manifest
    rescue JSON::ParserError
      raise "deployment manifest JSON is malformed"
    end

    def validate_component!(component, expected_version:)
      raise "component version mismatch" unless component.fetch("version") == expected_version
      raise "component URL is not a fixed official GitHub release" unless component.fetch("url").match?(%r{\Ahttps://github\.com/(?:qdrant/qdrant|FalkorDB/FalkorDB)/releases/download/v[0-9.]+/[A-Za-z0-9._-]+\z})
      raise "component SHA-256 is invalid" unless component.fetch("sha256").match?(/\A[0-9a-f]{64}\z/)
    end

    def normalize_parameters(parameters)
      value = parameters.transform_keys(&:to_s)
      target = value.fetch("target_alias").to_s
      raise "target alias is invalid" unless target.match?(/\A[a-z][a-z0-9_-]{0,31}\z/)
      vmid = Integer(value.fetch("vmid"))
      raise "guest VMID is invalid" unless vmid.between?(100, 999_999)
      fqdn = value.fetch("fqdn").to_s.downcase
      raise "guest FQDN is invalid" unless fqdn.match?(/\A[a-z][a-z0-9-]{0,62}(?:\.[a-z0-9][a-z0-9-]{0,62}){2,}\z/)
      ipv4 = private_unicast(value.fetch("ipv4"), "guest")
      gateway = private_unicast(value.fetch("gateway"), "gateway")
      client = private_unicast(value.fetch("client_ipv4"), "client")
      subnet = IPAddr.new("#{ipv4}/24")
      raise "gateway is outside the guest subnet" unless subnet.include?(gateway)
      raise "client is outside the guest subnet" unless subnet.include?(client)
      raise "guest, gateway, and client addresses must be distinct" unless [ipv4, gateway, client].uniq.length == 3
      digests = REQUIRED_DIGEST_KEYS.to_h do |key|
        candidate = value.fetch(key).to_s.downcase
        raise "#{key} is invalid" unless candidate.match?(/\A[0-9a-f]{64}\z/)
        [key, candidate]
      end
      raise "database credentials must be independently generated" if digests.fetch("qdrant_api_key_sha256") == digests.fetch("falkordb_password_sha256")
      {
        "target_alias" => target,
        "vmid" => vmid,
        "fqdn" => fqdn,
        "ipv4" => ipv4.to_s,
        "gateway" => gateway.to_s,
        "client_ipv4" => client.to_s
      }.merge(digests)
    rescue KeyError, ArgumentError
      raise "deployment parameters are incomplete or invalid"
    end

    def private_unicast(input, label)
      value = IPAddr.new(input.to_s)
      raise "#{label} address must be IPv4" unless value.ipv4?
      private_address = IPAddr.new("10.0.0.0/8").include?(value) ||
        IPAddr.new("172.16.0.0/12").include?(value) ||
        IPAddr.new("192.168.0.0/16").include?(value)
      raise "#{label} address must be private unicast" unless private_address
      value
    rescue IPAddr::InvalidAddressError
      raise "#{label} address is invalid"
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
    end

    def canonicalize(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, canonicalize(value.fetch(key))] }
      when Array then value.map { |item| canonicalize(item) }
      else value
      end
    end
  end
end
