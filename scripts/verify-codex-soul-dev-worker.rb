#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "stringio"
require "tempfile"
require_relative "../lib/soul_core/dev_worker_service"
require_relative "../lib/soul_core/dev_worker_command"

errors = []
checks = 0
check = lambda do |description, condition|
  checks += 1
  if condition
    puts "PASS: #{description}"
  else
    errors << description
    warn "FAIL: #{description}"
  end
end

class FakeDevClient
  attr_reader :calls

  def initialize(response: nil)
    @calls = []
    @response = response
  end

  def chat(**arguments)
    @calls << arguments
    @response || SoulCore::LocalDevelopmentModelClient::Response.new(
      provider: "local.dev", model: "gpt-oss:20b", status: "ok", http_status: 200,
      content: '{"summary":"bounded"}', structured: { "summary" => "bounded" },
      error_message: nil, duration_seconds: 1.25,
      runtime_receipt: { "starting_core_id" => "dev", "selected_dev_core" => true }
    )
  end
end

class FakeTaskOrchestrator
  def with_task(request_id:, purpose:, on_progress: nil)
    value = yield("model" => "gpt-oss:20b", "endpoint" => "http://127.0.0.1:18083")
    [value, { "request_id" => request_id, "purpose" => purpose, "selected_dev_core" => true }]
  end
end

context = "Relevant source excerpt only.\nNo tools or execution claims are evidence."
schema = {
  "type" => "object",
  "properties" => { "summary" => { "type" => "string", "maxLength" => 2_000 } },
  "required" => ["summary"],
  "additionalProperties" => false
}
request = {
  "schema_version" => "soul.dev_worker.request.v1",
  "request_id" => "adapter_eval_001",
  "purpose" => "Critique the bounded adapter contract",
  "task_kind" => "critique",
  "repository_relative_paths" => ["lib/soul_core/dev_worker_service.rb"],
  "parent_supplied_context" => context,
  "expected_context_sha256" => Digest::SHA256.hexdigest(context),
  "output_schema" => schema,
  "timeout_seconds" => 45
}

client = FakeDevClient.new
timeouts = []
service = SoulCore::DevWorkerService.new(
  model_client_factory: ->(timeout) { timeouts << timeout; client },
  clock: -> { Time.utc(2026, 8, 1, 5, 0, 0) }
)

preview = service.preview(request: request)
check.call("preview validates without invoking the model", preview["ok"] && client.calls.empty?)
check.call("preview returns exact confirmation and digest", preview.dig("data", "confirmation_phrase") == "RUN_SOUL_DEV_WORKER adapter_eval_001" && preview.dig("data", "expected_digest").to_s.match?(/\A[0-9a-f]{64}\z/))
check.call("preview classifies critique as read only", preview.dig("data", "classification") == "read_only")

bad_digest = service.preview(request: request.merge("expected_context_sha256" => "0" * 64))
check.call("context digest mismatch blocks before model invocation", bad_digest["lifecycle_state"] == "blocked_for_human_review" && client.calls.empty?)

secret = "API_KEY=super-secret-value"
secret_result = service.preview(request: request.merge("parent_supplied_context" => secret, "expected_context_sha256" => Digest::SHA256.hexdigest(secret)))
check.call("obvious secret material blocks before model invocation", secret_result["message"].include?("secret material") && client.calls.empty?)

traversal = service.preview(request: request.merge("repository_relative_paths" => ["../private.env"]))
check.call("absolute or traversal repository paths are rejected", traversal["lifecycle_state"] == "blocked_for_human_review")
protected_path = service.preview(request: request.merge("repository_relative_paths" => ["config/.env"]))
check.call("known secret-store paths are rejected", protected_path["lifecycle_state"] == "blocked_for_human_review")
unknown_task = service.preview(request: request.merge("task_kind" => "execute_shell"))
check.call("only approved task kinds are accepted", unknown_task["message"].include?("task kind"))
open_schema = service.preview(request: request.merge("output_schema" => schema.merge("additionalProperties" => true)))
check.call("output schemas must be closed objects", open_schema["message"].include?("closed object"))
unsupported_schema = service.preview(request: request.merge("output_schema" => schema.merge("oneOf" => [])))
check.call("unsupported schema complexity is rejected", unsupported_schema["message"].include?("unsupported keywords"))

