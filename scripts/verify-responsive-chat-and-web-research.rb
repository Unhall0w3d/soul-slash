#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "tmpdir"
require "uri"

require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/conversation_artifact_creation_service"
require_relative "../lib/soul_core/conversation_orchestrator"
require_relative "../lib/soul_core/conversation_provider_contract"
require_relative "../lib/soul_core/conversation_runtime"
require_relative "../lib/soul_core/dashboard_http_application"
require_relative "../lib/soul_core/dashboard_server"
require_relative "../lib/soul_core/web_research_service"

failures = []
check = lambda do |name, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{name}"
  failures << name unless condition
end

class FixtureSuccess < Net::HTTPOK
  def initialize(body, media_type)
    super("1.1", "200", "OK")
    @fixture_body = body
    self["content-type"] = media_type
    self["content-length"] = body.bytesize.to_s
  end

  def read_body
    yield @fixture_body
  end
end

class FixtureRedirect < Net::HTTPFound
  def initialize(location)
    super("1.1", "302", "Found")
    self["location"] = location
  end
end

class FixtureHttp
  attr_accessor :ipaddr, :use_ssl, :open_timeout, :read_timeout

  def initialize(host, handler)
    @host = host
    @handler = handler
  end

  def request(request)
    yield @handler.call(@host, request)
  end
end

lookup_payload = lambda do |query|
  if query.include?("Unknown")
    { "Heading" => "", "AbstractText" => "", "Answer" => "", "Definition" => "" }
  else
    { "Heading" => "Ruby", "AbstractText" => "Ruby is a programming language.", "AbstractSource" => "Fixture reference", "AbstractURL" => "https://example.com/ruby" }
  end
end

handler = lambda do |host, request|
  case host
  when "api.duckduckgo.com"
    query = URI.decode_www_form(URI.parse(request.path).query.to_s).to_h.fetch("q", "")
    FixtureSuccess.new(JSON.generate(lookup_payload.call(query)), "application/x-javascript")
  when "searx.local"
    FixtureSuccess.new(JSON.generate("results" => [
      { "title" => "Public result", "url" => "https://example.com/research", "content" => "Public snippet" },
      { "title" => "Private result", "url" => "https://192.168.1.77/secret", "content" => "Must be blocked" }
    ]), "application/json")
  when "example.com"
    FixtureSuccess.new("<html><script>ignore()</script><body>Bounded public evidence.</body></html>", "text/html")
  when "redirect.example"
    FixtureRedirect.new("https://192.168.1.99/secret")
  else
    raise "unexpected fixture host: #{host}"
  end
end

resolver = lambda do |host|
  {
    "api.duckduckgo.com" => ["52.1.2.3"],
    "searx.local" => ["192.168.1.10"],
    "example.com" => ["93.184.216.34"],
    "redirect.example" => ["93.184.216.35"]
  }.fetch(host, [host])
end
http_factory = ->(host, _port) { FixtureHttp.new(host, handler) }
clock = -> { Time.utc(2026, 7, 16, 20, 0, 0) }

service = SoulCore::WebResearchService.new(
  env: { "SOUL_WEB_SEARCH_PROVIDER" => "searxng", "SOUL_WEB_SEARXNG_URL" => "http://searx.local", "SOUL_WEB_ALLOW_PRIVATE_SEARXNG" => "true" },
  clock: clock,
  resolver: resolver,
  http_factory: http_factory
)

lookup = service.lookup("What is Ruby?")
check.call("Instant Answer lookup returns one provenance-bound orientation", lookup["ok"] && lookup.dig("data", "found") == true && lookup.dig("data", "answer", "source_url") == "https://example.com/ruby")
empty_lookup = service.lookup("What is Unknown Fixture?")
check.call("missing Instant Answer is a normal found-false completion", empty_lookup["ok"] && empty_lookup.dig("data", "found") == false && empty_lookup["lifecycle_state"] == "complete")

research = service.research(queries: ["bounded fixture"], source_limit: 2)
sources = research.dig("data", "sources") || []
check.call("private SearXNG is allowed only through explicit configuration", research["ok"] && research.dig("data", "provider") == "searxng")
check.call("public source is retrieved with digest and normalized text", sources.first&.dig("status") == "ok" && sources.first&.dig("content_digest")&.length == 64 && sources.first&.dig("text") == "Bounded public evidence.")
check.call("private result URL never inherits provider exception", sources.last&.dig("status") != "ok" && sources.last&.dig("reason")&.include?("blocked network"))

