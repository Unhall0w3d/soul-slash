#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/application_chat_service"
require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/conversation_observation_store"

checks = 0
check = lambda do |label, condition|
  raise "FAIL: #{label}" unless condition
  checks += 1
end

Result = Struct.new(:content, :mode, :provider_id, :fallback_reason, :metadata, keyword_init: true) do
  def to_h
    {
      "content" => content,
      "mode" => mode,
      "provider_id" => provider_id,
      "fallback_reason" => fallback_reason,
      "metadata" => metadata
    }
  end
end

Runtime = Struct.new(:response, keyword_init: true) do
  def respond(chat_id:, message:, **_options)
    raise "missing chat" if chat_id.to_s.empty? || message.to_s.empty?
    response
  end
end

def observation_events(store)
  Dir.glob(File.join(store.path, "segment_*.jsonl")).sort.flat_map do |path|
    File.readlines(path, chomp: true).map { |line| JSON.parse(line) }
  end
end

FlakyObserver = Struct.new(:delegate, :attempts, keyword_init: true) do
  def capture_exchange(**arguments)
    self.attempts += 1
    raise IOError, "fixture failure" if attempts == 1

    delegate.capture_exchange(**arguments)
  end
end

Dir.mktmpdir("soul-observation-a11") do |root|
  chats = SoulCore::ChatStore.new(root: root)
  chat = chats.create_chat
  runtime = Runtime.new(response: Result.new(
    content: "Exact assistant reply.\nSecond line.", mode: "fixture", provider_id: "local-fixture",
    fallback_reason: nil, metadata: { "fixture" => true }
  ))
  observations = SoulCore::ConversationObservationStore.new(root: root, clock: -> { Time.utc(2026, 8, 24, 12, 0, 0) })
  service = SoulCore::ApplicationChatService.new(root: root, store: chats, runtime: runtime, observation_store: observations)
  request_id = "req:a11:0001"
  exchange = service.send(
    chat_id: chat.fetch("id"), message: "Exact user message — preserved.", request_id: request_id, interface: "dashboard"
  )
  check.call("successful exchange remains complete", exchange["ok"] && exchange["lifecycle_state"] == "complete")
  capture = exchange.fetch("observation_capture")
  check.call("exchange captures exactly two observations", capture["ok"] && capture["event_count"] == 2 && !capture["idempotent"])
  check.call("capture receipt is content-free", !JSON.generate(capture).include?("Exact user message") && capture["content_included"] == false)

  events = observation_events(observations)
  check.call("roles retain conversational order", events.map { |event| event["role"] } == %w[user assistant])
  check.call("exact content is retained locally", events.map { |event| event["content"] } == ["Exact user message — preserved.", "Exact assistant reply.\nSecond line."])
  check.call("source identities are retained", events.map { |event| event["message_id"] } == [exchange.dig("user_message", "id"), exchange.dig("assistant_message", "id")])
  check.call("events are chained", events.first["previous_event_sha256"].nil? && events.last["previous_event_sha256"] == events.first["event_sha256"])
  check.call("integrity summary is content-free", observations.integrity["ok"] && !JSON.generate(observations.integrity).include?("Exact assistant reply"))

  replay = service.send(
    chat_id: chat.fetch("id"), message: "Exact user message — preserved.", request_id: request_id, interface: "dashboard"
  )
  check.call("application replay does not duplicate observations", replay["idempotent_replay"] && replay.dig("observation_capture", "idempotent") && observation_events(observations).length == 2)

  altered = exchange.fetch("user_message").merge("content" => "conflicting content")
  conflict = observations.capture_exchange(
    user_message: altered,
    assistant_message: exchange.fetch("assistant_message"),
    request_id: request_id,
    interface: "dashboard"
  )
  check.call("message identity conflict fails closed", !conflict["ok"] && conflict["reason"].include?("conflicts"))

  segment = Dir.glob(File.join(observations.path, "segment_*.jsonl")).first
  original = File.binread(segment)
  File.binwrite(segment, original.sub("Exact assistant reply", "Alter assistant reply"))
  check.call("content tampering fails integrity", !observations.integrity["ok"])
  File.binwrite(segment, original.sub(/\n\z/, ""))
  check.call("partial final write fails integrity", !observations.integrity["ok"])
  File.binwrite(segment, original)
  check.call("restored ledger verifies", observations.integrity["ok"])
  FileUtils.rm_rf(File.join(observations.path, "index"))
  rebuilt = observations.rebuild_index
  check.call("derived index rebuild is content-free", rebuilt["ok"] && rebuilt["indexed_messages"] == 2 && !JSON.generate(rebuilt).include?("Exact user message"))
end

