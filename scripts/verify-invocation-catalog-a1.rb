#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/chat_responder"
require_relative "../lib/soul_core/conversation_orchestrator"
require_relative "../lib/soul_core/invocation_catalog_service"

ROOT = File.expand_path("..", __dir__)
checks = []

def check(checks, label, condition)
  raise label unless condition
  checks << label
end

service = SoulCore::InvocationCatalogService.new(root: ROOT)
catalog = service.list
check(checks, "catalog is bounded and read-only", catalog["count"].between?(10, 100) && catalog["read_only"] == true && catalog["mutation"] == "none")
check(checks, "examples explicitly carry no authority", catalog["examples_are_authority"] == false)
check(checks, "human-facing fields are complete", catalog["records"].all? { |record| %w[id label category summary status required_inputs optional_inputs core approval output boundary examples].all? { |key| record.key?(key) } })
check(checks, "production skill references resolve", catalog["records"].all? { |record| record["status"] == "available" && Array(record["unavailable_skill_ids"]).empty? })

cpu_commands = service.list(category: "Commands")["records"]
cpu_requests = service.list(category: "Supported requests")["records"]
check(checks, "CPU slash commands and supported prose have distinct categories", cpu_commands.map { |row| row["id"] }.sort == %w[cpu-calculation-command cpu-task-commands] && cpu_requests.map { |row| row["id"] }.sort == %w[cpu-approved-memory cpu-assistance-requests cpu-calculation-requests cpu-creative-execution cpu-creative-preview cpu-file-reference-requests cpu-fleet-status cpu-guide-search cpu-operational-guide cpu-queue-requests cpu-security-status cpu-weather-requests cpu-web-reference-requests])
check(checks, "CPU guide entries reference gateways rather than skills", (cpu_commands + cpu_requests).all? { |row| row["skill_ids"].empty? && row["handler_id"].start_with?("cpu_member_") })
check(checks, "new categories route through the read-only catalog", service.match?("List Commands invocations") && service.match?("Show Supported requests invocations"))
check(checks, "CPU guide preserves confirmation and admission boundaries", cpu_requests.find { |row| row["id"] == "cpu-assistance-requests" }["approval"].include?("immediately after") && cpu_requests.find { |row| row["id"] == "cpu-queue-requests" }["boundary"].include?("does not reserve compute"))
check(checks, "conversational detail renders all typed task command examples", service.respond("How can I invoke /task commands?").include?("/task run") && service.respond("How can I invoke /task commands?").include?("/task preview"))

creative = service.list(category: "Creative")
check(checks, "category filter is exact and bounded", creative["count"].positive? && creative["records"].all? { |record| record["category"] == "Creative" })
music = service.list(query: "ACE-Step")
check(checks, "text filter searches operational details", music["records"].map { |record| record["id"] } == ["music-production"])

overview = service.respond("Show the invocation catalog")
detail = service.respond("How can I invoke music production?")
check(checks, "overview warns that inspection is inert", overview.include?("does not run it or authorize") && overview.include?("Mutation: none"))
check(checks, "detail explains inputs Core approval result and boundary", %w[Required Optional Core Approval Result Boundary].all? { |word| detail.include?(word) } && detail.include?("Example wording"))

responder = SoulCore::ChatResponder.new(root: ROOT)
chat = responder.respond("List Creative invocations.")
check(checks, "Chat returns the curated catalog rather than the raw skill list", chat.include?("Creative invocations") && chat.include?("Music production") && !chat.include?("Soul/skills/"))

orchestrator = SoulCore::ConversationOrchestrator.new
decision = orchestrator.plan(message: "Show the invocation catalog", provider_available: true)
discussion = orchestrator.plan(message: "I have been thinking about music production.", provider_available: true)
check(checks, "explicit catalog request routes deterministically", decision.kind == "deterministic_passthrough" && decision.flags["invocation_catalog"] == true && decision.requires_model == false)
check(checks, "ordinary topical discussion does not invoke the catalog", discussion.flags["invocation_catalog"] != true)

facade = SoulCore::ApplicationFacade.new(root: ROOT)
envelope = facade.call({
  "schema_version" => "soul.application.v1",
  "request_id" => "invocation-catalog-a1-test",
  "operation" => "invocations.list",
  "parameters" => { "category" => "Runtime" },
  "context" => { "interface" => "dashboard_test" }
})
check(checks, "application operation is complete and non-mutating", envelope["lifecycle_state"] == "complete" && envelope.dig("meta", "mutation") == "none" && envelope.dig("data", "records", 0, "id") == "core-control")

html = File.read(File.join(ROOT, "assets/dashboard/index.html"))
javascript = File.read(File.join(ROOT, "assets/dashboard/dashboard.js"))
check(checks, "Dashboard exposes a read-only invocation dialog", html.include?('id="invocation-catalog"') && html.include?("Examples are inert documentation"))
check(checks, "Dashboard loads only on explicit open and provides no execute control", javascript.include?('callSoul("invocations.list")') && javascript.include?("openInvocationCatalog") && !html.match?(/id="execute-invocation"/))
check(checks, "Dashboard rendering uses DOM text rather than catalog HTML injection", javascript.include?("example.textContent") && !javascript.match?(/invocation.*innerHTML/i))

puts "Invocation Catalog A1 verification:"
checks.each { |label| puts "PASS: #{label}" }
puts "#{checks.length} checks passed."
