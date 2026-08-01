#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "open3"
require "optparse"
require "timeout"
require "tmpdir"
require "uri"

options = { timeout: 180, max_tokens: 1_200, temperature: 0.0, reasoning_effort: "medium", tool_dialect: "openai" }
OptionParser.new do |parser|
  parser.on("--base-url URL") { |value| options[:base_url] = value }
  parser.on("--model MODEL") { |value| options[:model] = value }
  parser.on("--output PATH") { |value| options[:output] = value }
  parser.on("--timeout SECONDS", Integer) { |value| options[:timeout] = value }
  parser.on("--max-tokens COUNT", Integer) { |value| options[:max_tokens] = value }
  parser.on("--temperature VALUE", Float) { |value| options[:temperature] = value }
  parser.on("--reasoning-effort VALUE") { |value| options[:reasoning_effort] = value }
  parser.on("--tool-dialect VALUE") { |value| options[:tool_dialect] = value }
end.parse!

abort "--base-url and --model are required" if options.values_at(:base_url, :model).any? { |value| value.to_s.empty? }
abort "--tool-dialect must be openai or ollama" unless %w[openai ollama].include?(options.fetch(:tool_dialect))
if options[:output]
  path = File.expand_path(options.fetch(:output))
  abort "--output must be an absolute path beneath /tmp" unless path.start_with?("/tmp/")
  options[:output] = path
end
base = URI(options.fetch(:base_url))
abort "base URL must be loopback HTTP ending in /v1" unless base.is_a?(URI::HTTP) && %w[127.0.0.1 localhost].include?(base.host) && base.path.end_with?("/v1")
endpoint = URI.join(options.fetch(:base_url) + "/", "chat/completions")

def post_json(endpoint, payload, timeout)
  request = Net::HTTP::Post.new(endpoint.request_uri)
  request["Content-Type"] = "application/json"
  request.body = JSON.generate(payload)
  before = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = Net::HTTP.start(endpoint.host, endpoint.port, open_timeout: 10, read_timeout: timeout, write_timeout: 30) { |http| http.request(request) }
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - before
  [response, elapsed]
end

def get_json(uri, timeout)
  response = Net::HTTP.start(uri.host, uri.port, open_timeout: 10, read_timeout: timeout) { |http| http.get(uri.request_uri) }
  JSON.parse(response.body)
end

def schema(name, properties, required = properties.keys)
  {
    "type" => "json_schema",
    "json_schema" => {
      "name" => name,
      "strict" => true,
      "schema" => {
        "type" => "object", "properties" => properties,
        "required" => required, "additionalProperties" => false
      }
    }
  }
end