Dir.mktmpdir("soul-observation-a11-failure") do |root|
  chats = SoulCore::ChatStore.new(root: root)
  chat = chats.create_chat
  runtime = Runtime.new(response: Result.new(content: "Available reply", mode: "fixture", provider_id: nil, metadata: {}))
  retained = SoulCore::ConversationObservationStore.new(root: root)
  failed_observer = FlakyObserver.new(delegate: retained, attempts: 0)
  service = SoulCore::ApplicationChatService.new(root: root, store: chats, runtime: runtime, observation_store: failed_observer)
  exchange = service.send(chat_id: chat.fetch("id"), message: "Still answer me", request_id: "req:a11:failure", interface: "voice_presence")
  check.call("capture dependency failure does not erase chat completion", exchange["ok"] && exchange.dig("observation_capture", "ok") == false)
  check.call("completed chat messages remain readable", chats.messages(chat.fetch("id")).map { |message| message["content"] } == ["Still answer me", "Available reply"])
  check.call("capture failure receipt remains content-free", !JSON.generate(exchange.fetch("observation_capture")).include?("Still answer me"))
  replay = service.send(chat_id: chat.fetch("id"), message: "Still answer me", request_id: "req:a11:failure", interface: "voice_presence")
  check.call("exact application replay repairs missing capture", replay["idempotent_replay"] && replay.dig("observation_capture", "ok") && observation_events(retained).length == 2)
end

Dir.mktmpdir("soul-observation-a11-safety") do |root|
  outside = File.join(root, "outside")
  FileUtils.mkdir_p(outside)
  symlink = File.join(root, "observations")
  File.symlink(outside, symlink)
  begin
    SoulCore::ConversationObservationStore.new(root: root, path: symlink)
    raise "FAIL: symlinked observation ledger accepted"
  rescue ArgumentError
    checks += 1
  end
  begin
    SoulCore::ConversationObservationStore.new(root: root, path: File.join(root, "..", "escape.jsonl"))
    raise "FAIL: escaped observation ledger accepted"
  rescue ArgumentError
    checks += 1
  end
end


Dir.mktmpdir("soul-observation-a11-malformed") do |root|
  path = File.join(root, "observations")
  FileUtils.mkdir_p(File.join(path, "index"))
  File.write(File.join(path, "segment_000001.jsonl"), "secret-content-is-not-json\n")
  store = SoulCore::ConversationObservationStore.new(root: root, path: path)
  result = store.integrity
  check.call("malformed-ledger failure is content-free", !result["ok"] && !JSON.generate(result).include?("secret-content"))
end


Dir.mktmpdir("soul-observation-a11-segments") do |root|
  original_limit = SoulCore::ConversationObservationStore::SEGMENT_EVENTS
  SoulCore::ConversationObservationStore.send(:remove_const, :SEGMENT_EVENTS)
  SoulCore::ConversationObservationStore.const_set(:SEGMENT_EVENTS, 2)
  begin
    store = SoulCore::ConversationObservationStore.new(root: root, clock: -> { Time.utc(2026, 8, 24, 13, 0, 0) })
    message = lambda do |id, role, content|
      { "id" => id, "chat_id" => "chat:segments", "role" => role, "content" => content, "created_at" => "2026-08-24T13:00:00Z" }
    end
    first = store.capture_exchange(user_message: message.call("msg:u1", "user", "first"), assistant_message: message.call("msg:a1", "assistant", "reply one"), request_id: "req:one", interface: "dashboard")
    second = store.capture_exchange(user_message: message.call("msg:u2", "user", "second"), assistant_message: message.call("msg:a2", "assistant", "reply two"), request_id: "req:two", interface: "dashboard")
    check.call("bounded segments rotate without imposing a lifetime ledger ceiling", first["ok"] && second["ok"] && Dir.glob(File.join(store.path, "segment_*.jsonl")).length == 2)
    check.call("full-history verification crosses segment boundaries", store.integrity["ok"] && store.integrity["event_count"] == 4 && store.integrity["segment_count"] == 2)
    replay = store.capture_exchange(user_message: message.call("msg:u1", "user", "first"), assistant_message: message.call("msg:a1", "assistant", "reply one"), request_id: "req:one", interface: "dashboard")
    check.call("derived index provides cross-segment idempotency", replay["ok"] && replay["idempotent"])
    first_segment = File.join(store.path, "segment_000001.jsonl")
    File.chmod(0o000, first_segment)
    third = store.capture_exchange(user_message: message.call("msg:u3", "user", "third"), assistant_message: message.call("msg:a3", "assistant", "reply three"), request_id: "req:three", interface: "dashboard")
    check.call("normal capture does not rescan inactive history", third["ok"] && Dir.glob(File.join(store.path, "segment_*.jsonl")).length == 3)
    File.chmod(0o600, first_segment)
    check.call("explicit verification still covers complete retained history", store.integrity["ok"] && store.integrity["event_count"] == 6)
  ensure
    File.chmod(0o600, first_segment) if defined?(first_segment) && File.exist?(first_segment)
    SoulCore::ConversationObservationStore.send(:remove_const, :SEGMENT_EVENTS)
    SoulCore::ConversationObservationStore.const_set(:SEGMENT_EVENTS, original_limit)
  end
end

puts "MEMORY_CONVERSATION_OBSERVATION_CAPTURE_A11=PASS (#{checks} checks)"
