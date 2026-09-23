#!/usr/bin/env ruby
require "tmpdir"
require_relative "../lib/soul_core/conversation_runtime"
require_relative "../lib/soul_core/conversation_context_builder"
require_relative "../lib/soul_core/chat_store"

Dir.mktmpdir("soul-safeguard-guidance-") do |root|
  runtime = SoulCore::ConversationRuntime.new(root: root, env: {}, store: SoulCore::ChatStore.new(root: root))
  provider = SoulCore::ConversationProviderContract::ProviderDefinition.new(
    id: "local.fixture", label: "fixture", transport: "openai_compatible",
    endpoint: "http://127.0.0.1:1/v1", model: "fixture", privacy_class: "local_only",
    capabilities: ["chat"], configured: true)
  context = {"messages" => [{"role" => "system", "content" => SoulCore::ConversationContextBuilder::SYSTEM_PROMPT}]}
  before = Marshal.dump(context)
  decision = Struct.new(:kind).new("direct_model")
  %w[voice_presence dashboard].each do |interface|
    request = runtime.send(:build_request, chat_id: "fixture", provider: provider,
      context: context, orchestration: decision, interface: interface,
      message: "What happens if the original path already exists?")
    prompt = request.messages.first.fetch("content")
    raise "missing prohibition guidance" unless prompt.include?("user confirmation does not waive a prohibition")
    raise "missing correction guidance" unless prompt.include?("explicit correction supersedes")
    raise "voice guidance leaked or missing" unless prompt.include?("one to three short sentences") == (interface == "voice_presence")
    raise "context mutated" unless Marshal.dump(context) == before
  end
end
puts "PASS shared safeguard/correction instructions, voice-only brevity, and immutable request context"
