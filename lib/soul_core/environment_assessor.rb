# frozen_string_literal: true
require "time"
require_relative "bounded_command_runner"
require_relative "package_manager_assessor"
require_relative "runtime_assessor"
require_relative "soul_project_assessor"

module SoulCore
  class EnvironmentAssessor
    def initialize(root: Dir.pwd, runner: BoundedCommandRunner.new, clock: -> { Time.now }, pacman_log_path: "/var/log/pacman.log", uptime_path: "/proc/uptime")
      @root = root
      @runner = runner
      @clock = clock
      @pacman_log_path = pacman_log_path
      @uptime_path = uptime_path
    end

    def assess(include_updates: false)
      system = system_inventory
      package_managers = PackageManagerAssessor.new(runner: @runner, clock: @clock, pacman_log_path: @pacman_log_path, uptime_path: @uptime_path).assess(include_updates: include_updates)
      runtimes = RuntimeAssessor.new(runner: @runner).assess
      project = SoulProjectAssessor.new(root: @root, runner: @runner).assess
      {
        "status"=>"ok",
        "assessment"=>"environment",
        "generated_at"=>@clock.call.iso8601,
        "read_only"=>true,
        "update_checks_requested"=>include_updates,
        "system"=>system,
        "package_managers"=>package_managers,
        "runtimes"=>runtimes,
        "soul_project"=>project,
        "recommendations"=>recommendations(package_managers, runtimes, project, include_updates),
        "verification"=>{"no_updates_applied"=>true,"no_packages_removed"=>true,"no_install_actions_attempted"=>true,"read_only_commands_only"=>true}
      }
    end

    def render(report)
      lines = []
      lines << "Soul Environment Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Read-only: #{report['read_only']}"
      lines << ""
      lines << "System"
      lines << "- OS: #{report.dig('system','os_pretty_name') || 'unknown'}"
      lines << "- Kernel: #{report.dig('system','kernel') || 'unknown'}"
      lines << "- Architecture: #{report.dig('system','architecture') || 'unknown'}"
      lines << ""
      lines << "Package Managers"
      report.dig("package_managers","managers").each { |n,d| lines << "- #{n}: #{d['detected'] ? 'detected' : 'not detected'}" }
      lines << ""
      lines << "Runtimes"
      report.dig("runtimes","runtimes").each { |n,d| lines << "- #{n}: #{d['detected'] ? 'detected' : 'not detected'}#{d['version'] ? " (#{d['version']})" : ''}" }
      lines << ""
      lines << "Soul Project"
      lines << "- Root: #{report.dig('soul_project','root')}"
      lines << "- Git branch: #{report.dig('soul_project','git','branch') || 'unknown'}"
      lines << "- Git dirty: #{report.dig('soul_project','git','dirty')}"
      lines << "- Verifier scripts: #{report.dig('soul_project','verifiers','count')}"
      lines << ""
      lines << "Recommendations"
      if report["recommendations"].empty?
        lines << "- No recommendations generated."
      else
        report["recommendations"].each_with_index { |r,i| lines << "#{i+1}. [#{r['severity'].upcase}] #{r['title']}\n   #{r['detail']}\n   Recommended action: #{r['action']}" }
      end
      lines.join("\n")
    end

    private

    def system_inventory
      os = {}
      if File.exist?("/etc/os-release")
        File.readlines("/etc/os-release").each do |l|
          next unless l.include?("=")
          k,v = l.strip.split("=",2)
          os[k] = v.to_s.gsub(/\A"|"\z/,"")
        end
      end
      {"os_name"=>os["NAME"],"os_pretty_name"=>os["PRETTY_NAME"],"os_id"=>os["ID"],"os_id_like"=>os["ID_LIKE"],"kernel"=>cap("uname","-r"),"architecture"=>cap("uname","-m"),"shell"=>ENV["SHELL"],"session_type"=>ENV["XDG_SESSION_TYPE"],"desktop"=>ENV["XDG_CURRENT_DESKTOP"],"hostname"=>cap("hostname")}
    end

    def cap(*cmd)
      result = @runner.run(*cmd, timeout_seconds: 3, max_output_bytes: 8 * 1024)
      result.success? ? result.stdout.strip : nil
    rescue StandardError
      nil
    end

    def recommendations(pm, rt, project, include_updates)
      recs=[]
      recs << rec("warn","Soul repo has uncommitted changes","The repository is dirty. Review the working tree before more overlays.","Run `git status --short`.") if project.dig("git","dirty")
      recs << rec("info","Arch package update checks available","pacman was detected. Read-only update and orphan checks can be included.","Run `ruby bin/soul assess environment --updates`.") if pm.dig("managers","pacman","detected") && !include_updates
      recs << rec("warn","Pacman orphan candidates detected","`pacman -Qdtq` reported packages that may no longer be required.","Review manually before considering `sudo pacman -Rns <packages>`.") if pm.dig("managers","pacman","orphans","count").to_i > 0
      recs << rec("warn","System reboot recommended","A CachyOS package hook requested a reboot after the current boot began. Soul will not reboot the host.","Save active work and reboot at an operator-chosen time.") if pm.dig("reboot","recommended") == true
      recs << rec("info","Flatpak unused runtime candidates detected","Flatpak dry-run cleanup reported unused entries.","Review `flatpak uninstall --unused --dry-run`.") if pm.dig("managers","flatpak","unused","count").to_i > 0
      recs << rec("blocker","Ruby runtime missing","Soul requires Ruby to run.","Install Ruby before running Soul workflows.") unless rt.dig("runtimes","ruby","detected")
      recs
    end

    def rec(sev,title,detail,action)
      {"severity"=>sev,"title"=>title,"detail"=>detail,"action"=>action}
    end
  end
end