wrong_confirmation = service.execute(request: request, confirmation: "RUN SOMETHING ELSE", expected_digest: preview.dig("data", "expected_digest"))
check.call("execute requires exact confirmation", wrong_confirmation["lifecycle_state"] == "awaiting_input" && client.calls.empty?)
wrong_digest = service.execute(request: request, confirmation: preview.dig("data", "confirmation_phrase"), expected_digest: "f" * 64)
check.call("execute requires unchanged preview digest", wrong_digest["message"].include?("changed after preview") && client.calls.empty?)

result = service.execute(
  request: request,
  confirmation: preview.dig("data", "confirmation_phrase"),
  expected_digest: preview.dig("data", "expected_digest")
)
check.call("one valid request invokes the model once", result["ok"] && client.calls.length == 1 && timeouts == [45])
check.call("provider grammar receives structure while Soul retains range validation", !JSON.generate(client.calls.first.fetch(:response_schema)).include?("maxLength"))
check.call("model prompt receives the requested output schema", client.calls.first.fetch(:messages).last.fetch("content").include?(JSON.generate(schema)))
check.call("structured GPT-OSS requests use its documented low reasoning level", client.calls.first.fetch(:reasoning) == "low")
check.call("success records candidate classification and runtime receipt", result.dig("data", "candidate", "summary") == "bounded" && result.dig("data", "classification") == "read_only" && result.dig("data", "provider_receipt", "runtime_receipt", "selected_dev_core") == true)
check.call("success receipt omits supplied context", !JSON.generate(result).include?(context))
check.call("success uses a terminal lifecycle and mutation none", result["lifecycle_state"] == "complete" && result["mutation"] == "none")

draft_schema = {
  "type" => "object",
  "properties" => { "patch" => { "type" => "string", "maxLength" => 262_144 } },
  "required" => ["patch"],
  "additionalProperties" => false
}
draft_request = request.merge("request_id" => "adapter_patch_001", "task_kind" => "draft_patch", "output_schema" => draft_schema)
draft_preview = service.preview(request: draft_request)
check.call("draft patch is separately classified write candidate", draft_preview.dig("data", "classification") == "write_candidate")
missing_patch = service.preview(request: draft_request.merge("output_schema" => schema))
check.call("draft patch requires a bounded patch property", missing_patch["message"].include?("bounded patch string"))

failed_client = FakeDevClient.new(response: SoulCore::LocalDevelopmentModelClient::Response.new(
  provider: "local.dev", model: "gpt-oss:20b", status: "failed", http_status: 500,
  content: "", structured: nil, error_message: "provider stopped safely", duration_seconds: 0.5,
  runtime_receipt: { "starting_core_id" => "amd-free" }
))
failed_service = SoulCore::DevWorkerService.new(model_client_factory: ->(_timeout) { failed_client })
failed = failed_service.execute(request: request, confirmation: preview.dig("data", "confirmation_phrase"), expected_digest: preview.dig("data", "expected_digest"))
check.call("provider failure remains visible and terminal", failed["lifecycle_state"] == "failed" && failed["message"] == "provider stopped safely")

invalid_client = FakeDevClient.new(response: SoulCore::LocalDevelopmentModelClient::Response.new(
  provider: "local.dev", model: "gpt-oss:20b", status: "ok", http_status: 200,
  content: '{"unexpected":true}', structured: { "unexpected" => true }, error_message: nil,
  duration_seconds: 0.5, runtime_receipt: { "starting_core_id" => "dev" }
))
invalid_service = SoulCore::DevWorkerService.new(model_client_factory: ->(_timeout) { invalid_client })
invalid = invalid_service.execute(request: request, confirmation: preview.dig("data", "confirmation_phrase"), expected_digest: preview.dig("data", "expected_digest"))
check.call("structured output receives independent schema validation", invalid["lifecycle_state"] == "failed" && invalid["message"].include?("does not match"))

patch_client = FakeDevClient.new(response: SoulCore::LocalDevelopmentModelClient::Response.new(
  provider: "local.dev", model: "gpt-oss:20b", status: "ok", http_status: 200,
  content: '{"patch":"change the file"}', structured: { "patch" => "change the file" }, error_message: nil,
  duration_seconds: 0.5, runtime_receipt: { "starting_core_id" => "dev" }
))
patch_service = SoulCore::DevWorkerService.new(model_client_factory: ->(_timeout) { patch_client })
invalid_patch = patch_service.execute(request: draft_request, confirmation: draft_preview.dig("data", "confirmation_phrase"), expected_digest: draft_preview.dig("data", "expected_digest"))
check.call("draft patch output must be unified diff text", invalid_patch["lifecycle_state"] == "failed" && invalid_patch["message"].include?("unified diff"))