private_without_opt_in = SoulCore::WebResearchService.new(
  env: { "SOUL_WEB_SEARCH_PROVIDER" => "searxng", "SOUL_WEB_SEARXNG_URL" => "http://searx.local" },
  resolver: resolver,
  http_factory: http_factory
).search("fixture")
check.call("private SearXNG requires the separate opt-in", !private_without_opt_in["ok"])

public_http = SoulCore::WebResearchService.new(
  env: { "SOUL_WEB_SEARCH_PROVIDER" => "searxng", "SOUL_WEB_SEARXNG_URL" => "http://public-search.example", "SOUL_WEB_ALLOW_PRIVATE_SEARXNG" => "true" },
  resolver: ->(_host) { ["93.184.216.36"] },
  http_factory: ->(_host, _port) { raise "public HTTP provider must be rejected before transport" }
).search("fixture")
check.call("private-provider opt-in does not permit public HTTP SearXNG", !public_http["ok"])

redirect_handler = lambda do |host, _request|
  raise "unexpected provider host" unless host == "searx.local"
  FixtureRedirect.new("http://other-searx.local/search?q=fixture&format=json")
end
provider_redirect = SoulCore::WebResearchService.new(
  env: { "SOUL_WEB_SEARCH_PROVIDER" => "searxng", "SOUL_WEB_SEARXNG_URL" => "http://searx.local", "SOUL_WEB_ALLOW_PRIVATE_SEARXNG" => "true" },
  resolver: ->(host) { host == "searx.local" ? ["192.168.1.10"] : ["192.168.1.11"] },
  http_factory: ->(host, _port) { FixtureHttp.new(host, redirect_handler) }
).search("fixture")
check.call("SearXNG redirects cannot change the configured authority", !provider_redirect["ok"] && provider_redirect["reason"].include?("changed the configured authority"))

redirect = service.fetch_source("https://redirect.example/start")
check.call("redirects are revalidated and cannot enter private space", !redirect["ok"] && redirect["reason"].include?("blocked network"))
check.call("exhausted total byte budget blocks before transport", service.fetch_source("https://example.com/research", remaining_bytes: 0)["reason"] == "research byte budget is exhausted")
check.call("query count is bounded", service.research(queries: %w[one two three four])["lifecycle_state"] == "awaiting_input")
check.call("query bytes are bounded", service.lookup("x" * 501)["lifecycle_state"] == "awaiting_input")
check.call("query control characters are rejected", service.lookup("bad\u0001query")["lifecycle_state"] == "awaiting_input")

orchestrator = SoulCore::ConversationOrchestrator.new
lookup_plan = orchestrator.plan(message: "Can you tell me about Ruby?", provider_available: true)
research_plan = orchestrator.plan(message: "Research current Ruby security documentation and cite sources", provider_available: true)
artifact_research_plan = orchestrator.plan(message: "Please research bash scripting and create a proposal based on current sources", provider_available: true)
reflection_plan = orchestrator.plan(message: "Reflect on this research and propose memory candidates", provider_available: true)
hello_soul_request = "I'd like you to do some research on the topic of how best to add/apply personalities/personas to Mistral in the most compatible way. I would like to improve the experience. Based on your research, please use the appropriate skill to provide me a proposal."
hello_soul_plan = orchestrator.plan(message: hello_soul_request, provider_available: true)
environment_review_plan = orchestrator.plan(message: "are you able to scan or review your environment to get an understanding?", provider_available: true)
environment_catalog_plan = orchestrator.plan(message: "Well, take a look at what skills you have. Is there a suitable skill for reviewing the environment?", provider_available: true)
conversation_recall_plan = orchestrator.plan(message: "What is the synthetic project's codename?", provider_available: true)
check.call("narrow orientation routes to web lookup", lookup_plan.kind == "web_lookup")
check.call("conversation recall is not misrouted to public lookup", conversation_recall_plan.kind == "direct_model")
check.call("explicit current-source request routes to research", research_plan.kind == "web_research")
check.call("research remains ahead of artifact drafting", artifact_research_plan.kind == "web_research" && artifact_research_plan.flags["research_deliverable"] == true)
check.call("research reflection requires an explicit bounded request", reflection_plan.kind == "research_reflection")
check.call("exact failed Hello Soul request now requires research and a deliverable handoff", hello_soul_plan.kind == "web_research" && hello_soul_plan.flags["research_deliverable"] == true)
check.call("exact environment-review request routes to bounded host evidence", environment_review_plan.kind == "skill_only" && environment_review_plan.tool_ids == ["host.system_status"])
check.call("catalog suitability question lists capabilities without silently running the host scan", environment_catalog_plan.kind == "skill_only" && environment_catalog_plan.tool_ids == ["assistant-skill-catalog"])

