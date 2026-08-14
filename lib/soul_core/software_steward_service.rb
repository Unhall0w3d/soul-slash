# frozen_string_literal: true

require "json"
require "open3"
require "time"

module SoulCore
  # A small foreground-only runner.  It accepts argv, never a shell string, and
  # owns a process group so a timed-out command cannot leave descendants behind.
  class ReadOnlyCommandRunner
    def call(argv, timeout_seconds:, output_limit_bytes:)
      command = Array(argv).map(&:to_s)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stdout_reader, stdout_writer = IO.pipe
      stderr_reader, stderr_writer = IO.pipe
      pid = Process.spawn(*command, out: stdout_writer, err: stderr_writer, pgroup: true)
      stdout_writer.close
      stderr_writer.close
      stdout = +""
      stderr = +""
      readers = { stdout_reader => stdout, stderr_reader => stderr }
      deadline = started + timeout_seconds.to_f
      status = nil
      result_status = nil

      until readers.empty? && status
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          result_status = "timeout"
          terminate_process_group(pid)
          status = wait_for(pid)
          readers.each_key(&:close)
          readers.clear
          break
        end

        ready = IO.select(readers.keys, nil, nil, [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0.05].max)
        Array(ready && ready[0]).each do |io|
          chunk = io.read_nonblock(16 * 1024, exception: false)
          if chunk.nil?
            io.close
            readers.delete(io)
          elsif chunk != :wait_readable
            readers.fetch(io) << chunk
            if readers.fetch(io).bytesize > output_limit_bytes
              result_status = "truncated"
              terminate_process_group(pid)
              status = wait_for(pid)
              readers.each_key(&:close)
              readers.clear
              break
            end
          end
        end
        status ||= Process.waitpid(pid, Process::WNOHANG) && $?
      end

      {
        "status" => result_status || (status&.success? ? "ok" : "failed"),
        "stdout" => stdout.byteslice(0, output_limit_bytes),
        "stderr" => stderr.byteslice(0, output_limit_bytes),
        "exit_status" => status&.exitstatus,
        "elapsed_ms" => elapsed_ms(started)
      }
    rescue Errno::ENOENT => error
      { "status" => "unavailable", "stdout" => "", "stderr" => error.message, "exit_status" => nil, "elapsed_ms" => elapsed_ms(started) }
    rescue StandardError => error
      { "status" => "failed", "stdout" => "", "stderr" => "#{error.class}: #{error.message}", "exit_status" => nil, "elapsed_ms" => elapsed_ms(started) }
    ensure
      [stdout_reader, stdout_writer, stderr_reader, stderr_writer].compact.each { |io| io.close unless io.closed? }
    end

    private

    def wait_for(pid)
      Process.waitpid(pid)
      $?
    rescue Errno::ECHILD
      nil
    end

    def terminate_process_group(pid)
      Process.kill("TERM", -pid)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.25
      loop do
        return if Process.waitpid(pid, Process::WNOHANG)
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.01
      end
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    def elapsed_ms(started)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
    end
  end

  class SoftwareStewardService
    MAX_PACKAGE_IDS = 100
    MAX_AUDIT_FINDINGS = 100
    COMMAND_TIMEOUT_SECONDS = 8
    OUTPUT_LIMIT_BYTES = 512 * 1024
    PACKAGE_ID = /\A[A-Za-z0-9@._+:~-]+\z/
    FLATPAK_ID = /\A[A-Za-z0-9_.-]+\z/

    COMMANDS = {
      "installed" => %w[pacman -Qq],
      "explicit" => %w[pacman -Qeq],
      "foreign" => %w[pacman -Qmq],
      "orphans" => %w[pacman -Qdtq],
      "flatpak" => %w[flatpak list --app --columns=application],
      "arch_audit" => %w[arch-audit --json]
    }.freeze

    def initialize(runner: ReadOnlyCommandRunner.new, clock: -> { Time.now.utc })
      @runner = runner
      @clock = clock
    end

    def refresh
      package_sources = %w[installed explicit foreign orphans].to_h { |name| [name, package_source(name)] }
      flatpak = package_source("flatpak", identifier: FLATPAK_ID)
      flatpak_inventory = package_inventory("flatpak" => flatpak).fetch("flatpak")
      audit = audit_source
      complete({
        "schema_version" => "soul.software-steward.a0.v1",
        "package_inventory" => package_inventory(package_sources),
        "flatpak" => flatpak_inventory,
        "arch_audit" => audit,
        "sources" => package_sources.transform_values { |source| source_metadata(source) }.merge("flatpak" => source_metadata(flatpak), "arch_audit" => source_metadata(audit, may_contact_remote: true)),
        "limits" => { "package_ids" => MAX_PACKAGE_IDS, "audit_findings" => MAX_AUDIT_FINDINGS, "command_output_bytes" => OUTPUT_LIMIT_BYTES, "command_timeout_seconds" => COMMAND_TIMEOUT_SECONDS },
        "automatic_refresh" => false,
        "background_polling" => false,
        "mutation_authority" => "none"
      }, "Software Steward evidence collected.")
    rescue StandardError => error
      failed("Software Steward refresh failed safely: #{error.class}")
    end

    private

    def package_inventory(sources)
      sources.transform_values do |source|
        next source_metadata(source) unless source["available"]

        { "available" => true, "count" => source.fetch("items").length, "items" => source.fetch("items").first(MAX_PACKAGE_IDS), "truncated" => source.fetch("items").length > MAX_PACKAGE_IDS }
      end
    end

    def package_source(name, identifier: PACKAGE_ID)
      result = run(name)
      return unavailable(result) unless result["status"] == "ok"

      items = result["stdout"].lines.map(&:strip).reject(&:empty?)
      return malformed(result, "package identifiers were malformed") unless items.all? { |item| item.match?(identifier) }

      { "available" => true, "items" => items, "command" => command_metadata(name, result) }
    end

    def audit_source
      result = run("arch_audit")
      return unavailable(result) unless result["status"] == "ok"

      parsed = JSON.parse(result["stdout"])
      findings = parsed.is_a?(Array) ? parsed : parsed["issues"] || parsed["findings"] || parsed["vulnerabilities"]
      return malformed(result, "arch-audit JSON did not contain a findings array") unless findings.is_a?(Array) && findings.all?(Hash)

      normalized = findings.flat_map { |finding| normalize_findings(finding) }
      return malformed(result, "arch-audit finding was malformed") if normalized.empty? && !findings.empty?

      grouped = normalized.first(MAX_AUDIT_FINDINGS).group_by { |finding| finding.fetch("severity") }
      { "available" => true, "count" => normalized.length, "findings" => normalized.first(MAX_AUDIT_FINDINGS), "findings_by_severity" => grouped.transform_values(&:length), "truncated" => normalized.length > MAX_AUDIT_FINDINGS, "command" => command_metadata("arch_audit", result), "may_contact_arch_security_tracker" => true }
    rescue JSON::ParserError
      malformed(result, "arch-audit JSON was malformed")
    end

    def normalize_findings(finding)
      packages = Array(finding["packages"] || finding["package"] || finding["affected_package"])
      packages = [finding["name"]] if packages.empty? && !finding.key?("issues")
      packages = packages.map(&:to_s).select { |package| package.match?(PACKAGE_ID) }.uniq.first(20)
      return [] if packages.empty?

      advisories = Array(finding["advisories"] || finding["advisory"]).filter_map do |advisory|
        next unless advisory.is_a?(Hash)

        identifier = advisory["id"] || advisory["advisory"] || advisory["name"]
        fixed = advisory["fixed"] || advisory["fixed_version"] || advisory["fixed_versions"]
        cves = Array(advisory["cves"] || advisory["cve"]).map(&:to_s).grep(/\ACVE-\d{4}-\d+\z/i).first(20)
        { "advisory" => identifier.to_s, "fixed_version" => fixed.to_s, "cves" => cves }.reject { |_key, value| value.nil? || value == "" || value == [] }
      end
      if advisories.empty?
        advisory_id = finding["advisory"] || finding["name"]
        cves = Array(finding["cves"] || finding["cve"] || finding["issues"]).map(&:to_s).grep(/\ACVE-\d{4}-\d+\z/i).first(20)
        advisory = { "advisory" => advisory_id.to_s, "fixed_version" => (finding["fixed"] || finding["fixed_version"]).to_s, "cves" => cves }.reject { |_key, value| value == "" || value == [] }
        advisories = [advisory] unless advisory.empty?
      end
      packages.map { |package| { "severity" => normalize_severity(finding["severity"]), "affected_package" => package, "advisories" => advisories.first(20) } }
    end

    def normalize_severity(value)
      severity = value.to_s.downcase
      %w[critical high medium low unknown].include?(severity) ? severity : "unknown"
    end

    def run(name)
      @runner.call(COMMANDS.fetch(name), timeout_seconds: COMMAND_TIMEOUT_SECONDS, output_limit_bytes: OUTPUT_LIMIT_BYTES)
    end

    def unavailable(result)
      { "available" => false, "reason" => source_reason(result), "command" => command_metadata(nil, result) }
    end

    def malformed(result, reason)
      { "available" => false, "reason" => reason, "command" => command_metadata(nil, result) }
    end

    def source_metadata(source, may_contact_remote: false)
      { "available" => source["available"], "reason" => source["reason"], "may_contact_arch_security_tracker" => may_contact_remote }.compact
    end

    def command_metadata(name, result)
      { "source_id" => name, "status" => result["status"], "exit_status" => result["exit_status"], "elapsed_ms" => result["elapsed_ms"] }.compact
    end

    def source_reason(result)
      case result["status"]
      when "unavailable" then "required local command is unavailable"
      when "timeout" then "source timed out and is unavailable"
      when "truncated" then "source output exceeded its bound and is unavailable"
      else "source command failed and is unavailable"
      end
    end

    def complete(data, message)
      { "ok" => true, "lifecycle_state" => "complete", "message" => message, "data" => data, "mutation" => "none", "retrieved_at" => @clock.call.iso8601(6) }
    end

    def failed(message)
      { "ok" => false, "lifecycle_state" => "failed", "message" => message, "data" => {}, "mutation" => "none", "retrieved_at" => @clock.call.iso8601(6) }
    end
  end
end