Tempfile.create(["soul-dev-worker-request", ".json"], "/tmp") do |file|
  file.write(JSON.generate(request))
  file.flush
  output = StringIO.new
  command = SoulCore::DevWorkerCommand.new(argv: ["preview", "--request-file", file.path], service: service, output: output)
  command_result = command.run
  parsed = JSON.parse(output.string)
  check.call("foreground CLI reads one bounded request and returns JSON", command_result.zero? && parsed.dig("data", "request_id") == "adapter_eval_001")

  link = "#{file.path}.link"
  File.symlink(file.path, link)
  linked_output = StringIO.new
  linked = SoulCore::DevWorkerCommand.new(argv: ["preview", "--request-file", link], service: service, output: linked_output).run
  check.call("foreground CLI rejects symlink request files", linked == 2 && JSON.parse(linked_output.string)["message"].include?("non-symlink"))
  File.unlink(link)
end

service_source = File.read(File.join(__dir__, "../lib/soul_core/dev_worker_service.rb"))
command_source = File.read(File.join(__dir__, "../lib/soul_core/dev_worker_command.rb"))
check.call("worker service has no repository read or write primitive", !service_source.match?(/File\.(?:read|binread|write|open)|IO\.(?:read|write)|Open3|system\(|spawn\(|`/))
check.call("command is foreground-only with no listener or retry loop", %w[TCPServer HTTPServer Thread.new Process.daemon setInterval].none? { |token| command_source.include?(token) })
check.call("local client uses the bounded per-request timeout", File.read(File.join(__dir__, "../lib/soul_core/local_development_model_client.rb")).include?("read_timeout: @timeout_seconds"))

fenced_body = JSON.generate("message" => { "content" => "```json\n{\"summary\":\"fenced but bounded\"}\n```" })
fenced_client = SoulCore::LocalDevelopmentModelClient.new(
  task_orchestrator: FakeTaskOrchestrator.new,
  http_post: ->(_uri, _payload) { { status: 200, body: fenced_body } }
)
fenced_response = fenced_client.chat(
  messages: [{ "role" => "user", "content" => "Return the schema." }],
  purpose: "fenced_json_compatibility", response_schema: schema, reasoning: false
)
check.call("local client accepts one whole fenced JSON document", fenced_response.ok? && fenced_response.structured == { "summary" => "fenced but bounded" })

mixed_body = JSON.generate("message" => { "content" => "Here is JSON:\n```json\n{\"summary\":\"mixed\"}\n```" })
mixed_client = SoulCore::LocalDevelopmentModelClient.new(
  task_orchestrator: FakeTaskOrchestrator.new,
  http_post: ->(_uri, _payload) { { status: 200, body: mixed_body } }
)
mixed_response = mixed_client.chat(
  messages: [{ "role" => "user", "content" => "Return the schema." }],
  purpose: "mixed_json_rejection", response_schema: schema, reasoning: false
)
check.call("local client rejects prose mixed with fenced JSON", !mixed_response.ok? && mixed_response.error_message.include?("invalid structured output"))

http_error_body = JSON.generate("error" => "grammar rejected safely")
http_error_client = SoulCore::LocalDevelopmentModelClient.new(
  task_orchestrator: FakeTaskOrchestrator.new,
  http_post: ->(_uri, _payload) { { status: 400, body: http_error_body } }
)
http_error = http_error_client.chat(
  messages: [{ "role" => "user", "content" => "Return the schema." }],
  purpose: "provider_http_error", response_schema: schema, reasoning: false
)
check.call("provider HTTP errors retain their real message and runtime receipt", http_error.http_status == 400 && http_error.error_message == "grammar rejected safely" && http_error.runtime_receipt["selected_dev_core"] == true)

abort "#{errors.length} Codex–Soul Dev Worker checks failed: #{errors.join('; ')}" unless errors.empty?
puts "Codex–Soul Dev Worker verification passed (#{checks} checks)."