truth_guard = SoulCore::ConversationResponseTruthGuard.new
guarded = truth_guard.filter("I'm curious and glad to meet you. The air feels different today, and the local system is settling into its rhythm. What shall we explore?")
check.call("direct-model truth guard removes unsupported off-screen and host observations", !guarded.valid && guarded.removed.length == 1 && guarded.content.include?("curious") && !guarded.content.include?("air feels") && !guarded.content.include?("system is settling"))

class CatalogGateFixture
  Result = Struct.new(:executed, :ok, :stdout, :status, :blocked_by, :message, keyword_init: true)

  def evaluate(_message, execute:, record_history:)
    payload = {
      "skills" => [
        { "id" => "system.status", "description" => "Report Soul runtime status." },
        { "id" => "web.research", "description" => "Perform bounded public web research." }
      ]
    }
    Result.new(executed: execute, ok: record_history, stdout: JSON.generate(payload), status: "complete", blocked_by: [], message: "")
  end
end

catalog_responder = SoulCore::ChatResponder.new(root: Dir.pwd)
catalog_responder.instance_variable_set(:@gate, CatalogGateFixture.new)
catalog_response = catalog_responder.respond("Well, take a look at what skills you have. Is there a suitable skill for reviewing the environment?")
check.call("skill catalog renders real inventory and identifies the bounded environment capability", catalog_response.include?("`host.system_status`") && catalog_response.include?("`web.research`") && !catalog_response.include?("conversational synthesis is unavailable"))

class ArtifactDraftClient
  attr_reader :request

  def chat(provider:, request:, timeout_seconds:)
    @request = request
    SoulCore::ConversationProviderContract::ResponseEnvelope.new(
      request_id: request.request_id,
      provider_id: provider.id,
      model: provider.model,
      content: "# Grounded report\n\nFixture claim [S1].",
      finish_reason: "stop",
      latency_ms: 1.0
    )
  end
end

class ReflectionDraftClient
  def initialize(content)
    @content = content
  end

  def chat(provider:, request:, timeout_seconds:)
    SoulCore::ConversationProviderContract::ResponseEnvelope.new(
      request_id: request.request_id, provider_id: provider.id, model: provider.model,
      content: @content, finish_reason: "stop", latency_ms: 1.0
    )
  end
end

reflection_provider = SoulCore::ConversationProviderContract::ProviderDefinition.new(
  id: "local.reflection", label: "Reflection fixture", transport: "openai_compatible", endpoint: "http://127.0.0.1:1/v1", model: "fixture-model",
  privacy_class: "local_only", capabilities: %w[chat structured_output reasoning_control], configured: true
)
reflection_draft = JSON.generate(
  "observations" => ["The retrieved source was used during troubleshooting."],
  "candidate_lessons" => ["Retain exact error evidence before proposing a repair."],
  "candidate_memory_updates" => [{ "layer" => "semantic", "content" => "Verified repairs should retain their source and error provenance.", "confidence" => 0.8 }],
  "warnings" => ["Human review remains required."]
)
Dir.mktmpdir("soul-research-reflection") do |root|
  service_under_test = SoulCore::ConversationResearchReflectionService.new(root: root, provider_client: ReflectionDraftClient.new(reflection_draft), clock: clock)
  outcome = service_under_test.create(
    chat_id: "chat_fixture",
    messages: [{ "role" => "user", "content" => "Research and repair it." }, { "role" => "assistant", "content" => "The verified repair worked." }],
    evidence_records: [{ "evidence_id" => "ev_fixture", "evidence_profile" => "web_research", "status" => "ok", "claims" => ["[S1] Fixture"], "collected" => { "sources" => [] } }],
    provider: reflection_provider
  )
  candidate_path = File.join(root, outcome.dig("data", "json_path").to_s)
  candidate = File.exist?(candidate_path) ? JSON.parse(File.read(candidate_path)) : {}
  check.call("reflection creates only a private pending candidate", outcome["lifecycle_state"] == "blocked_for_human_review" && outcome["mutation"] == "reflection_candidate_created" && candidate["status"] == "pending_review" && candidate["promote_automatically"] == false && candidate.dig("verification_summary", "evidence_ids") == ["ev_fixture"] && (File.stat(candidate_path).mode & 0o777) == 0o600)
