# frozen_string_literal: true
require "json"
require "open3"
require "timeout"

module SoulCore
  # One request, one helper invocation. Lifecycle owners decide when to sample;
  # construction does not launch anything or establish a background poller.
  class GpuAccountingSnapshot
    HELPER = "/usr/local/libexec/soul-gpu-accounting/snapshot"
    # Bound sudo startup too, not just the privileged helper's own alarm.
    # Foreground mode avoids creating/signaling the caller's process group.
    COMMAND = ["/usr/bin/timeout", "--foreground", "--kill-after=1s", "6s",
      "/usr/bin/sudo", "-n", "--", HELPER].freeze
    class Unavailable < StandardError; end
    FAILURE_CODES = %w[kernel_record_bound client_incomplete descriptor_bound identity_changed
      shared_client_changed gpu_identity vram_totals ownership_incomplete snapshot_stale
      output_bound lock_busy permission_denied unknown].freeze

    def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @clock = clock
      @sequence = 0
      @last_captured = nil
      @mutex = Mutex.new
    end

    def sample
      raise Unavailable, "accounting request already active" unless @mutex.try_lock
      locked = true
      output = nil
      status = nil
      Open3.popen3(*COMMAND) do |input, stdout, stderr, wait|
        input.close
        stderr.close
        begin
          Timeout.timeout(8) do
            output = stdout.read(524_289)
            raise Unavailable, "accounting helper returned no data" if output.nil? || output.empty?
            raise Unavailable, "accounting output bound" if output.bytesize > 524_288
            raise Unavailable, "accounting trailing output" unless stdout.read(1).nil?
            status = wait.value
          end
        ensure
          stdout.close unless stdout.closed?
        end
      end
      unless status.success?
        failure = JSON.parse(output) rescue nil
        code = failure.is_a?(Hash) && failure["state"] == "failed" && failure["error_code"]
        raise Unavailable, FAILURE_CODES.include?(code) ? "accounting helper failed: #{code}" : "accounting helper failed"
      end
      decode(output)
    rescue JSON::ParserError, KeyError, Timeout::Error, SystemCallError => error
      raise Unavailable, "accounting unavailable: #{error.class}"
    ensure
      @mutex.unlock if locked
    end

    private

    def decode(output)
      row = JSON.parse(output)
      raise Unavailable, "accounting shape" unless row.is_a?(Hash)
      captured = row.fetch("monotonic")
      unless row["state"] == "sample" && row["pci"] == "0000:0a:00.0" &&
          captured.is_a?(Numeric) && captured.finite? && (@clock.call - captured).between?(0, 3) &&
          (!@last_captured || captured > @last_captured)
        raise Unavailable, "stale or invalid accounting"
      end
      total, used, clients = row.values_at("total", "used", "clients")
      unless total.is_a?(Integer) && total >= 15 * 1024**3 && used.is_a?(Integer) && used.between?(0,total) &&
          clients.is_a?(Array) && clients.all? { |c| c.is_a?(Hash) && c["id"].is_a?(String) &&
            c["bytes"].is_a?(Integer) && c["bytes"] >= 0 && c["compute"].is_a?(Integer) && c["compute"] >= 0 &&
            c["holders"].is_a?(Array) && !c["holders"].empty? && c["holders"].all? { |h| h.is_a?(Hash) &&
              h["pid"].is_a?(Integer) && h["pid"] > 0 && h["uid"].is_a?(Integer) && h["uid"] >= 0 &&
              h["start_ticks"].is_a?(Integer) && h["start_ticks"] >= 0 && h["exe"].is_a?(String) } } &&
          clients.map { |c| c["id"] }.uniq.length == clients.length &&
          used <= clients.sum { |c| c["bytes"] } + 256 * 1024**2
        raise Unavailable, "incomplete accounting"
      end
      @last_captured = captured
      @sequence += 1
      row.merge("sequence" => @sequence)
    end
  end
end
