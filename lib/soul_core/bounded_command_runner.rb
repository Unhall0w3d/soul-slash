# frozen_string_literal: true

require "open3"
require "timeout"

module SoulCore
  class BoundedCommandRunner
    DEFAULT_TIMEOUT_SECONDS = 8
    DEFAULT_MAX_OUTPUT_BYTES = 256 * 1024

    Result = Struct.new(:stdout, :stderr, :exit_status, :status, :truncated, keyword_init: true) do
      def success?
        status == "ok"
      end
    end

    def run(*command, timeout_seconds: DEFAULT_TIMEOUT_SECONDS, max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES, chdir: nil)
      argv = command.flatten.map(&:to_s)
      raise ArgumentError, "command is required" if argv.empty?

      options = { pgroup: true }
      options[:chdir] = chdir if chdir
      stdout = stderr = ""
      stdout_truncated = stderr_truncated = false
      process_status = nil
      run_status = "failed"

      Open3.popen3(*argv, **options) do |stdin, out, err, wait_thread|
        stdin.close
        stdout_reader = bounded_reader(out, max_output_bytes)
        stderr_reader = bounded_reader(err, max_output_bytes)
        begin
          Timeout.timeout(Float(timeout_seconds)) { process_status = wait_thread.value }
          run_status = process_status.success? ? "ok" : "failed"
        rescue Timeout::Error
          run_status = "timeout"
          terminate_group(wait_thread)
          process_status = wait_thread.value
        ensure
          stdout, stdout_truncated = reader_value(stdout_reader)
          stderr, stderr_truncated = reader_value(stderr_reader)
        end
      end

      Result.new(
        stdout: safe_text(stdout, max_output_bytes),
        stderr: safe_text(stderr, max_output_bytes),
        exit_status: process_status&.exitstatus,
        status: run_status,
        truncated: stdout_truncated || stderr_truncated
      )
    rescue Errno::ENOENT => error
      Result.new(stdout: "", stderr: error.message, exit_status: nil, status: "unavailable", truncated: false)
    rescue StandardError => error
      Result.new(stdout: "", stderr: "#{error.class}: #{error.message}", exit_status: nil, status: "failed", truncated: false)
    end

    def which(name)
      candidate = name.to_s
      return nil unless candidate.match?(/\A[A-Za-z0-9_.+-]+\z/)

      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).filter_map do |directory|
        path = File.expand_path(candidate, directory)
        path if File.file?(path) && File.executable?(path)
      end.first
    end

    private

    def bounded_reader(io, maximum)
      Thread.new do
        content = +""
        truncated = false
        loop do
          chunk = io.readpartial(4096)
          remaining = maximum - content.bytesize
          content << chunk.byteslice(0, remaining) if remaining.positive?
          truncated = true if chunk.bytesize > remaining
        end
      rescue EOFError, IOError
        [content, truncated]
      end
    end

    def reader_value(reader)
      Timeout.timeout(2) { reader.value }
    rescue Timeout::Error
      reader.kill
      ["", true]
    end

    def terminate_group(wait_thread)
      Process.kill("TERM", -wait_thread.pid)
      Timeout.timeout(1) { wait_thread.join }
    rescue Errno::ESRCH
      nil
    rescue Timeout::Error
      Process.kill("KILL", -wait_thread.pid) rescue nil
      wait_thread.join
    end

    def safe_text(value, maximum)
      value.to_s.byteslice(0, maximum).to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
    end
  end
end
