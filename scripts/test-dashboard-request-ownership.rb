# frozen_string_literal: true
require "minitest/autorun"
require "stringio"
require_relative "../lib/soul_core/dashboard_server"

class DashboardRequestOwnershipTest < Minitest::Test
  # Defer both workers until accept has advanced. This deterministically exposes
  # capture of mutable accept-loop locals without relying on scheduler timing.
  def test_each_delayed_worker_keeps_its_socket_and_start_gate
    clients = [Object.new, Object.new]
    listener = Object.new
    pending = clients.dup
    listener.define_singleton_method(:accept) { pending.shift }
    listener.define_singleton_method(:closed?) { false }
    listener.define_singleton_method(:close) {}
    jobs = []
    seen = []
    released = []
    server = SoulCore::DashboardServer.new(host: "127.0.0.1", port: 0, application: nil, max_requests: 2, output: StringIO.new)
    server.define_singleton_method(:install_signal_handlers) {}
    server.define_singleton_method(:restore_signal_handlers) {}
    server.define_singleton_method(:handle) { |client| seen << client }
    server.define_singleton_method(:release_request) { |client| released << client }
    server.define_singleton_method(:close_and_join_requests) do |**|
      Timeout.timeout(1) { jobs.each(&:call) }
    end
    spawn = ->(*args, &block) { jobs << -> { block.call(*args) }; Object.new }
    original_listener = TCPServer.method(:new)
    original_thread = Thread.method(:new)
    Timeout.timeout(1) { true }
    TCPServer.define_singleton_method(:new) { |*| listener }
    Thread.define_singleton_method(:new, &spawn)
    assert_equal "complete", server.run
    assert_equal clients, seen
    assert_equal clients, released
  ensure
    TCPServer.define_singleton_method(:new, original_listener) if original_listener
    Thread.define_singleton_method(:new, original_thread) if original_thread
  end
end
