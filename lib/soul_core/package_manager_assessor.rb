# frozen_string_literal: true
require_relative "bounded_command_runner"

module SoulCore
  class PackageManagerAssessor
    SUPPORTED = %w[pacman yay paru flatpak snap nix].freeze
    def initialize(runner: BoundedCommandRunner.new)
      @runner = runner
    end

    def assess(include_updates: false)
      managers = SUPPORTED.to_h { |n| [n, detect(n)] }
      if include_updates
        pacman(managers["pacman"]) if managers.dig("pacman","detected")
        aur(managers["paru"],"paru") if managers.dig("paru","detected")
        aur(managers["yay"],"yay") if managers.dig("yay","detected")
        flatpak(managers["flatpak"]) if managers.dig("flatpak","detected")
        snap(managers["snap"]) if managers.dig("snap","detected")
        nix(managers["nix"]) if managers.dig("nix","detected")
      end
      {"status"=>"ok","read_only"=>true,"updates_checked"=>include_updates,"managers"=>managers,"preferred_aur_helper"=> managers.dig("paru","detected") ? "paru" : (managers.dig("yay","detected") ? "yay" : nil)}
    end
    private
    def detect(name)
      path = which(name)
      {"detected"=>!path.nil?,"path"=>path,"safe_update_check_supported"=>true,"orphan_check_supported"=>%w[pacman flatpak].include?(name)}
    end
    def pacman(d)
      d["updates"] = pack("pacman -Qu", lines("pacman","-Qu"))
      d["orphans"] = pack("pacman -Qdtq", lines("pacman","-Qdtq"))
      d["foreign_packages"] = pack("pacman -Qm", lines("pacman","-Qm"))
    end
    def aur(d,h); d["updates"] = pack("#{h} -Qua", lines(h,"-Qua")); end
    def flatpak(d)
      d["updates"] = pack("flatpak remote-ls --updates", lines("flatpak","remote-ls","--updates"))
      d["unused"] = pack("flatpak uninstall --unused --dry-run", lines("flatpak","uninstall","--unused","--dry-run"))
    end
    def snap(d); d["updates"] = pack("snap refresh --list", lines("snap","refresh","--list")); end
    def nix(d)
      d["profiles"] = pack("nix profile list", lines("nix","profile","list"))
      d["nixos_detected"] = File.exist?("/etc/NIXOS")
      d["nix_store_detected"] = Dir.exist?("/nix/store")
      d["home_manager_detected"] = !which("home-manager").nil?
      d["nixos_rebuild_detected"] = !which("nixos-rebuild").nil?
    end
    def pack(cmd, items); {"command"=>cmd,"count"=>items.length,"items"=>items}; end
    def lines(*cmd)
      result = @runner.run(*cmd, timeout_seconds: 12, max_output_bytes: 256 * 1024)
      result.success? ? result.stdout.lines.map(&:strip).reject(&:empty?).first(2_000) : []
    rescue StandardError
      []
    end
    def which(name)
      @runner.which(name)
    rescue StandardError
      nil
    end
  end
end
