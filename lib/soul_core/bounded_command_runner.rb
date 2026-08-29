# frozen_string_literal: true

require "json"
require "open3"
require "timeout"

module SoulCore
  class BoundedCommandRunner
    DEFAULT_TIMEOUT_SECONDS = 8
    DEFAULT_MAX_OUTPUT_BYTES = 256 * 1024
    CAPTURE_MODES = %i[prefix complete_line_tail json_lines].freeze

    Result = Struct.new(:stdout, :stderr, :exit_status, :status, :truncated, :records, keyword_init: true) do
      def success?
        status == "ok"
      end
    end

    def run(*command, timeout_seconds: DEFAULT_TIMEOUT_SECONDS, max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES, chdir: nil, env: nil, capture_mode: :prefix, max_records: 100_000, max_line_bytes: 1024 * 1024, &record_transform)
      argv = command.flatten.map(&:to_s)
      raise ArgumentError, "command is required" if argv.empty?
      raise ArgumentError, "capture mode must be one of: #{CAPTURE_MODES.join(', ')}" unless CAPTURE_MODES.include?(capture_mode)
      if capture_mode == :json_lines
        raise ArgumentError, "JSON-line capture requires a record transform" unless record_transform
        raise ArgumentError, "JSON-line record limit is invalid" unless Integer(max_records).between?(1, 1_000_000)
        raise ArgumentError, "JSON-line byte limit is invalid" unless Integer(max_line_bytes).between?(1, 16 * 1024 * 1024)
      end
      unless env.nil? || (env.is_a?(Hash) && env.keys.all? { |key| key.is_a?(String) } && env.values.all? { |value| value.nil? || value.is_a?(String) })
        raise ArgumentError, "command environment must contain only string keys and string or nil values"
      end

      options = { pgroup: true }
      options[:chdir] = chdir if chdir
      spawn_argv = env ? [env, *argv] : argv
      stdout = stderr = ""
      stdout_truncated = stderr_truncated = false
      records = []
      parse_error = nil
      process_status = nil
      run_status = "failed"

      Open3.popen3(*spawn_argv, **options) do |stdin, out, err, wait_thread|
        stdin.close
        stdout_reader = bounded_reader(out, max_output_bytes, capture_mode, max_records, max_line_bytes, record_transform)
        stderr_reader = bounded_reader(err, max_output_bytes, :prefix, max_records, max_line_bytes, nil)
        begin
          Timeout.timeout(Float(timeout_seconds)) { process_status = wait_thread.value }
          run_status = process_status.success? ? "ok" : "failed"
        rescue Timeout::Error
          run_status = "timeout"
          terminate_group(wait_thread)
          process_status = wait_thread.value
        ensure
          stdout, stdout_truncated, records, parse_error = reader_value(stdout_reader)
          stderr, stderr_truncated, = reader_value(stderr_reader)
        end
      end
      if parse_error
        run_status = "failed"
        stderr = parse_error
      end

      Result.new(
        stdout: safe_text(stdout, max_output_bytes),
        stderr: safe_text(stderr, max_output_bytes),
        exit_status: process_status&.exitstatus,
        status: run_status,
        truncated: stdout_truncated || stderr_truncated,
        records: records
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

    def bounded_reader(io, maximum, capture_mode, max_records, max_line_bytes, record_transform)
      Thread.new do
        if capture_mode == :json_lines
          json_lines_reader(io, maximum, max_records, max_line_bytes, record_transform)
        elsif capture_mode == :complete_line_tail
          complete_line_tail_reader(io, maximum)
        else
          prefix_reader(io, maximum)
        end
      end
    end

    def prefix_reader(io, maximum)
      content = +""
      truncated = false
      loop do
        chunk = io.readpartial(4096)
        remaining = maximum - content.bytesize
        content << chunk.byteslice(0, remaining) if remaining.positive?
        truncated = true if chunk.bytesize > remaining
      end
    rescue EOFError, IOError
      [content, truncated, [], nil]
    end

    def complete_line_tail_reader(io, maximum)
      # Keep only complete records and discard oversized in-progress records so
      # an untrusted stream cannot make the reader's memory grow with one line.
      records = []
      records_head = 0
      records_bytes = 0
      pending = +"".b
      oversized_line = false
      truncated = false

      loop do
        io.readpartial(4096).each_byte do |byte|
          if oversized_line
            if byte == 10
              oversized_line = false
            end
            next
          end

          pending << byte
          if byte == 10
            if pending.bytesize > maximum
              truncated = true
            else
              records, records_head, records_bytes, discarded = append_tail_record(
                records, records_head, records_bytes, pending, maximum
              )
              truncated ||= discarded
            end
            pending = +"".b
          elsif pending.bytesize > maximum
            pending.clear
            oversized_line = true
            truncated = true
          end
        end
      end
    rescue EOFError, IOError
      if !oversized_line && pending.bytesize.positive?
        if pending.bytesize > maximum
          truncated = true
        else
          records, records_head, records_bytes, discarded = append_tail_record(
            records, records_head, records_bytes, pending, maximum
          )
          truncated ||= discarded
        end
      end
      [records.drop(records_head).join, truncated, [], nil]
    end

    def json_lines_reader(io, maximum, max_records, max_line_bytes, record_transform)
      records = []
      records_bytes = 0
      oversized_line = false
      truncated = false
      parse_error = nil

      begin
        io.each_line("\n", max_line_bytes + 1) do |line|
          if oversized_line
            oversized_line = false if line.end_with?("\n")
            next
          end

          if line.bytesize > max_line_bytes
            oversized_line = !line.end_with?("\n")
            parse_error ||= "JSON line exceeds the bounded record size"
            next
          end
          records_bytes, record_truncated, error = project_json_record(
            line, records, records_bytes, maximum, max_records, record_transform
          )
          truncated ||= record_truncated
          parse_error ||= error
        end
      rescue EOFError, IOError
        nil
      end
      ["", truncated, records, parse_error]
    end

    def project_json_record(line, records, records_bytes, maximum, max_records, record_transform)
      text = line.dup.force_encoding(Encoding::UTF_8)
      return [records_bytes, false, "JSON line is not valid UTF-8"] unless text.valid_encoding?
      projected = record_transform.call(JSON.parse(text))
      return [records_bytes, false, nil] if projected.nil?
      return [records_bytes, false, "JSON record projection must be a string"] unless projected.is_a?(String)
      projected_bytes = projected.bytesize
      if records.length >= max_records || projected_bytes > maximum || records_bytes + projected_bytes > maximum
        return [records_bytes, true, nil]
      end
      records << projected
      [records_bytes + projected_bytes, false, nil]
    rescue StandardError
      [records_bytes, false, "JSON line could not be projected safely"]
    end

    def append_tail_record(records, head, records_bytes, record, maximum)
      return [records, records.length, 0, true] unless maximum.positive?

      records << record
      records_bytes += record.bytesize
      discarded = false
      while records_bytes > maximum
        records_bytes -= records.fetch(head).bytesize
        records[head] = nil
        head += 1
        discarded = true
      end

      # Periodically compact discarded entries so many tiny records do not
      # grow the queue even though the retained bytes stay within the limit.
      if head >= 256 && head * 2 >= records.length
        records = records.drop(head)
        head = 0
      end
      [records, head, records_bytes, discarded]
    end

    def reader_value(reader)
      Timeout.timeout(2) { reader.value }
    rescue Timeout::Error
      reader.kill
      ["", true, [], "command output reader timed out"]
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
