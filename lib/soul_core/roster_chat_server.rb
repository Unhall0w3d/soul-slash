# frozen_string_literal: true
require_relative "dashboard_server"

module SoulCore
  # Separate transport: do not change cancellation semantics of other dashboards.
  # Models are stopped by their owner, never by a socket thread killing a PID.
  class RosterChatServer < DashboardServer
    private

    def handle(client)
      request = Timeout.timeout(READ_TIMEOUT) { read_request(client) }
      cancel = -> { @stopping || disconnected?(client) }
      response = @application.call(**request, cancel: cancel)
      write_response(client, response) unless cancel.call
    rescue Timeout::Error
      write_plain_error(client, 408, "Request Timeout")
    rescue PayloadTooLarge
      write_plain_error(client, 413, "Payload Too Large")
    rescue ClientDisconnected, IOError, SystemCallError
      nil
    rescue StandardError
      write_plain_error(client, 400, "Bad Request")
    ensure
      client.close unless client.closed?
    end

    def disconnected?(client)
      return true if client.closed?
      value = client.recv_nonblock(1, Socket::MSG_PEEK, exception: false)
      # No HTTP pipelining is supported; unexpected trailing bytes cancel too.
      value != :wait_readable
    rescue IOError, SystemCallError
      true
    end
  end
end
