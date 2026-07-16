# frozen_string_literal: true
require_relative "bounded_command_runner"

module SoulCore
  class PackageManagerAssessor
    SUPPORTED = %w[pacman yay paru flatpak snap nix].freeze
    READ_ONLY_UPDATE_CHECKS = {
      "pacman" => "checkupdates", "yay" => "yay -Qua", "paru" => "paru -Qua",
      "flatpak" => "flatpak remote-ls --updates", "snap" => "snap refresh --list"
    }.freeze
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
      supported = !path.nil? && READ_ONLY_UPDATE_CHECKS.key?(name)
      supported &&= !which("checkupdates").nil? if name == "pacman"
      {"detected"=>!path.nil?,"path"=>path,"safe_update_check_supported"=>supported,"orphan_check_supported"=>%w[pacman flatpak].include?(name)}
    end
    def pacman(d)
      d["updates"] = check(["checkupdates", "--nocolor"], no_results_exit_statuses: [2], empty_status: "no_updates")
      d["orphans"] = check(["pacman", "-Qdtq"], no_results_exit_statuses: [1])
      d["foreign_packages"] = check(["pacman", "-Qm"], no_results_exit_statuses: [1])
    end
    def aur(d,h); d["updates"] = check([h,"-Qua"], no_results_exit_statuses: [1]); end
    def flatpak(d)
      d["updates"] = check(["flatpak","remote-ls","--updates"])
      d["unused"] = check(["flatpak","uninstall","--unused","--dry-run"])
    end
    def snap(d); d["updates"] = check(["snap","refresh","--list"]); end
    def nix(d)
      d["profiles"] = check(["nix","profile","list"])
      d["nixos_detected"] = File.exist?("/etc/NIXOS")
      d["nix_store_detected"] = Dir.exist?("/nix/store")
      d["home_manager_detected"] = !which("home-manager").nil?
      d["nixos_rebuild_detected"] = !which("nixos-rebuild").nil?
    end
    def check(argv, no_results_exit_statuses: [], empty_status: "no_results")
      result = @runner.run(*argv, timeout_seconds: 12, max_output_bytes: 256 * 1024)
      items = result.stdout.to_s.lines.map(&:strip).reject(&:empty?).first(2_000)
      status = if result.success?
        items.empty? ? empty_status : "complete"
      elsif no_results_exit_statuses.include?(result.exit_status)
        items = []
        empty_status
      elsif result.status == "unavailable"
        "unavailable"
      else
        "failed"
      end
      {
        "command"=>argv.join(" "), "status"=>status, "exit_status"=>result.exit_status,
        "fresh"=>argv.first == "checkupdates" && ["complete", empty_status].include?(status),
        "count"=>items.length, "items"=>items, "truncated"=>result.truncated == true,
        "error"=>%w[failed unavailable].include?(status) ? result.stderr.to_s.strip.byteslice(0, 500) : nil
      }
    rescue StandardError
      {"command"=>argv.join(" "),"status"=>"failed","exit_status"=>nil,"fresh"=>false,"count"=>0,"items"=>[],"truncated"=>false,"error"=>"assessment command failed safely"}
    end
    def which(name)
      @runner.which(name)
    rescue StandardError
      nil
    end
  end
end
