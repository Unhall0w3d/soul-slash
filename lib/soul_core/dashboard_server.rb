# frozen_string_literal: true

require "ipaddr"
require "socket"
require "timeout"

module SoulCore
  class DashboardServer
    REQUEST_LINE_LIMIT = 2 * 1024
    HEADER_BYTES_LIMIT = 16 * 1024
    HEADER_COUNT_LIMIT = 64
    BODY_LIMIT = 128 * 1024
    READ_TIMEOUT = 5

    STATUS_TEXT = {
      200 => "OK", 400 => "Bad Request", 401 => "Unauthorized", 403 => "Forbidden", 404 => "Not Found",
      405 => "Method Not Allowed", 408 => "Request Timeout", 413 => "Payload Too Large",
      415 => "Unsupported Media Type", 422 => "Unprocessable Content", 429 => "Too Many Requests",
      500 => "Internal Server Error"
    }.freeze

    def initialize(host:, port:, application:, max_requests: nil, output: $stdout)
      raise ArgumentError, "dashboard bind host must be loopback" unless self.class.loopback?(host)
      raise ArgumentError, "max requests must be positive" if max_requests && (!max_requests.is_a?(Integer) || max_requests <= 0)

      @host = host
      @port = Integer(port)
      @application = application
      @max_requests = max_requests
      @output = output
      @stopping = false
    end

    def run
      listener = TCPServer.new(@host, @port)
      @listener = listener
      install_signal_handlers
      @output.puts "Soul dashboard: http://#{display_host}:#{@port}"
      @output.puts "Foreground loopback session. Press Ctrl+C to stop."
      handled = 0
      until @stopping || (@max_requests && handled >= @max_requests)
        begin
          client = listener.accept
          handle(client)
          handled += 1
        rescue Errno::EINTR, IOError, Errno::EBADF
          break if @stopping
          raise
        end
      end
      @stopping ? "canceled" : "complete"
    rescue Interrupt, SignalException
      @stopping = true
      "canceled"
    ensure
      listener&.close unless listener&.closed?
      restore_signal_handlers
    end

    def stop
      @stopping = true
      @listener&.close unless @listener&.closed?
    rescue IOError
      nil
    end

    def self.loopback?(host)
      return true if host == "localhost"

      IPAddr.new(host).loopback?
    rescue IPAddr::InvalidAddressError
      false
    end

    private

    def install_signal_handlers
      @previous_handlers = {}
      %w[INT TERM].each { |signal| @previous_handlers[signal] = Signal.trap(signal) { raise Interrupt } }
    end

    def restore_signal_handlers
      return unless @previous_handlers

      @previous_handlers.each { |signal, handler| Signal.trap(signal, handler) }
    end

    def handle(client)
      request = Timeout.timeout(READ_TIMEOUT) { read_request(client) }
      response = @application.call(**request)
      write_response(client, response)
    rescue Timeout::Error
      write_plain_error(client, 408, "Request Timeout")
    rescue PayloadTooLarge
      write_plain_error(client, 413, "Payload Too Large")
    rescue StandardError
      write_plain_error(client, 400, "Bad Request")
    ensure
      client.close unless client.closed?
    end

    class PayloadTooLarge < StandardError; end

    def read_request(client)
      line = bounded_line(client, REQUEST_LINE_LIMIT)
      method, target, version = line.to_s.strip.split(" ", 3)
      raise ArgumentError, "invalid request line" unless method && target && version == "HTTP/1.1"

      headers = {}
      header_bytes = 0
      loop do
        raw = bounded_line(client, HEADER_BYTES_LIMIT)
        header_bytes += raw.bytesize
        raise PayloadTooLarge if header_bytes > HEADER_BYTES_LIMIT
        break if raw == "\r\n"

        key, value = raw.split(":", 2)
        raise ArgumentError, "invalid header" unless key && value && key.match?(/\A[A-Za-z0-9-]+\z/)
        raise PayloadTooLarge if headers.length >= HEADER_COUNT_LIMIT
        normalized = key.downcase
        raise ArgumentError, "duplicate header" if headers.key?(normalized)
        headers[normalized] = value.strip
      end

      length = headers["content-length"] ? Integer(headers["content-length"], 10) : 0
      raise ArgumentError, "negative content length" if length.negative?
      raise PayloadTooLarge if length > BODY_LIMIT
      body = read_exact(client, length)
      { method: method, target: target, headers: headers, body: body }
    end

    def bounded_line(client, limit)
      line = client.gets(limit + 1)
      raise ArgumentError, "unexpected end of request" unless line
      raise PayloadTooLarge if line.bytesize > limit || !line.end_with?("\r\n")

      line
    end

    def read_exact(client, length)
      bytes = +""
      while bytes.bytesize < length
        chunk = client.read(length - bytes.bytesize)
        raise ArgumentError, "incomplete body" unless chunk
        bytes << chunk
      end
      bytes
    end

    def write_response(client, response)
      body = response.body.to_s
      headers = response.headers.merge("Content-Length" => body.bytesize.to_s)
      client.write("HTTP/1.1 #{response.status} #{STATUS_TEXT.fetch(response.status, 'Response')}\r\n")
      headers.each { |key, value| client.write("#{key}: #{value}\r\n") }
      client.write("\r\n")
      client.write(body)
    end

    def write_plain_error(client, status, message)
      body = "#{message}\n"
      client.write("HTTP/1.1 #{status} #{STATUS_TEXT.fetch(status)}\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
    rescue IOError, Errno::EPIPE
      nil
    end

    def display_host
      @host.include?(":") ? "[#{@host}]" : @host
    end
  end
end
