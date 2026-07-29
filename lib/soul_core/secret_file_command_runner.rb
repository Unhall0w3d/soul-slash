# frozen_string_literal: true

require "timeout"

module SoulCore
  class SecretFileCommandRunner
    DEFAULT_TIMEOUT_SECONDS = 120
    DEFAULT_MAX_OUTPUT_BYTES = 256 * 1024

    Result = Struct.new(:stdout, :exit_status, :status, :truncated, keyword_init: true) do
      def success?
        status == "ok"
      end
    end

    attr_reader :commands

    def initialize
      @commands = []
    end

    def run(*command, password:, new_password: nil, timeout_seconds: DEFAULT_TIMEOUT_SECONDS, max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES)
      argv = command.flatten.map(&:to_s)
      raise ArgumentError, "command is required" if argv.empty?

      @commands << argv.dup.freeze
      old_secret = bounded_secret(password, "repository password")
      new_secret = new_password.nil? ? nil : bounded_secret(new_password, "new repository password")
      old_reader, old_writer = IO.pipe
      new_reader = new_writer = nil
      if new_secret
        new_reader, new_writer = IO.pipe
      end
      stdout_reader, stdout_writer = IO.pipe
      stderr_reader, stderr_writer = IO.pipe

      write_secret(old_writer, old_secret)
      write_secret(new_writer, new_secret) if new_writer
      spawn_options = {
        out: stdout_writer, err: stderr_writer, 3 => old_reader,
        pgroup: true, close_others: true
      }
      spawn_options[4] = new_reader if new_reader
      pid = Process.spawn(*argv, **spawn_options)
      [old_reader, new_reader, stdout_writer, stderr_writer].compact.each(&:close)
      stdout_thread = bounded_reader(stdout_reader, max_output_bytes)
      stderr_thread = bounded_reader(stderr_reader, max_output_bytes)
      process_status = nil
      status = "failed"
      begin
        Timeout.timeout(Float(timeout_seconds)) { _, process_status = Process.wait2(pid) }
        status = process_status.success? ? "ok" : "failed"
      rescue Timeout::Error
        status = "timeout"
        process_status = terminate_group(pid)
      ensure
        stdout, stdout_truncated = reader_value(stdout_thread)
        _stderr, stderr_truncated = reader_value(stderr_thread)
      end
      Result.new(
        stdout: safe_text(stdout, max_output_bytes),
        exit_status: process_status&.exitstatus,
        status: status,
        truncated: stdout_truncated || stderr_truncated
      )
    rescue Errno::ENOENT
      Result.new(stdout: "", exit_status: nil, status: "unavailable", truncated: false)
    rescue StandardError
      Result.new(stdout: "", exit_status: nil, status: "failed", truncated: false)
    ensure
      [old_reader, old_writer, new_reader, new_writer, stdout_reader, stdout_writer, stderr_reader, stderr_writer].compact.each do |io|
        io.close unless io.closed?
      rescue IOError
        nil
      end
      wipe(old_secret)
      wipe(new_secret)
    end

    private

    def bounded_secret(value, label)
      secret = value.to_s.dup
      raise ArgumentError, "#{label} is required" if secret.empty?
      raise ArgumentError, "#{label} exceeds 512 bytes" if secret.bytesize > 512
      raise ArgumentError, "#{label} contains a line break" if secret.match?(/[\r\n]/)

      secret
    end

    def write_secret(writer, secret)
      writer.write(secret)
      writer.write("\n")
      writer.close
    end

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
      ensure
        io.close unless io.closed?
      end
    end

    def reader_value(reader)
      Timeout.timeout(2) { reader.value }
    rescue Timeout::Error
      reader.kill
      ["", true]
    end

    def terminate_group(pid)
      Process.kill("TERM", -pid)
      Timeout.timeout(1) { _, status = Process.wait2(pid); status }
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    rescue Timeout::Error
      Process.kill("KILL", -pid) rescue nil
      begin
        _, status = Process.wait2(pid)
        status
      rescue Errno::ECHILD
        nil
      end
    end

    def safe_text(value, maximum)
      value.to_s.byteslice(0, maximum).to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
    end

    def wipe(value)
      value&.replace("\0" * value.bytesize)
    end
  end
end