end

Dir.mktmpdir("soul-invalid-reflection") do |root|
  service_under_test = SoulCore::ConversationResearchReflectionService.new(root: root, provider_client: ReflectionDraftClient.new("```json\n#{reflection_draft}\n```"), clock: clock)
  outcome = service_under_test.create(chat_id: "chat_fixture", messages: [], evidence_records: [{ "evidence_id" => "ev_fixture", "evidence_profile" => "web_research" }], provider: reflection_provider)
  check.call("Markdown-wrapped reflection JSON fails closed", outcome["lifecycle_state"] == "failed" && Dir.glob(File.join(root, "Soul/reflection/pending/*.json")).empty?)
end

Dir.mktmpdir("soul-reflection-symlink") do |root|
  outside = Dir.mktmpdir("soul-reflection-outside")
  FileUtils.mkdir_p(File.join(root, "Soul/reflection"))
  File.symlink(outside, File.join(root, "Soul/reflection/pending"))
  service_under_test = SoulCore::ConversationResearchReflectionService.new(root: root, provider_client: ReflectionDraftClient.new(reflection_draft), clock: clock)
  outcome = service_under_test.create(chat_id: "chat_fixture", messages: [], evidence_records: [{ "evidence_id" => "ev_fixture", "evidence_profile" => "web_research" }], provider: reflection_provider)
  check.call("reflection candidate path cannot escape through a symlink", outcome["lifecycle_state"] == "failed" && Dir.children(outside).empty?)
  FileUtils.remove_entry_secure(outside)
end

Dir.mktmpdir("soul-grounded-artifact") do |root|
  FileUtils.mkdir_p(File.join(root, "artifacts"))
  client = ArtifactDraftClient.new
  provider = SoulCore::ConversationProviderContract::ProviderDefinition.new(
    id: "local.fixture", label: "Fixture", transport: "openai_compatible", endpoint: "http://127.0.0.1:1/v1", model: "fixture-model",
    privacy_class: "local_only", capabilities: %w[chat], configured: true
  )
  service_under_test = SoulCore::ConversationArtifactCreationService.new(root: root, env: {}, provider_client: client)
  grounding = [{ "evidence_id" => "ev_fixture", "tool_id" => "web.research", "evidence_profile" => "web_research", "claims" => ["[S1] Fixture claim"], "collected" => { "sources" => [{ "source_id" => "S1", "url" => "https://example.com/research" }] } }]
  preview = service_under_test.preview(chat_id: "chat_fixture", message: "Create a project report at artifacts/research.md", provider: provider, grounding: grounding)
  prompt = client.request&.messages&.map { |message| message["content"] }.to_a.join("\n")
  check.call("artifact preview is bound to research evidence digest and IDs", preview["lifecycle_state"] == "awaiting_input" && preview["grounding_evidence_ids"] == ["ev_fixture"] && preview["grounding_digest"]&.length == 64 && prompt.include?("ev_fixture") && prompt.include?("preserve [S#] citations"))
  check.call("artifact evidence uses one leading system message for Ministral compatibility", client.request&.messages&.map { |message| message["role"] } == %w[system user])
end

class RuntimeWebFixture
  def initialize(configured:, lookup:, research: nil)
    @configured = configured
    @lookup = lookup
    @research = research
  end

  def configured? = @configured
  def lookup(_query) = @lookup
  def research(queries:, source_limit:) = @research
end

class RuntimeRegistryFixture
  def initialize(provider)
    @provider = provider
  end

  def find(id) = id == @provider.id ? @provider : nil
  def configured = [@provider]
end


class CountingProviderClient
  attr_reader :calls

  def initialize
    @calls = 0
  end

  def chat(**)
    @calls += 1
    raise "provider must not be called when research is unavailable"
  end
