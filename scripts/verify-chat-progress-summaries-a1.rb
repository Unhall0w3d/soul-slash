#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/application_chat_service"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/application_request_receipt_store"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAILED'}"
  errors << label unless condition
end

puts "Chat progress summaries A1 verification:"

class ProgressChatStoreFixture
  attr_reader :records

  def initialize
    @records = []
  end

  def chat(chat_id)
    chat_id == "chat_alpha" ? {"id" => chat_id} : nil
  end

  def add_message(chat_id, role:, content:, metadata:)
    record = {"id" => "msg_#{@records.length + 1}", "chat_id" => chat_id, "role" => role, "content" => content, "metadata" => metadata}
    @records << record
    record
  end

  def message(chat_id, message_id)
    @records.find { |record| record["chat_id"] == chat_id && record["id"] == message_id }
  end
end

class ProgressRuntimeFixture
  Result = Struct.new(:content, :mode, :provider_id, :fallback_reason, :metadata, keyword_init: true) do
    def to_h = {content: content, mode: mode, provider_id: provider_id, fallback_reason: fallback_reason, metadata: metadata}
  end

  attr_reader :calls, :observed

  def initialize(receipts)
    @receipts = receipts
    @calls = 0
  end

  def respond(chat_id:, message:, progress: nil)
    @calls += 1
    progress&.call("state" => "planning", "summary" => "Selecting the bounded path for this request.")
    progress&.call("state" => "synthesizing", "summary" => "Composing a response through the selected local model.")
    @observed = @receipts.active(operation: "chats.send", identity: chat_id, limit: 1).first
    Result.new(content: "Acknowledged: #{message}", mode: "fixture", provider_id: "fixture", metadata: {})
  end
end

Dir.mktmpdir("soul-chat-progress") do |root|
  now = Time.utc(2026, 7, 27, 21, 0, 0)
  clock = -> { now }
  store = SoulCore::ApplicationRequestReceiptStore.new(root: root, clock: clock)
  store.reserve(request_id: "request:progress001", operation: "chats.send", identity: "chat_alpha", input_digest: "a" * 64)
  store.progress(request_id: "request:progress001", state: "received", summary: "Transmission received and written to local continuity.")
  now += 1
  store.progress(request_id: "request:progress001", state: "planning", summary: "Selecting the bounded path for this request.")

  reopened = SoulCore::ApplicationRequestReceiptStore.new(root: root, clock: clock)
  active = reopened.active(operation: "chats.send", identity: "chat_alpha", limit: 10)
  check.call("progress survives a new receipt-store instance",
             active.one? &&
             active.first["request_id"] == "request:progress001" &&
             active.first["progress_state"] == "planning" &&
             active.first["progress_summary"] == "Selecting the bounded path for this request.")
  check.call("active progress is bounded and excludes prompt or response payloads",
             active.first.keys.sort == %w[created_at identity operation progress_at progress_state progress_summary request_id status].sort &&
             JSON.generate(active).bytesize < 2_000)

  reopened.complete(request_id: "request:progress001", user_message_id: "msg_user", assistant_message_id: "msg_assistant")
  reopened.progress(request_id: "request:progress001", state: "researching", summary: "This must not reopen terminal work.")
  check.call("terminal receipts disappear and cannot be reopened",
             reopened.active(operation: "chats.send", identity: "chat_alpha", limit: 10).empty? &&
             reopened.find("request:progress001")["status"] == "complete")

  invalid_state = begin
    reopened.reserve(request_id: "request:progress002", operation: "chats.send", identity: "chat_beta", input_digest: "b" * 64)
    reopened.progress(request_id: "request:progress002", state: "../running", summary: "invalid")
    false
  rescue ArgumentError
    true
  end
  oversized = begin
    reopened.progress(request_id: "request:progress002", state: "planning", summary: "x" * 241)
    false
  rescue ArgumentError
    true
  end
  invalid_utf8 = begin
    reopened.progress(request_id: "request:progress002", state: "planning", summary: "\xFF".b)
    false
  rescue ArgumentError
    true
  end
  check.call("invalid progress state and summary text fail closed", invalid_state && oversized && invalid_utf8)

  now += SoulCore::ApplicationRequestReceiptStore::ACTIVE_TTL_SECONDS + 1
  check.call("stale incomplete receipts are not presented as active",
             reopened.active(operation: "chats.send", limit: 10).empty?)
end

Dir.mktmpdir("soul-chat-progress-service") do |root|
  receipts = SoulCore::ApplicationRequestReceiptStore.new(root: root)
  messages = ProgressChatStoreFixture.new
  runtime = ProgressRuntimeFixture.new(receipts)
  service = SoulCore::ApplicationChatService.new(root: root, store: messages, runtime: runtime, receipt_store: receipts)
  emitted = []
  result = service.send(
    chat_id: "chat_alpha",
    message: "hello",
    request_id: "request:service001",
    interface: "dashboard",
    progress: ->(event) { emitted << event }
  )
  replay = service.send(
    chat_id: "chat_alpha",
    message: "hello",
    request_id: "request:service001",
    interface: "dashboard"
  )
  check.call("Chat service persists real runtime progress before terminal completion",
             runtime.observed["progress_state"] == "synthesizing" &&
             runtime.observed["progress_summary"].include?("selected local model") &&
             emitted.map { |event| event["state"] } == %w[received planning synthesizing finalizing complete])
  check.call("terminal completion removes active progress and preserves idempotent replay",
             result["lifecycle_state"] == "complete" &&
             receipts.active(operation: "chats.send", identity: "chat_alpha", limit: 1).empty? &&
             replay["idempotent_replay"] == true &&
             runtime.calls == 1 &&
             messages.records.length == 2)
end

contract = SoulCore::ApplicationContract::OPERATIONS
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
brief = File.read(File.expand_path("../docs/soul/CHAT_PROGRESS_SUMMARIES_A1_BRIEF.md", __dir__))

check.call("typed application contract exposes read-only Chat progress",
           contract["chats.progress"] == %w[chat_id limit])
append_position = javascript.index("appendPendingExchange(message, chatRequestId)")
stream_position = javascript.index("await callSoulStream", append_position || 0)
check.call("submitted text renders before the streaming request starts",
           append_position && stream_position && append_position < stream_position)
check.call("Dashboard marks accepted text and reconstructs one working card",
           javascript.include?("markPendingMessageAccepted") &&
           javascript.include?('"chats.progress"') &&
           javascript.include?("renderChatProgress") &&
           javascript.include?("soul-working-message"))
check.call("navigation-safe completion is scoped to the originating conversation",
           javascript.include?("state.activeChat?.id === chatId"))
check.call("progress recovery remains event-driven without polling or push transports",
           !javascript.match?(/chatProgress.{0,500}(?:setInterval|setTimeout|WebSocket|EventSource|Worker)/m))
check.call("brief preserves the bounded foreground boundary",
           brief.include?("It must not\npoll") &&
           brief.include?("A terminal receipt can never return to an active state.") &&
           brief.include?("Model-generated progress prose."))

abort "Chat progress summaries A1 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Chat progress summaries A1 verification complete."
