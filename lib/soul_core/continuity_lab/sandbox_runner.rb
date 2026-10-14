# frozen_string_literal: true

require "rbconfig"
require_relative "broker_session"
require_relative "admission_gate"
require_relative "qwen_broker_session"

module SoulCore
  module ContinuityLab
    class SandboxFailure < Error; end

    # Fixed foreground driver, not a general subprocess executor.
    class SandboxRunner
      MAX_FRAME = 524_288
      MAX_CHANNEL = 8 * 1024 * 1024
      attr_reader :pid

      def initialize(state_directory:, timeout_seconds: 10, execution_profile: nil)
        raise ValidationError, "invalid worker execution profile" unless [nil, Config::STREAM_PROFILE].include?(execution_profile)
        @execution_profile = execution_profile
        maximum = execution_profile == Config::STREAM_PROFILE ? 430 : 60
        unless timeout_seconds.is_a?(Numeric) && timeout_seconds.finite? && timeout_seconds.between?(0.1, maximum)
          raise ValidationError, "invalid worker deadline"
        end
        unless state_directory.is_a?(String) && File.realpath(state_directory) == state_directory &&
               File.stat(state_directory).directory? && File.stat(state_directory).uid == Process.uid &&
               (File.stat(state_directory).mode & 0o777) == 0o700 &&
               (Dir.children(state_directory) - %w[store probe.txt]).empty?
          raise ValidationError, "worker requires a dedicated private fixture directory"
        end
        @state_directory, @timeout = state_directory, timeout_seconds.to_f
        stat = File.stat(state_directory)
        @directory_identity = [stat.dev, stat.ino]
      rescue SystemCallError
        raise ValidationError, "fixture directory is unavailable"
      end

      def command(state_fd)
        ruby_root = File.expand_path("../..", RbConfig.ruby)
        root = File.expand_path("../../..", __dir__)
        ["/usr/bin/bwrap", "--unshare-all", "--unshare-user", "--die-with-parent", "--new-session", "--disable-userns", "--cap-drop", "ALL", "--clearenv",
         "--ro-bind", "/usr", "/usr", "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib", "/lib64",
         "--ro-bind", ruby_root, ruby_root, "--ro-bind", __dir__, "/app/continuity_lab",
         "--ro-bind", File.join(root, "scripts/continuity-lab-worker.rb"), "/app/worker.rb",
         "--bind-fd", state_fd.to_s, "/state", "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp",
         "--dir", "/run", "--setenv", "HOME", "/tmp", "--setenv", "LANG", "C.UTF-8",
         "--chdir", "/state", "--", RbConfig.ruby, "/app/worker.rb"]
      end

      def run(request:, broker:, admission: nil, cancel: -> { false })
        raise Busy, "fixture worker already active" if @running
        unless request.is_a?(Hash) && (admission.instance_of?(AdmissionGate) ||
          (admission.nil? && %w[probe timeout_probe disconnect_probe].include?(request["mode"])))
          raise AdmissionDenied, "task execution requires the foreground admission gate"
        end
        @running = true
        begin
          if admission
            admission.with_window { run_owned(request: request, broker: broker, cancel: cancel) }
          else
            run_owned(request: request, broker: broker, cancel: cancel)
          end
        ensure
          @running = false
        end
      end

      def run_owned(request:, broker:, cancel:)
        @pid, @reaped = nil, false
        raise ValidationError, "invalid worker request" unless request.is_a?(Hash)
        live = %w[qwen_run qwen_resume qwen_v3_run qwen_v3_resume qwen_v3_rollover_run qwen_v3_rollover_resume qwen_v4_run qwen_v4_resume qwen_v4_rollover_run qwen_v4_rollover_resume qwen_v5_run qwen_v5_resume qwen_v5_rollover_run qwen_v5_rollover_resume qwen_v6_run qwen_v6_resume qwen_v6_rollover_run qwen_v6_rollover_resume qwen_v7_run qwen_v7_resume qwen_v8_run qwen_v8_resume qwen_v9_run qwen_v9_resume qwen_v9_chat_run qwen_v9_chat_resume qwen_v9_checked_run qwen_v9_checked_resume].include?(request["mode"])
        unless live ? broker.instance_of?(QwenBrokerSession) : broker.instance_of?(BrokerSession)
          raise ValidationError, "broker does not match worker profile"
        end
        if live
          expected_execution = request["mode"].start_with?("qwen_v5_", "qwen_v6_", "qwen_v7_", "qwen_v8_", "qwen_v9_") ? Config::STREAM_PROFILE : nil
          unless @execution_profile == expected_execution && broker.execution_profile == expected_execution
            raise ValidationError, "worker/broker execution profile mismatch"
          end
          receipt_mode = request["mode"].start_with?("qwen_v6_", "qwen_v7_", "qwen_v8_", "qwen_v9_")
          if receipt_mode != QwenMessageProjection.receipt_profile?(broker.message_profile)
            raise ValidationError, "worker/broker context policy mismatch"
          end
          if request["mode"].start_with?("qwen_v8_", "qwen_v9_") != QwenMessageProjection.recent_profile?(broker.message_profile)
            raise ValidationError, "worker/broker recent dialogue policy mismatch"
          end
          if request["mode"].start_with?("qwen_v9_") != QwenMessageProjection.direct_profile?(broker.message_profile)
            raise ValidationError, "worker/broker direct evidence policy mismatch"
          end
          if request["mode"].start_with?("qwen_v9_")
            expected_message = if request["mode"].start_with?("qwen_v9_checked_")
              QwenMessageProjection::PROFILE_DIRECT_CHECKED
            elsif request["mode"].start_with?("qwen_v9_chat_")
              QwenMessageProjection::PROFILE_DIRECT_CHAT
            else
              QwenMessageProjection::PROFILE_DIRECT
            end
            raise ValidationError, "worker/broker direct projection mismatch" unless broker.message_profile == expected_message
          end
          version = if request["mode"].start_with?("qwen_v4_", "qwen_v5_", "qwen_v6_", "qwen_v7_", "qwen_v8_", "qwen_v9_")
            expected_budget = request["mode"].include?("_rollover_") ? 2048 : 3072
            raise ValidationError, "broker budget does not match worker profile" unless broker.input_budget == expected_budget
            QwenBrokerSession::V4_PROMPT_VERSION
          elsif request["mode"].start_with?("qwen_v3_")
            QwenBrokerSession::V3_PROMPT_VERSION
          else
            QwenBrokerSession::PROMPT_VERSION
          end
          raise ValidationError, "broker protocol does not match worker profile" unless broker.protocol_version == version
        elsif @execution_profile
          raise ValidationError, "extended deadline requires streaming worker mode"
        end
        pending = ContinuityLab.encode(request) + "\n"
        raise ValidationError, "worker request too large" if pending.bytesize > MAX_FRAME
        directory = File.open(@state_directory, File::RDONLY | File::NOFOLLOW | File::NONBLOCK)
        stat = directory.stat
        raise ValidationError, "fixture directory changed" unless stat.directory? && stat.uid == Process.uid && (stat.mode & 0o777) == 0o700 && [stat.dev, stat.ino] == @directory_identity
        child_in, input = IO.pipe
        output, child_out = IO.pipe
        errors, child_err = IO.pipe
        @pid = Process.spawn({}, *command(3), in: child_in, out: child_out, err: child_err, 3 => directory,
                             close_others: true, unsetenv_others: true, pgroup: true,
                             rlimit_as: 768 * 1024 * 1024, rlimit_cpu: 30,
                             rlimit_fsize: 64 * 1024 * 1024, rlimit_nofile: 64)
        [child_in, child_out, child_err, directory].each(&:close)
        deadline = monotonic + @timeout
        buffer, stderr, total, completed, exit_status = +"", +"", 0, nil, nil
        streams = [output, errors]
        loop do
          raise SandboxFailure, "worker canceled" if cancel.call
          raise SandboxFailure, "worker deadline exceeded" if monotonic >= deadline
          ready = IO.select(streams, pending.empty? ? [] : [input], nil, [deadline - monotonic, 0.05].min.clamp(0.001, 0.05))
          if ready
            ready[1].each do |io|
              written = io.write_nonblock(pending, exception: false)
              pending = pending.byteslice(written..) if written.is_a?(Integer)
            end
            ready[0].each do |io|
              data = io.read_nonblock(4096, exception: false)
              if data.nil?
                streams.delete(io)
                io.close
                next
              end
              next if data == :wait_readable
              total += data.bytesize
              raise SandboxFailure, "worker output budget exceeded" if total > MAX_CHANNEL
              if io == errors
                stderr << data
                raise SandboxFailure, "worker stderr budget exceeded" if stderr.bytesize > 4096
                next
              end
              buffer << data
              raise SandboxFailure, "worker frame too large" if buffer.bytesize > MAX_FRAME
              while (newline = buffer.index("\n"))
                frame = ContinuityLab.parse(buffer.slice!(0..newline))
                raise SandboxFailure, "worker protocol after completion" if completed
                unless frame.is_a?(Hash)
                  raise SandboxFailure, "invalid worker frame"
                end
                case frame["type"]
                when "request"
                  raise SandboxFailure, "invalid worker request frame" unless frame.keys.sort == %w[request type] && pending.empty?
                  remaining = deadline - monotonic
                  raise SandboxFailure, "worker deadline exceeded" unless remaining.positive?
                  # Includes host observation and receipt callbacks, not only HTTP.
                  response = Timeout.timeout(remaining) do
                    # New profile reserves ten seconds for final framing/cleanup.
                    dispatch_deadline = @execution_profile ? deadline - 10 : deadline
                    live ? broker.dispatch(frame["request"], deadline: dispatch_deadline) : broker.dispatch(frame["request"])
                  end
                  pending = ContinuityLab.encode(response) + "\n"
                  raise SandboxFailure, "broker response too large" if pending.bytesize > MAX_FRAME
                when "complete"
                  raise SandboxFailure, "invalid worker completion" unless frame.keys.sort == %w[result type] && frame["result"].is_a?(Hash) && pending.empty?
                  completed = frame["result"]
                else
                  raise SandboxFailure, "worker protocol denied"
                end
              end
            end
          end
          unless exit_status
            exited = Process.waitpid2(@pid, Process::WNOHANG)
            exit_status = exited.last if exited
            @reaped = true if exited
          end
          break if exit_status && streams.empty?
        end
        unless exit_status.success? && completed && buffer.empty? && stderr.empty? && pending.empty?
          raise SandboxFailure, "worker failed or disconnected (exit=#{exit_status.exitstatus}; diagnostic=#{stderr.byteslice(0, 512).inspect})"
        end
        { "state" => "complete", "result" => completed, "worker_pid" => @pid, "exit_status" => exit_status.exitstatus }
      rescue JSON::ParserError, SystemCallError, IOError, Timeout::Error => error
        raise SandboxFailure, "worker channel unavailable: #{error.class}"
      ensure
        reap! if @pid && !@reaped
        [directory, child_in, child_out, child_err, input, output, errors].each { |io| io.close if io && !io.closed? }
      end

      private

      private :run_owned

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def reap!
        # Bubblewrap's parent-death contract kills its new-session child too.
        # Do not release the caller's admission lock until waitpid completes.
        Process.kill("KILL", -@pid)
        Process.waitpid(@pid)
        @reaped = true
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end
    end
  end
end