end

class ArtifactHandoffFixture
  attr_reader :grounding

  def preview(chat_id:, message:, provider:, grounding: nil)
    @grounding = grounding
    { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => "provide one project-relative target such as artifacts/status.md", "file_created" => false, "registry_mutated" => false }
  end
end

Dir.mktmpdir("soul-web-runtime") do |root|
  store = SoulCore::ChatStore.new(root: root)
  chat = store.create_chat
  no_answer = { "ok" => true, "lifecycle_state" => "complete", "mutation" => "none", "data" => { "query" => "fixture", "provider" => "duckduckgo_instant_answer", "found" => false, "retrieved_at" => clock.call.iso8601 } }
  runtime = SoulCore::ConversationRuntime.new(root: root, store: store, env: {}, web_research_service: RuntimeWebFixture.new(configured: false, lookup: no_answer))
  result = runtime.respond(chat_id: chat.fetch("id"), message: "Tell me about Unknown Fixture")
  check.call("lookup miss without SearXNG does not hallucinate research", result.mode == "web_lookup_no_answer" && result.content.include?("did not fill that gap from model memory"))

  research_packet = {
    "ok" => true, "lifecycle_state" => "complete", "mutation" => "none",
    "data" => {
      "research_id" => "res_fixture", "queries" => ["Tell me about Unknown Fixture"], "provider" => "searxng", "usable_source_count" => 1,
      "retrieved_bytes" => 20, "collected_at" => clock.call.iso8601,
      "sources" => [{ "source_id" => "S1", "title" => "Fixture", "url" => "https://example.com/research", "search_snippet" => "Public snippet", "status" => "ok", "retrieved_at" => clock.call.iso8601, "media_type" => "text/html", "bytes" => 20, "content_digest" => "a" * 64, "text" => "Evidence" }]
    }
  }
  second_chat = store.create_chat
  runtime = SoulCore::ConversationRuntime.new(root: root, store: store, env: {}, web_research_service: RuntimeWebFixture.new(configured: true, lookup: no_answer, research: research_packet))
  result = runtime.respond(chat_id: second_chat.fetch("id"), message: "Tell me about Unknown Fixture")
  check.call("lookup miss escalates synchronously to configured research", result.mode == "web_research_evidence" && result.content.include?("[S1]") && result.content.include?("https://example.com/research"))

  handoff = ArtifactHandoffFixture.new
  third_chat = store.create_chat
  runtime = SoulCore::ConversationRuntime.new(root: root, store: store, env: {}, web_research_service: RuntimeWebFixture.new(configured: true, lookup: no_answer, research: research_packet), artifact_creation_service: handoff)
  result = runtime.respond(chat_id: third_chat.fetch("id"), message: "Research the fixture and create a report based on current sources")
  check.call("research deliverables enter the existing artifact approval path with evidence", result.content.include?("Research deliverable handoff") && result.content.include?("artifacts/status.md") && handoff.grounding&.first&.dig("evidence_profile") == "web_research")

  provider_client = CountingProviderClient.new
  blocked_research = { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "reason" => "web search provider is not configured", "data" => {}, "mutation" => "none" }
  fourth_chat = store.create_chat
  runtime = SoulCore::ConversationRuntime.new(
    root: root, store: store,
    env: { "SOUL_CONVERSATION_PROVIDER" => reflection_provider.id },
    registry: RuntimeRegistryFixture.new(reflection_provider), provider_client: provider_client,
    web_research_service: RuntimeWebFixture.new(configured: false, lookup: no_answer, research: blocked_research)
  )
  result = runtime.respond(chat_id: fourth_chat.fetch("id"), message: hello_soul_request)
  check.call("unconfigured Hello Soul acceptance fails honestly before model synthesis", result.mode == "web_research_blocked_for_human_review" && result.content.include?("did not substitute model memory") && provider_client.calls.zero?)

  evidence_envelope = runtime.send(
    :build_request,
    chat_id: fourth_chat.fetch("id"),
    provider: reflection_provider,
    context: { "messages" => [{ "role" => "system", "content" => "Identity" }, { "role" => "user", "content" => "Question" }] },
    orchestration: research_plan,
    evidence: [{ "evidence_id" => "ev_fixture", "evidence_profile" => "web_research", "claims" => ["[S1] Fixture"] }]
  )
  check.call("conversation evidence is merged into one leading system message for Ministral", evidence_envelope.messages.map { |message| message["role"] } == %w[system user] && evidence_envelope.messages.first["content"].include?("ev_fixture"))
