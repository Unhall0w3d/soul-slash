# frozen_string_literal: true
require "minitest/autorun"
require "timeout"
require_relative "../lib/soul_core/roster_service_backend"
require_relative "../lib/soul_core/roster_service_application"

class RosterRequestControlTest < Minitest::Test
  def setup
    @control = SoulCore::RosterRequestControl.new
    @identity = { conversation_id: "chat_one", request_id: "request_one" }
  end

  def run_failed(clean: true)
    entered, release = Queue.new, Queue.new
    thread = Thread.new do
      @control.run(**@identity, cancel: -> { false }, released: -> { clean }) do |signal|
        entered << signal
        release.pop
        raise RuntimeError, "synthetic failure"
      end
    rescue RuntimeError
      :failed
    end
    signal = Timeout.timeout(2) { entered.pop }
    yield signal
    release << true
    Timeout.timeout(2) { thread.value }
  ensure
    release << true if thread&.alive?
    thread&.join(2)
  end

  def test_exact_request_then_release_confirmation
    run_failed do |signal|
      assert_equal "unknown", @control.cancel(conversation_id: "other", request_id: "request_one")["state"]
      refute signal.call
      response = @control.cancel(**@identity)
      assert_equal "cancel_requested", response["state"]
      refute response["cleanup_confirmed"]
      assert signal.call
    end
    assert @control.status(**@identity)["cleanup_confirmed"]
  end

  def test_uncertain_cleanup_never_confirmed
    run_failed(clean: false) { @control.cancel(**@identity) }
    assert_equal "failed_unconfirmed", @control.status(**@identity)["state"]
    refute @control.status(**@identity)["cleanup_confirmed"]
  end

  def test_ordinary_failure_not_called_canceled
    run_failed { }
    assert_equal "failed_unconfirmed", @control.status(**@identity)["state"]
  end

  def test_success_wins_before_late_stop_and_restart_is_unknown
    @control.run(**@identity, cancel: -> { false }, released: -> { false }) { :ok }
    assert_equal "completed", @control.cancel(**@identity)["state"]
    assert_equal "unknown", SoulCore::RosterRequestControl.new.status(**@identity)["state"]
  end

  def test_terminal_cache_bounded
    65.times do |i|
      @control.run(conversation_id: "chat_one", request_id: "r#{i}", cancel: -> { false }, released: -> { false }) { :ok }
    end
    assert_equal "unknown", @control.status(conversation_id: "chat_one", request_id: "r0")["state"]
    assert_equal "completed", @control.status(conversation_id: "chat_one", request_id: "r64")["state"]
    assert_raises(ArgumentError) { @control.cancel(conversation_id: "../bad", request_id: "r1") }
  end

  def test_control_routes_require_auth_and_reject_origins_and_extra_fields
    backend = Object.new
    backend.define_singleton_method(:complete) { |**| raise "must not generate" }
    control = @control
    backend.define_singleton_method(:request_status) { |**id| control.status(**id) }
    backend.define_singleton_method(:cancel_request) { |**id| control.cancel(**id) }
    app = SoulCore::RosterServiceApplication.new(backend: backend, bearer_token: "a" * 64)
    args = {method: "POST", target: "/v1/soul/requests/cancel", body: JSON.generate(@identity), headers: {}}
    assert_equal 401, app.call(**args).status
    args[:headers] = {"Authorization" => "Bearer #{'a' * 64}"}
    assert_equal 200, app.call(**args).status
    assert_equal 403, app.call(**args.merge(headers: args[:headers].merge("Origin" => "http://localhost"))).status
    assert_equal 405, app.call(**args.merge(method: "GET")).status
    assert_equal 422, app.call(**args.merge(body: JSON.generate(@identity.merge(extra: true)))).status
    assert_equal 422, app.call(**args.merge(body: "x" * 1025)).status
    assert_equal 422, app.call(**args.merge(body: '{"conversation_id":"one","request_id":"one","request_id":"two"}')).status
  end
end
