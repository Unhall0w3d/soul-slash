#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "socket"
require "stringio"
require "tmpdir"
require_relative "../lib/soul_core/continuity_lab/chat_application"
require_relative "../lib/soul_core/continuity_lab/chat_gateway"
require_relative "../lib/soul_core/continuity_lab/runtime"
require_relative "../lib/soul_core/dashboard_server"
require_relative "continuity-lab-chat"

Lab = SoulCore::ContinuityLab

class A22IntegrationExecutor
  attr_reader :config, :profile, :backend, :calls

  def initialize(after_run: nil)
    @config = Lab::Config.new("context_mode" => "explicit_v1")
    @profile = "fixture_a22"
    @backend = Lab::FakeBackend.new(responses: Array.new(16, JSON.generate("action" => "reply", "content" => "réponse 雪")))
    @after_run = after_run
    @calls = 0
  end

  def run(state_directory:, event_id:, content:)
    @calls += 1
    store = Lab::Store.open(path: File.join(state_directory, "store"), config: config)
    Lab::Runtime.new(store: store, backend: backend).submit(event_id: event_id, content: content)
  ensure
    store&.close
    @after_run&.call
  end
end

module VerifyContinuityLabChatIntegrationA22
  TOKEN = "synthetic-integration-bearer-token-0123456789"
  CONVERSATION = "integration_a22"
  module_function

  def check(name, count)
    raise "FAIL: #{name}" unless yield

    count[0] += 1
    puts "PASS: #{name}"
  rescue StandardError => error
    count[1] << [name, error.class, error.message]
    puts "FAIL: #{name} (#{error.class}: #{error.message})"
  end

  def raises(error_class)
    yield
    false
  rescue error_class
    true
  end

  def config = Lab::Config.new("context_mode" => "explicit_v1")

  def gateway(root, executor)
    Lab::ChatGateway.create(path: root, executor: executor)
    Lab::ChatGateway.new(path: root, executor: executor)
  end

  def payload(messages, stream: false)
    JSON.generate("model" => Lab::ChatApplication::MODEL, "messages" => messages, "stream" => stream)
  end

  def socket_request(server, request_text, ready: nil, release: nil)
    client, peer = UNIXSocket.pair
    thread = Thread.new { server.send(:handle, peer) }
    client.write(request_text)
    if ready
      ready.pop
      client.close
      release << true
      thread.join
      return nil
    end
    response = +"".b
    response << client.read until client.eof?
    client.close
    thread.value
    response
  ensure
    client&.close unless client&.closed?
    peer&.close unless peer&.closed?
  end

  def request_text(body, stream: false, conversation: CONVERSATION)
    bytes = body.b
    "POST /v1/chat/completions HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer #{TOKEN}\r\n" \
      "X-Soul-Conversation-ID: #{conversation}\r\nContent-Type: application/json\r\n" \
      "Content-Length: #{bytes.bytesize}\r\nConnection: close\r\n\r\n".b + bytes
  end

  def parse_http(response)
    header, body = response.split("\r\n\r\n".b, 2)
    status = header.lines.first.split.fetch(1).to_i
    headers = header.lines.drop(1).to_h do |line|
      key, value = line.split(":", 2)
      [key.downcase, value.strip]
    end
    [status, headers, body]
  end

  def cli(argv)
    original_out, original_err = $stdout, $stderr
    out, err = StringIO.new, StringIO.new
    $stdout, $stderr = out, err
    status = SoulCore::ContinuityLab::ChatCLI.run(argv)
    [status, out.string, err.string]
  ensure
    $stdout, $stderr = original_out, original_err
  end

  def run
    checks = [0, []]
    Dir.mktmpdir("soul-a22-chat-integration-") do |temporary|
      root = File.join(temporary, "transport-root")
      executor = A22IntegrationExecutor.new
      adapter = gateway(root, executor)
      app = Lab::ChatApplication.new(backend: adapter, bearer_token: TOKEN)
      server = SoulCore::DashboardServer.new(host: "127.0.0.1", port: 0, application: app, output: StringIO.new)

      first_messages = [{ "role" => "user", "content" => "How do you greet in French?雪" }]
      json_response = socket_request(server, request_text(payload(first_messages)))
      status, json_headers, json_bytes = parse_http(json_response)
      json_data = JSON.parse(json_bytes.force_encoding(Encoding::UTF_8))
      accepted = json_data.dig("choices", 0, "message", "content")
      check("UNIXSocket HTTP path parses UTF-8 body bytes and returns durable JSON completion", checks) do
        status == 200 && json_headers["content-length"] == json_bytes.bytesize.to_s &&
          json_data["object"] == "chat.completion" && accepted == "réponse 雪" && executor.backend.calls == 1
      end

      sse_response = socket_request(server, request_text(payload(first_messages, stream: true)))
      sse_status, sse_headers, sse_bytes = parse_http(sse_response)
      frames = sse_bytes.force_encoding(Encoding::UTF_8).split("\n\n").reject(&:empty?)
      data_frames = frames[0...-1].map { |frame| JSON.parse(frame.delete_prefix("data: ")) }
      stream_answer = data_frames[1].dig("choices", 0, "delta", "content")
      check("buffered SSE carries the same durable answer and retry executes no second model call", checks) do
        sse_status == 200 && sse_headers["content-type"].start_with?("text/event-stream") &&
          stream_answer == accepted && frames.last == "data: [DONE]" && executor.backend.calls == 1 && executor.calls == 1
      end

      second_messages = first_messages + [{ "role" => "assistant", "content" => accepted },
        { "role" => "user", "content" => "And thank you?" }]
      second = socket_request(server, request_text(payload(second_messages)))
      second_status, _second_headers, second_bytes = parse_http(second)
      second_data = JSON.parse(second_bytes.force_encoding(Encoding::UTF_8))
      check("serialized full history advances a second durable turn with the first reply", checks) do
        second_status == 200 && second_data.dig("choices", 0, "message", "content") == accepted &&
          executor.backend.calls == 2 && second_data.dig("soul", "event_id") == "turn-0002"
      end

      dropped = Queue.new
      continue = Queue.new
      disconnect_executor = A22IntegrationExecutor.new(after_run: -> { dropped << true; continue.pop })
      disconnect_root = File.join(temporary, "disconnect-root")
      disconnect_gateway = gateway(disconnect_root, disconnect_executor)
      disconnect_app = Lab::ChatApplication.new(backend: disconnect_gateway, bearer_token: TOKEN)
      disconnect_server = SoulCore::DashboardServer.new(host: "127.0.0.1", port: 0,
        application: disconnect_app, output: StringIO.new)
      client, peer = UNIXSocket.pair
      disconnect_thread = Thread.new { disconnect_server.send(:handle, peer) }
      client.write(request_text(payload([{ "role" => "user", "content" => "disconnect after commit" }])))
      dropped.pop
      client.close
      continue << true
      disconnect_thread.join
      retry_response = socket_request(disconnect_server,
        request_text(payload([{ "role" => "user", "content" => "disconnect after commit" }])))
      retry_status, _retry_headers, retry_bytes = parse_http(retry_response)
      retry_data = JSON.parse(retry_bytes.force_encoding(Encoding::UTF_8))
      check("receiver disconnect after commit is recovered by retry without another executor call", checks) do
        retry_status == 200 && retry_data.dig("choices", 0, "message", "content") == "réponse 雪" &&
          retry_data.dig("soul", "replayed") && disconnect_executor.calls == 1 && disconnect_executor.backend.calls == 1
      end
      disconnect_gateway.close
      adapter.close

      stop_executor = Object.new
      stop_calls = 0
      stop_executor.define_singleton_method(:cancel!) { stop_calls += 1 }
      foreground = SoulCore::ContinuityLab::ForegroundChatServer.new(executor: stop_executor,
        host: "127.0.0.1", port: 0, application: Object.new, output: StringIO.new)
      foreground.stop
      check("foreground stop cancels executor before any listener is created", checks) do
        stop_calls == 1 && foreground.instance_variable_get(:@listener).nil?
      end

      cli_root = File.join(temporary, "cli-root")
      init_status, init_out, _init_err = cli(["--init", cli_root])
      check("CLI init creates a fresh private root without preparing inference", checks) do
        init_status == 0 && JSON.parse(init_out).fetch("listener_started") == false &&
          File.stat(cli_root).mode & 0o777 == 0o700
      end
      check_status, check_out, _check_err = cli(["--check", cli_root])
      check("CLI check reads retained root without listener or backend health probe", checks) do
        check_status == 0 && JSON.parse(check_out).fetch("backend_health_checked") == false &&
          JSON.parse(check_out).fetch("listener_started") == false
      end

      missing_corpus_root = File.join(temporary, "missing-corpus-root")
      missing_status, = cli(["--init", missing_corpus_root, "--corpus", File.join(temporary, "absent.json")])
      check("CLI rejects missing corpus file", checks) { missing_status == 2 && !File.exist?(missing_corpus_root) }
      invalid_corpus = File.join(temporary, "invalid-corpus.json")
      File.write(invalid_corpus, "{}")
      File.chmod(0o600, invalid_corpus)
      invalid_corpus_root = File.join(temporary, "invalid-corpus-root")
      invalid_status, = cli(["--init", invalid_corpus_root, "--corpus", invalid_corpus])
      check("CLI rejects corpus with invalid shape", checks) { invalid_status == 2 && !File.exist?(invalid_corpus_root) }
      args_status, = cli(["--init", File.join(temporary, "unused"), "--check", cli_root])
      check("CLI rejects conflicting operation arguments", checks) { args_status == 2 }

      unsafe_key_root = File.join(temporary, "unsafe-key-root")
      unsafe_init_status, = cli(["--init", unsafe_key_root])
      unsafe_key = File.join(temporary, "unsafe.key")
      File.write(unsafe_key, "unsafe-synthetic-key-material-0123456789\n")
      File.chmod(0o644, unsafe_key)
      chat_executor_class = Lab::ChatExecutor
      original_prepare = chat_executor_class.instance_method(:prepare!)
      preparations = 0
      chat_executor_class.define_method(:prepare!) { preparations += 1; raise "prepare must not run for unsafe key" }
      serve_status, _serve_out, serve_err = cli(["--serve", unsafe_key_root, "--key-file", unsafe_key, "--approved-quiet-window"])
      chat_executor_class.define_method(:prepare!, original_prepare)
      check("unsafe 0644 serve key is rejected before executor preparation", checks) do
        outcome = unsafe_init_status == 0 && serve_status == 2 && preparations.zero? &&
          serve_err.include?("ValidationError") && !serve_err.include?("unsafe-synthetic-key")
        raise "init=#{unsafe_init_status} status=#{serve_status} prepare_calls=#{preparations} stderr=#{serve_err.inspect}" unless outcome
        true
      end

      puts "RESULT: #{checks[0]} A22 integration checks passed, #{checks[1].length} failed; socket path used UNIXSocket.pair only; model calls used scripted FakeBackend."
      checks[1].each { |name, klass, message| warn "FAILURE DETAIL: #{name}: #{klass}: #{message}" }
      raise "#{checks[1].length} A22 integration verifier check(s) failed" unless checks[1].empty?
    end
  end
end

VerifyContinuityLabChatIntegrationA22.run
