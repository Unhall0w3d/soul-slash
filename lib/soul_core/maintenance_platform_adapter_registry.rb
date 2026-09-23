# frozen_string_literal: true

module SoulCore
  class MaintenancePlatformAdapterRegistry
    SCHEMA_VERSION = "soul.maintenance.platform_adapter_registry.v1"
    ADAPTERS = {
      "omarchy" => {
        "label" => "Omarchy",
        "base_family" => "arch",
        "status_adapter" => "omarchy_arch_read_only",
        "maintenance_adapter" => "omarchy_update",
        "reboot_adapter" => "omarchy_system_reboot"
      },
      "arch" => {
        "label" => "Arch-compatible Linux",
        "base_family" => "arch",
        "status_adapter" => "arch_package_managers_read_only",
        "maintenance_adapter" => "arch_pacman",
        "reboot_adapter" => "systemd_reboot"
      },
      "proxmox_apt" => {
        "label" => "Proxmox VE on Debian",
        "base_family" => "debian",
        "status_adapter" => "proxmox_apt_read_only",
        "maintenance_adapter" => "proxmox_apt",
        "reboot_adapter" => "systemd_reboot"
      },
      "debian_apt" => {
        "label" => "Debian APT",
        "base_family" => "debian",
        "status_adapter" => "debian_apt_read_only",
        "maintenance_adapter" => "debian_apt",
        "reboot_adapter" => "systemd_reboot"
      },
      "fedora_dnf5" => {
        "label" => "Fedora DNF5",
        "base_family" => "fedora",
        "status_adapter" => "dnf5_read_only",
        "maintenance_adapter" => "fedora_dnf5",
        "reboot_adapter" => "systemd_reboot"
      },
      "nixos_flake" => {
        "label" => "NixOS flake",
        "base_family" => "nixos",
        "status_adapter" => "nixos_flake_read_only",
        "maintenance_adapter" => "nixos_flake",
        "reboot_adapter" => "nixos_fixed_reboot"
      },
      "inventory_only" => {
        "label" => "Inventory only",
        "base_family" => "unknown",
        "status_adapter" => "inventory_only",
        "maintenance_adapter" => nil,
        "reboot_adapter" => nil
      }
    }.freeze

    ARCH_IDS = %w[arch archlinux cachyos endeavouros manjaro].freeze
    DEBIAN_IDS = %w[debian ubuntu raspbian].freeze

    def resolve(os_id:, os_id_like: "", platform: "", package_managers: [])
      normalized_id = normalize(os_id)
      normalized_like = os_id_like.to_s.downcase.split(/\s+/).map { |item| normalize(item) }
      normalized_platform = normalize(platform)
      managers = Array(package_managers).map { |item| normalize(item) }.uniq

      adapter_id = if normalized_id == "omarchy"
        "omarchy"
      elsif normalized_platform == "proxmox" || managers.include?("pveversion")
        "proxmox_apt"
      elsif normalized_id == "nixos"
        "nixos_flake"
      elsif normalized_id == "fedora"
        "fedora_dnf5"
      elsif ARCH_IDS.include?(normalized_id) || normalized_like.any? { |item| ARCH_IDS.include?(item) }
        "arch"
      elsif DEBIAN_IDS.include?(normalized_id) || normalized_like.any? { |item| DEBIAN_IDS.include?(item) }
        "debian_apt"
      else
        "inventory_only"
      end

      definition(adapter_id).merge(
        "schema_version" => SCHEMA_VERSION,
        "id" => adapter_id,
        "matched_os_id" => normalized_id,
        "matched_platform" => normalized_platform,
        "package_managers" => managers,
        "mutation_authorized" => false
      )
    end

    def definition(adapter_id)
      ADAPTERS.fetch(adapter_id.to_s, ADAPTERS.fetch("inventory_only")).dup
    end

    def inventory
      {
        "schema_version" => SCHEMA_VERSION,
        "adapters" => ADAPTERS.map { |id, value| value.merge("id" => id) },
        "mutation_authorized" => false
      }
    end

    private

    def normalize(value)
      value.to_s.downcase.strip.gsub(/[^a-z0-9_.-]+/, "_").byteslice(0, 80).to_s
    end
  end
end
