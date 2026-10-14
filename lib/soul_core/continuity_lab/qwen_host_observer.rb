# frozen_string_literal: true

require "digest"
require_relative "admission_gate"
require_relative "qwen_transport"
require_relative "../bounded_command_runner"

module SoulCore
  module ContinuityLab
    class QwenHostObserver
      MODEL = "/home/bhones/ai_models/Qwen3-8B-Q4_K_M.gguf"
      SERVER = "/home/bhones/.local/opt/llama.cpp-b9851-cuda-sm61/bin/llama-server"
      TEMPLATE_SHA256 = "57f1fd00f0013a2be96aa79b857391f27e23df5b5f847072b524c897e24d0361"
      attr_reader :last_evidence

      def initialize(root:, client:, expected_pid:, expected_core: "amd-free", runner: BoundedCommandRunner.new)
        @root, @client, @pid, @core, @runner = root, client, expected_pid, expected_core, runner
      end

      def call
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 8
        directory = File.join(@root, "Soul/runtime/model_runtime")
        core = read_state(File.join(directory, "core_selection.json"))
        profile = read_state(File.join(directory, "selected_profile.json"))
        unless core["schema_version"] == "soul.core_selection.v2" && core["active_core_id"] == @core &&
               core.dig("profiles", @core) == "nvidia-fallback" && profile == { "profile_id" => "nvidia-fallback" }
          raise AdmissionDenied, "Core or selected profile changed"
        end
        pending = File.join(directory, "whisper-pending.json")
        raise AdmissionDenied, "pending Whisper recovery" if File.exist?(pending) || File.symlink?(pending)
        unit = @runner.run("systemctl", "--user", "show", "llama-server.service", "--property=ActiveState,SubState,MainPID", "--no-pager", timeout_seconds: 2, max_output_bytes: 2048)
        properties = unit.stdout.to_s.lines.to_h { |line| line.strip.split("=", 2) }
        unless unit.success? && !unit.truncated && properties["ActiveState"] == "active" &&
               properties["SubState"] == "running" && properties["MainPID"] == @pid.to_s
          raise AdmissionDenied, "resident service changed or unverified"
        end
        argv = File.binread("/proc/#{@pid}/cmdline", 8192).split("\0")
        unless argv.first == SERVER && argv.each_cons(2).include?(["--model", MODEL]) &&
               argv.each_cons(2).include?(["--host", "127.0.0.1"]) && argv.each_cons(2).include?(["--port", "8082"])
          raise AdmissionDenied, "resident process identity mismatch"
        end
        props = @client.request("GET", "/props", deadline: deadline)
        self.class.validate_props!(props)
        slots = @client.request("GET", "/slots", deadline: deadline)
        self.class.validate_slots!(slots)
        @last_evidence = { "pid" => @pid, "core" => @core, "build" => props["build_info"],
                           "template_sha256" => TEMPLATE_SHA256, "context" => 4096, "slots" => 1 }
        { "captured_at" => Process.clock_gettime(Process::CLOCK_MONOTONIC), "core" => @core,
          "profile_id" => "nvidia-fallback", "model_file" => File.basename(MODEL),
          "service_active" => true, "active_slots" => 0, "pending_transition" => false, "dedicated_window" => true }
      rescue SystemCallError, JSON::ParserError, TypeError, ArgumentError => error
        raise AdmissionDenied, "host observation unavailable: #{error.class}"
      end

      def self.validate_props!(props)
        unless props.is_a?(Hash) && props["model_path"] == MODEL && props["model_alias"] == "soul-local-chat" &&
               props["build_info"] == "b9851-0eca4d490" && props["total_slots"] == 1 &&
               props.dig("default_generation_settings", "n_ctx") == 4096 && props["is_sleeping"] == false &&
               props["chat_template"].is_a?(String) && Digest::SHA256.hexdigest(props["chat_template"]) == TEMPLATE_SHA256
          raise AdmissionDenied, "model, build, template or context identity changed"
        end
      end

      def self.validate_slots!(slots)
        unless slots.is_a?(Array) && slots.length == 1 && slots[0].is_a?(Hash) &&
               slots[0]["is_processing"] == false && slots[0]["n_ctx"] == 4096
          raise AdmissionDenied, "backend slot busy or unknown"
        end
      end

      private

      def read_state(path)
        stat = File.lstat(path)
        raise AdmissionDenied, "unsafe runtime selection file" unless stat.file? && !stat.symlink? && stat.size <= 8192
        ContinuityLab.parse(File.read(path, 8193))
      end
    end
  end
end