end

class FixtureAuth
  def session(token)
    return nil unless token == "good"

    { "authenticated" => true, "password_change_required" => false }
  end
end

class FixtureFacade
  def call(request, progress: nil)
    progress&.call("state" => "received", "summary" => "Accepted.")
    progress&.call("state" => "complete", "summary" => "Complete.")
    { "ok" => true, "operation" => request["operation"] }
  end
end

app = SoulCore::DashboardHttpApplication.new(root: Dir.pwd, facade: FixtureFacade.new, bind_host: "127.0.0.1", port: 4567, csrf_token: "csrf", authentication: FixtureAuth.new)
base_headers = { "Host" => "127.0.0.1:4567", "Content-Type" => "application/json", "Origin" => "http://127.0.0.1:4567", "X-Soul-CSRF" => "csrf", "Cookie" => "soul_session=good" }
stream = app.call(method: "POST", target: "/api/v1/chat-stream", headers: base_headers, body: JSON.generate("operation" => "chats.send", "payload" => {}))
events = stream.body.map { |line| JSON.parse(line) }
check.call("authenticated stream emits ordered real progress and one result", stream.status == 200 && events.map { |event| event["type"] } == %w[progress progress result] && events.last.dig("envelope", "ok") == true)
unauthenticated = app.call(method: "POST", target: "/api/v1/chat-stream", headers: base_headers.except("Cookie"), body: JSON.generate("operation" => "chats.send"))
no_csrf = app.call(method: "POST", target: "/api/v1/chat-stream", headers: base_headers.except("X-Soul-CSRF"), body: JSON.generate("operation" => "chats.send"))
wrong_operation = app.call(method: "POST", target: "/api/v1/chat-stream", headers: base_headers, body: JSON.generate("operation" => "system.status"))
check.call("stream preserves authentication, CSRF, and operation boundaries", unauthenticated.status == 401 && no_csrf.status == 403 && wrong_operation.status == 422)

class DisconnectingClient
  def initialize(fail_after:)
    @fail_after = fail_after
    @writes = 0
  end

  def write(_value)
    @writes += 1
    raise Errno::EPIPE if @writes >= @fail_after
    true
  end
end

completed_after_disconnect = false
disconnect_stream = Enumerator.new do |output|
  output << "first\n"
  output << "second\n"
  completed_after_disconnect = true
end
server = SoulCore::DashboardServer.allocate
response = SoulCore::DashboardHttpApplication::Response.new(status: 200, headers: { "Connection" => "close" }, body: disconnect_stream)
server.send(:write_stream_response, DisconnectingClient.new(fail_after: 5), response)
check.call("client disconnect does not abandon the accepted foreground exchange", completed_after_disconnect)

js = File.read("assets/dashboard/dashboard.js")
css = File.read("assets/dashboard/dashboard.css")
html = File.read("assets/dashboard/index.html")
append_position = js.index("appendPendingExchange")
stream_position = js.index("await callSoulStream", append_position || 0)
check.call("browser appends the pending exchange before awaiting the stream", append_position && stream_position && append_position < stream_position)
check.call("composer remains draftable and busy Enter does not interrupt", js.include?("draft was not sent") && !js.include?("message-input\").disabled = busy"))
check.call("responsive UI remains free of timers and background transports", %w[setTimeout setInterval WebSocket EventSource].none? { |term| js.include?(term) })
check.call("Soul familiar is state-driven and reduced-motion aware", html.include?("soul-presence") && css.include?("data-state") && css.include?("prefers-reduced-motion"))
check.call("stale restart-bound CSRF tokens recover through one page reload", js.scan('envelope.error?.code === "csrf"').length == 2 && js.scan("window.location.reload()").length >= 4)
check.call("wide-screen conversation messages remain readable and left anchored", css.include?(".message { max-width:920px; margin:0 0 29px; }") && !css.include?(".message { max-width:820px; margin:0 auto 29px; }"))

if failures.empty?
  puts "Responsive chat, lookup, and web research verification complete."
else
  warn "Verification failed: #{failures.join(', ')}"
  exit 1
end
