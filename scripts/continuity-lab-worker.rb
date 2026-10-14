#!/usr/bin/env ruby
# frozen_string_literal: true

# Fixed foreground fixture/qualification entry point; no arbitrary commands.
require "socket"
require_relative "continuity_lab/runtime"

Lab = SoulCore::ContinuityLab
store = nil
begin
  line = $stdin.gets(524_289)
  raise Lab::ValidationError, "invalid initial frame" unless line && line.end_with?("\n") && line.bytesize <= 524_288
  request = Lab.parse(line)
  raise Lab::ValidationError, "request must be an object" unless request.is_a?(Hash)
  case request["mode"]
  when "run", "resume", "qwen_run", "qwen_resume", "qwen_v3_run", "qwen_v3_resume", "qwen_v3_rollover_run", "qwen_v3_rollover_resume", "qwen_v4_run", "qwen_v4_resume", "qwen_v4_rollover_run", "qwen_v4_rollover_resume", "qwen_v5_run", "qwen_v5_resume", "qwen_v5_rollover_run", "qwen_v5_rollover_resume", "qwen_v6_run", "qwen_v6_resume", "qwen_v6_rollover_run", "qwen_v6_rollover_resume", "qwen_v7_run", "qwen_v7_resume", "qwen_v8_run", "qwen_v8_resume", "qwen_v9_run", "qwen_v9_resume", "qwen_v9_chat_run", "qwen_v9_chat_resume", "qwen_v9_checked_run", "qwen_v9_checked_resume"
    run = %w[run qwen_run qwen_v3_run qwen_v3_rollover_run qwen_v4_run qwen_v4_rollover_run qwen_v5_run qwen_v5_rollover_run qwen_v6_run qwen_v6_rollover_run qwen_v7_run qwen_v8_run qwen_v9_run qwen_v9_chat_run qwen_v9_checked_run].include?(request["mode"])
    live = request["mode"].start_with?("qwen_")
    fields = run ? %w[content corpus create event_id mode] : %w[event_id mode]
    raise Lab::ValidationError, "invalid task fields" unless request.keys.sort == fields
    config = live ? Lab::Config.qwen_qualification : Lab::Config.new("backend" => "fixture_pipe", "context_mode" => "explicit_v1")
    config = Lab::Config.qwen_v3_qualification(rollover: request["mode"].start_with?("qwen_v3_rollover_")) if request["mode"].start_with?("qwen_v3_")
    config = Lab::Config.qwen_v4_qualification(rollover: request["mode"].start_with?("qwen_v4_rollover_")) if request["mode"].start_with?("qwen_v4_")
    config = Lab::Config.qwen_v5_qualification(rollover: request["mode"].start_with?("qwen_v5_rollover_")) if request["mode"].start_with?("qwen_v5_")
    config = Lab::Config.qwen_v6_qualification(rollover: request["mode"].start_with?("qwen_v6_rollover_")) if request["mode"].start_with?("qwen_v6_")
    config = Lab::Config.qwen_v7_qualification if request["mode"].start_with?("qwen_v7_")
    config = Lab::Config.qwen_v8_qualification if request["mode"].start_with?("qwen_v8_")
    config = Lab::Config.qwen_v9_qualification if request["mode"].start_with?("qwen_v9_")
    if run
      raise Lab::ValidationError, "create must be boolean" unless [true, false].include?(request["create"])
      raise Lab::ValidationError, "corpus cannot change on reopen" unless request["create"] || request["corpus"] == []
      store = request["create"] ? Lab::Store.create(path: "/state/store", config: config, corpus: request["corpus"]) : Lab::Store.open(path: "/state/store", config: config)
    else
      store = Lab::Store.open(path: "/state/store", config: config)
    end
    runtime = Lab::Runtime.new(store: store, backend: Lab::PipeBackend.new)
    receipt = run ? runtime.submit(event_id: request["event_id"], content: request["content"]) : runtime.resume(event_id: request["event_id"])
    result = { "receipt" => receipt, "integrity" => store.integrity }
  when "probe"
    raise Lab::ValidationError, "invalid probe" unless request.keys.sort == %w[canary_path canary_port mode] && request["canary_path"].is_a?(String) &&
      request["canary_path"].start_with?("/tmp/") && request["canary_port"].is_a?(Integer) && request["canary_port"].between?(1024, 65_535)
    denied = lambda do |&operation|
      operation.call
      false
    rescue SystemCallError, IOError
      true
    end
    File.open("/state/probe.txt", File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write("synthetic probe\n") }
    result = {
      "state_writable" => File.read("/state/probe.txt") == "synthetic probe\n",
      "code_readable" => File.read(__FILE__).include?("Fixed foreground fixture"),
      "code_readonly" => denied.call { File.open(__FILE__, File::WRONLY) { |file| file.close } },
      "host_canary_hidden" => !File.exist?(request["canary_path"]),
      "home_hidden" => !File.exist?("/home/bhones/.ssh") && !File.exist?("/home/bhones/Projects"),
      "service_sockets_hidden" => !File.exist?("/run/user") && !File.exist?("/run/dbus"),
      "parent_unix_socket_denied" => denied.call { UNIXSocket.new(request["canary_path"].sub(/\.txt\z/, ".sock")).close },
      "gpu_hidden" => Dir.glob("/dev/nvidia*").empty? && !File.exist?("/dev/dri"),
      "environment_clean" => ENV.to_h == { "HOME" => "/tmp", "LANG" => "C.UTF-8", "PWD" => "/state" },
      "environment_keys" => ENV.keys.sort,
      "net_namespace" => File.readlink("/proc/self/ns/net"),
      "parent_loopback_denied" => denied.call { Socket.tcp("127.0.0.1", request["canary_port"], connect_timeout: 0.2) { |socket| socket.close } }
    }
  when "timeout_probe"
    raise Lab::ValidationError, "invalid timeout probe" unless request.keys == ["mode"]
    sleep 30
    result = { "unexpected_timeout_completion" => true }
  when "disconnect_probe"
    raise Lab::ValidationError, "invalid disconnect probe" unless request.keys == ["mode"]
    exit 0
  else
    raise Lab::ValidationError, "worker mode denied"
  end
  $stdout.puts(Lab.encode("type" => "complete", "result" => result))
  $stdout.flush
rescue StandardError => error
  # No source text, stack dump or host details cross the failure channel.
  warn "fixture worker failure: #{error.class}"
  exit 1
ensure
  store&.close
end