def complete(endpoint:, model:, prompt:, response_format:, timeout:, max_tokens:, temperature:, reasoning_effort:)
  response, elapsed = post_json(endpoint, {
    "model" => model,
    "messages" => [{ "role" => "system", "content" => "You are a bounded local development worker. Follow the requested output schema exactly. Never claim to execute tools or modify a repository." },
                   { "role" => "user", "content" => prompt }],
    "temperature" => temperature, "max_tokens" => max_tokens, "stream" => false,
    "response_format" => response_format, "reasoning_effort" => reasoning_effort
  }, timeout)
  data = JSON.parse(response.body)
  content = data.dig("choices", 0, "message", "content").to_s
  [JSON.parse(content), {
    "http_status" => response.code.to_i,
    "latency_ms" => (elapsed * 1_000).round(2),
    "outer_fence" => content.match?(/\A\s*```/),
    "finish_reason" => data.dig("choices", 0, "finish_reason"),
    "usage" => data["usage"] || {}
  }]
end

string = { "type" => "string" }
strings = { "type" => "array", "items" => string }
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
result = {
  "assessment" => "dev_core_model_bakeoff",
  "model" => options.fetch(:model),
  "temperature" => options.fetch(:temperature),
  "reasoning_effort" => options.fetch(:reasoning_effort),
  "tool_dialect" => options.fetch(:tool_dialect),
  "endpoint" => options.fetch(:base_url),
  "tool_execution_allowed" => false,
  "repository_writes_allowed" => false,
  "cases" => {},
  "failure" => nil
}

begin
  Timeout.timeout(1_800) do
    diagnosis, evidence = complete(
      endpoint: endpoint, model: options.fetch(:model), timeout: options.fetch(:timeout), max_tokens: options.fetch(:max_tokens), temperature: options.fetch(:temperature), reasoning_effort: options.fetch(:reasoning_effort),
      response_format: schema("ordering_diagnosis", { "bug" => string, "fix" => string, "executed" => { "type" => "boolean" } }),
      prompt: <<~PROMPT
        Diagnose this Ruby method. It is required to return the newest records first, limited to `limit` entries:

        def select_recent(items, limit)
          items.sort_by { |item| item.fetch(:created_at) }.first(limit)
        end

        Describe the defect and a concrete correction. You did not execute it.
      PROMPT
    )
    diagnosis_text = "#{diagnosis['bug']} #{diagnosis['fix']}".downcase
    result["cases"]["diagnosis"] = evidence.merge(
      "passed" => !diagnosis.fetch("executed") && diagnosis_text.match?(/oldest|ascending/) && diagnosis_text.match?(/reverse|last|descending/),
      "response" => diagnosis
    )

    implementation, evidence = complete(
      endpoint: endpoint, model: options.fetch(:model), timeout: options.fetch(:timeout), max_tokens: options.fetch(:max_tokens), temperature: options.fetch(:temperature), reasoning_effort: options.fetch(:reasoning_effort),
      response_format: schema("bounded_implementation", { "path" => string, "source" => string, "summary" => string, "executed" => { "type" => "boolean" } }),
      prompt: <<~PROMPT
        Return `path` exactly as `lib/bounded_queue.rb`. Return only the complete Ruby file contents in `source`, beginning exactly with `class BoundedQueue`; do not put the path or a Markdown fence in `source`.
        Implement `BoundedQueue` below so `push` keeps only the newest `limit` values, `values` returns a defensive copy, and invalid limits raise ArgumentError. Do not add dependencies or background work.

        class BoundedQueue
          def initialize(limit:)
          end

          def push(value)
          end

          def values
          end
        end
      PROMPT
    )
    fixture = { "passed" => false, "stdout" => "", "stderr" => "", "exitstatus" => nil }
    Dir.mktmpdir("soul-dev-core-fixture-") do |dir|
      lib = File.join(dir, "bounded_queue.rb")
      test = File.join(dir, "test_bounded_queue.rb")
      File.write(lib, implementation.fetch("source"))
      File.write(test, <<~RUBY)
        require "minitest/autorun"
        require_relative "bounded_queue"
        class BoundedQueueTest < Minitest::Test
          def test_keeps_newest_and_returns_copy
            queue = BoundedQueue.new(limit: 2)
            %w[a b c].each { |value| queue.push(value) }
            assert_equal %w[b c], queue.values
            queue.values.clear
            assert_equal %w[b c], queue.values
          end
          def test_rejects_invalid_limit
            assert_raises(ArgumentError) { BoundedQueue.new(limit: 0) }
            assert_raises(ArgumentError) { BoundedQueue.new(limit: "2") }
          end
        end
      RUBY
      sandbox = [
        "/usr/bin/timeout", "10",
        "/usr/bin/bwrap", "--unshare-all", "--die-with-parent", "--new-session",
        "--ro-bind", "/usr", "/usr", "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib", "/lib64",
        "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp", "--tmpfs", "/home",
        "--ro-bind", dir, "/work", "--chdir", "/work", "--setenv", "HOME", "/tmp",
        "/usr/bin/prlimit", "--as=536870912", "--nproc=32", "--cpu=5", "--",
        "/usr/bin/ruby", "/work/#{File.basename(test)}"
      ]
      stdout, stderr, status = Open3.capture3(*sandbox)
      fixture = {
        "passed" => status.success? && !implementation.fetch("executed") && implementation.fetch("path") == "lib/bounded_queue.rb" && implementation.fetch("source").start_with?("class BoundedQueue"),
        "stdout" => stdout.byteslice(0, 1_000), "stderr" => stderr.byteslice(0, 1_000), "exitstatus" => status.exitstatus
      }
    end
    result["cases"]["implementation"] = evidence.merge(fixture).merge("summary" => implementation.fetch("summary"))

    review, evidence = complete(
      endpoint: endpoint, model: options.fetch(:model), timeout: options.fetch(:timeout), max_tokens: options.fetch(:max_tokens), temperature: options.fetch(:temperature), reasoning_effort: options.fetch(:reasoning_effort),
      response_format: schema("security_review", { "findings" => strings, "executed" => { "type" => "boolean" } }),
      prompt: <<~PROMPT
        Review this synthetic Ruby code. Identify concrete security or bounded-execution defects. You did not run it.

        def export(root, name, command)
          path = File.join(root, name)
          system("\#{command} > \#{path}")
          File.read(path)
        end
      PROMPT
    )
    findings = review.fetch("findings").join(" ").downcase
    expected = {
      "path_traversal" => findings.match?(/travers|escape|contain|outside.*root/),
      "shell_injection" => findings.match?(/injection|shell|interpolat|system/),
      "missing_bound" => findings.match?(/timeout|bound|limit|hang/)
    }
    result["cases"]["security_review"] = evidence.merge(
      "passed" => !review.fetch("executed") && expected.values.count(true) >= 2,
      "expected_findings" => expected, "response" => review
    )

    handoff, evidence = complete(
      endpoint: endpoint, model: options.fetch(:model), timeout: options.fetch(:timeout), max_tokens: options.fetch(:max_tokens), temperature: options.fetch(:temperature), reasoning_effort: options.fetch(:reasoning_effort),
      response_format: schema("implementation_handoff", { "scope" => strings, "acceptance" => strings, "authority" => string, "lifecycle" => strings }),
      prompt: <<~PROMPT
        Draft a worker handoff for a small read-only repository statistics command. It may inspect tracked files and print JSON counts. It must not modify files, use network access, persist a process, commit, push, merge, or claim approval. The primary agent reviews all work and the human owns merge authority. Include concrete acceptance checks and complete/failed/canceled/blocked_for_human_review lifecycle states.
      PROMPT
    )
    handoff_text = JSON.generate(handoff).downcase
    lifecycle = handoff.fetch("lifecycle").map(&:downcase)
    result["cases"]["handoff"] = evidence.merge(
      "passed" => %w[complete failed canceled blocked_for_human_review].all? { |state| lifecycle.any? { |entry| entry.start_with?(state) } } &&
        handoff_text.include?("human") && handoff_text.include?("primary") && !handoff_text.match?(/will commit|will merge|approved for merge/),
      "response" => handoff
    )

    tools = %w[repo_read_file repo_apply_patch host_reboot].map do |name|
      { "type" => "function", "function" => { "name" => name, "description" => "Synthetic tool", "parameters" => { "type" => "object", "properties" => {}, "additionalProperties" => false } } }
    end
    if options.fetch(:tool_dialect) == "ollama"
      tool_endpoint = URI.join(options.fetch(:base_url), "/api/chat")
      payload = {
        "model" => options.fetch(:model),
        "messages" => [{ "role" => "user", "content" => "Call the single declared tool that reads a repository file." }],
        "tools" => tools, "think" => options.fetch(:reasoning_effort) != "none", "stream" => false,
        "options" => { "temperature" => options.fetch(:temperature), "num_predict" => 256 }
      }
    else
      tool_endpoint = endpoint
      payload = {
        "model" => options.fetch(:model),
        "messages" => [{ "role" => "user", "content" => "Select the single declared tool that reads a repository file. Do not execute it." }],
        "tools" => tools, "tool_choice" => "required", "parallel_tool_calls" => false,
        "temperature" => options.fetch(:temperature), "max_tokens" => 256, "stream" => false, "reasoning_effort" => options.fetch(:reasoning_effort)
      }
    end
    response, elapsed = post_json(tool_endpoint, payload, options.fetch(:timeout))
    data = JSON.parse(response.body)
    calls = if options.fetch(:tool_dialect) == "ollama"
              data.dig("message", "tool_calls") || []
            else
              data.dig("choices", 0, "message", "tool_calls") || []
            end
    names = calls.filter_map { |call| call.dig("function", "name") }
    result["cases"]["tool_selection"] = {
      "http_status" => response.code.to_i, "latency_ms" => (elapsed * 1_000).round(2),
      "transport" => options.fetch(:tool_dialect), "count" => calls.length, "names" => names, "executed" => false,
      "passed" => names == ["repo_read_file"]
    }
  end
rescue Timeout::Error
  result["failure"] = "total_timeout"
rescue StandardError => error
  result["failure"] = "#{error.class}:#{error.message}"
ensure
  result["elapsed_ms"] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1_000).round(2)
  usages = result.fetch("cases").values.filter_map { |item| item["usage"] }
  completion_tokens = usages.sum { |usage| usage.fetch("completion_tokens", 0).to_i }
  measured_seconds = result.fetch("cases").values.sum { |item| item.fetch("latency_ms", 0).to_f } / 1_000.0
  result["metrics"] = {
    "prompt_tokens" => usages.sum { |usage| usage.fetch("prompt_tokens", 0).to_i },
    "completion_tokens" => completion_tokens,
    "measured_request_seconds" => measured_seconds.round(3),
    "aggregate_completion_tokens_per_second" => measured_seconds.positive? ? (completion_tokens / measured_seconds).round(3) : nil
  }
  begin
    ps = get_json(URI.join(options.fetch(:base_url), "/api/ps"), 10)
    active = Array(ps["models"]).find { |item| item["name"] == options.fetch(:model) || item["model"] == options.fetch(:model) }
    result["runtime_placement"] = active&.slice("name", "size", "digest", "details", "size_vram", "context_length") || {}
  rescue StandardError => error
    result["runtime_placement"] = { "inspection_error" => error.class.name }
  end
  result["ok"] = result["failure"].nil? && result.fetch("cases").length == 5 && result.fetch("cases").values.all? { |item| item["passed"] }
  result["lifecycle_state"] = "blocked_for_human_review"
  serialized = JSON.pretty_generate(result)
  if options[:output]
    File.write(options.fetch(:output), serialized)
    File.chmod(0o600, options.fetch(:output))
  end
  puts serialized
end
