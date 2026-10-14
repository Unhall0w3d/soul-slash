# frozen_string_literal: true

require_relative "sandbox_runner"
require_relative "qwen_host_observer"

module SoulCore
  module ContinuityLab
    # Trusted host composition of existing fixed capabilities. The HTTP client
    # cannot select a process, path, model, profile, command, endpoint or tool.
    class ChatExecutor
      MODEL_SHA256 = "d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785"
      SERVER_SHA256 = "9b774d211090d3bff738fdb9b17f1ee7e3afa40774a0455f9f81399ff9d69e81"
      attr_reader :config, :profile, :last_receipts, :last_outcome, :observer

      def initialize(root: File.expand_path("../../..", __dir__), deadline: nil, max_generations: 32)
        raise ValidationError, "invalid generation ceiling" unless max_generations.is_a?(Integer) && max_generations.between?(1, 128)
        @root, @deadline, @maximum = root, deadline, max_generations
        @config = Config.qwen_v9_qualification
        @profile = QwenMessageProjection::PROFILE_DIRECT_CHAT
        @cancelled = false
        @generations = 0
        @last_receipts = []
      end

      def prepare!
        raise AdmissionDenied, "explicit finite quiet window required" unless @deadline.is_a?(Numeric) && @deadline.finite? && (@deadline - now).between?(1, 3600)
        @files = { QwenHostObserver::MODEL => MODEL_SHA256, QwenHostObserver::SERVER => SERVER_SHA256 }
        @identities = @files.to_h do |path, digest|
          raise AdmissionDenied, "qualified model/build changed" unless Digest::SHA256.file(path).hexdigest == digest
          [path, identity(path)]
        end
        runner = BoundedCommandRunner.new
        result = runner.run("systemctl", "--user", "show", "llama-server.service", "--property=MainPID", "--value", "--no-pager", timeout_seconds: 2, max_output_bytes: 64)
        unless result.success? && !result.truncated && result.stdout.to_s.strip.match?(/\A[1-9][0-9]*\z/)
          raise AdmissionDenied, "resident process unavailable"
        end
        selection = File.join(@root, "Soul/runtime/model_runtime/core_selection.json")
        stat = File.lstat(selection)
        raise AdmissionDenied, "unsafe selection file" unless stat.file? && !stat.symlink? && stat.size <= 8192
        core = ContinuityLab.parse(File.read(selection, 8193)).fetch("active_core_id")
        raise AdmissionDenied, "Core not eligible" unless %w[amd-free dev music].include?(core)
        @client = QwenTransport.new
        @observer = QwenHostObserver.new(root: @root, client: @client, expected_pid: result.stdout.to_i, expected_core: core)
        leases = ModelRuntimeLeaseStore.new(root: @root)
        @gate = AdmissionGate.new(lease_store: leases, snapshot_provider: @observer)
        @gate.with_window { @observer.call }
        true
      rescue SystemCallError, JSON::ParserError, KeyError => error
        raise AdmissionDenied, "host preparation unavailable: #{error.class}"
      end

      def cancel! = @cancelled = true
      def cancelled? = @cancelled || (@deadline && now >= @deadline)

      def run(state_directory:, event_id:, content:)
        raise AdmissionDenied, "foreground quiet window not prepared" unless @gate
        raise AdmissionDenied, "foreground window ended" if cancelled?
        @files.each_key do |path|
          raise AdmissionDenied, "qualified files changed" unless identity(path) == @identities.fetch(path)
        end
        @last_receipts = []
        retained_bytes = 0
        receipt = lambda do |record|
          retained_bytes += ContinuityLab.encode(record).bytesize
          raise QuotaExceeded, "broker receipt bound exceeded" if retained_bytes > 8 * 1024 * 1024
          @last_receipts << record
        end
        broker = QwenBrokerSession.new(client: @client, observer: @observer, on_receipt: receipt,
          before_generation: lambda {
            raise AdmissionDenied, "foreground generation budget exhausted" if cancelled? || @generations >= @maximum
            @generations += 1
          }, protocol_version: QwenBrokerSession::V4_PROMPT_VERSION,
          input_budget: TokenContext.budget(config), execution_profile: Config::STREAM_PROFILE, message_profile: profile)
        remaining = @deadline - now
        raise AdmissionDenied, "insufficient foreground time" unless remaining >= 11
        runner = SandboxRunner.new(state_directory: state_directory, timeout_seconds: [remaining, 430].min,
          execution_profile: Config::STREAM_PROFILE)
        @last_outcome = runner.run(request: { "mode" => "qwen_v9_chat_run", "create" => false,
          "event_id" => event_id, "content" => content, "corpus" => [] }, broker: broker, admission: @gate,
          cancel: -> { cancelled? })
      end

      def idle!
        raise AdmissionDenied, "window not prepared" unless @gate
        @gate.with_window { @observer.call }
      end

      private

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      def identity(path)
        stat = File.stat(path)
        [stat.dev, stat.ino, stat.size, stat.mtime.to_f, stat.ctime.to_f]
      end
    end
  end
end
