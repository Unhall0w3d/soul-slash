# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require "timeout"
require_relative "../lib/soul_core/application_chat_service"
require_relative "../lib/soul_core/chat_store"

class ApplicationChatCancellationTest < Minitest::Test
  Result = Struct.new(:content, :mode, :provider_id, :fallback_reason, :metadata, keyword_init: true)
  class Runtime
    attr_reader :entered, :release, :calls
    def initialize(confirm: true)
      @entered, @release, @calls, @confirm = Queue.new, Queue.new, 0, confirm
    end
    def supports_chat_cancellation? = true
    def respond(cancel:, **)
      @calls += 1
      @entered << true
      @release.pop
      raise SoulCore::ChatCancellation::Confirmed if cancel.call && @confirm
      Result.new(content: "answer", mode: "fixture", metadata: {})
    end
  end

  def setup
    @root = Dir.mktmpdir
    @store = SoulCore::ChatStore.new(root: @root)
    @chat = @store.create_chat.fetch("id")
    @runtime = Runtime.new
    build
  end
  def build
    @service = SoulCore::ApplicationChatService.new(root: @root, store: @store, runtime: @runtime)
  end
  def teardown
    @runtime.release << true if @thread&.alive?
    @thread&.join(2)
    FileUtils.remove_entry(@root)
  end
  def start
    @thread = Thread.new { send_request }
    Timeout.timeout(2) { @runtime.entered.pop }
  end
  def send_request
    @service.send(chat_id: @chat, message: "hello", request_id: "request-0001")
  end
  def stop(chat = @chat)
    @service.cancel(chat_id: chat, target_request_id: "request-0001")
  end
  def finish
    @runtime.release << true
    Timeout.timeout(2) { @thread.value }
  end

  def test_exact_target_and_confirmed_cleanup
    start
    refute stop("chat_other").dig("data", "cancellation_requested")
    response = stop
    assert response.dig("data", "cancellation_requested")
    refute response.dig("data", "generation_stopped")
    assert_equal "canceled", finish.fetch("lifecycle_state")
    assert_equal ["user"], @store.messages(@chat).map { |m| m["role"] }
    refute stop.dig("data", "cancellation_requested")
    assert_equal "blocked_for_human_review", send_request.fetch("lifecycle_state")
    assert_equal 1, @runtime.calls
  end

  def test_duplicate_inflight_does_not_generate_again_or_poison_original
    start
    assert_equal "blocked_for_human_review", send_request.fetch("lifecycle_state")
    assert_equal "complete", finish.fetch("lifecycle_state")
    assert send_request.fetch("idempotent_replay")
    assert_equal 1, @runtime.calls
    assert_equal 2, @store.messages(@chat).length
  end

  def test_normal_return_after_stop_does_not_fabricate_cancellation
    @runtime = Runtime.new(confirm: false)
    build
    start
    stop
    assert_equal "blocked_for_human_review", finish.fetch("lifecycle_state")
    assert_equal ["user"], @store.messages(@chat).map { |m| m["role"] }
  end

  def test_sealed_token_cannot_cancel_completed_answer
    token = SoulCore::ChatCancellation::Token.new
    refute token.seal
    refute token.request
    refute token.call
  end

  def test_unsupported_runtime_never_claims_cancellation
    @runtime.define_singleton_method(:supports_chat_cancellation?) { false }
    @runtime.define_singleton_method(:respond) do |**|
      @calls += 1
      @entered << true
      @release.pop
      Result.new(content: "legacy answer", mode: "fixture", metadata: {})
    end
    start
    refute stop.dig("data", "cancellation_requested")
    assert_equal "complete", finish.fetch("lifecycle_state")
    assert_equal "failed", @service.cancel(chat_id: @chat, target_request_id: "bad").fetch("lifecycle_state")
  end

  def test_invalid_duplicate_cannot_fail_original_receipt
    start
    assert_equal "failed", @service.send(chat_id: "invalid", message: "hello", request_id: "request-0001").fetch("lifecycle_state")
    assert_equal "complete", finish.fetch("lifecycle_state")
    assert send_request.fetch("idempotent_replay")
  end

  def test_reopened_service_refuses_incomplete_reservation
    start
    other = SoulCore::ApplicationChatService.new(root: @root, store: @store, runtime: @runtime)
    result = other.send(chat_id: @chat, message: "hello", request_id: "request-0001")
    assert_equal "blocked_for_human_review", result.fetch("lifecycle_state")
    assert_equal 1, @runtime.calls
    assert_equal "complete", finish.fetch("lifecycle_state")
  end

  def test_confirmation_without_stop_is_not_a_canceled_success
    @runtime.define_singleton_method(:respond) { |**| raise SoulCore::ChatCancellation::Confirmed }
    assert_equal "blocked_for_human_review", send_request.fetch("lifecycle_state")
    assert_equal ["user"], @store.messages(@chat).map { |m| m["role"] }
  end
end
