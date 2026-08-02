# frozen_string_literal: true

require "timeout"

module SoulCore
  class MaintenanceAurReviewRunner
    MAX_RUNTIME_SECONDS = 4 * 60 * 60
    FIXED_YAY_VECTOR = [
      "/usr/bin/yay", "--aur", "-Sua", "--sudoflags=-n",
      "--cleanmenu", "--diffmenu", "--editmenu",
      "--noanswerclean", "--noanswerdiff", "--noansweredit", "--noanswerupgrade",
      "--noremovemake", "--pgpfetch=false", "--provides=false",
      "--useask=false", "--sudoloop=false"
    ].freeze

    def initialize(command_executor: nil, output: $stdout)
      @command_executor = command_executor || method(:spawn_interactive)
      @output = output
    end

    def run
      @output.puts("Soul / AUR Human Review")
      @output.puts("Review the package set, PKGBUILD/install-script diffs, sources, and checksums before accepting anything.")
      @output.puts("This terminal is deliberately interactive. Closing it or declining a prompt stops the stage.")
      authenticated = execute(["/usr/bin/sudo", "-v"], 120)
      return result("failed", authenticated, "administrator authentication did not complete") unless authenticated.zero?

      status = execute(FIXED_YAY_VECTOR, MAX_RUNTIME_SECONDS)
      return result(status == 130 ? "canceled" : "failed", status, "AUR review or installation did not complete") unless status.zero?

      result("complete", 0, "AUR review terminal completed")
    rescue Interrupt
      result("canceled", 130, "AUR review terminal canceled")
    ensure
      execute(["/usr/bin/sudo", "-k"], 30) rescue nil
    end

    private

    def execute(argv, timeout_seconds)
      Integer(@command_executor.call(argv, timeout_seconds))
    end

    def spawn_interactive(argv, timeout_seconds)
      pid = Process.spawn(*argv, in: $stdin, out: $stdout, err: $stderr)
      status = nil
      Timeout.timeout(timeout_seconds) { _pid, status = Process.wait2(pid) }
      status.exitstatus || 1
    rescue Timeout::Error
      Process.kill("TERM", pid) rescue nil
      Process.wait(pid) rescue nil
      124
    rescue Errno::ENOENT
      127
    end

    def result(state, exit_status, reason)
      {
        "lifecycle_state" => state,
        "exit_status" => exit_status,
        "reason" => reason,
        "password_prompts" => 1,
        "sudo_ticket_invalidated" => true
      }
    end
  end
end
