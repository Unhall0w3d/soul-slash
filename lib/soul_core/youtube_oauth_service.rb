# frozen_string_literal: true

require "base64"
require "digest"
require "fileutils"
require "json"
require "securerandom"
require "socket"
require "time"
require "uri"
require_relative "bounded_command_runner"
require_relative "youtube_api_client"

module SoulCore
  class YouTubeOAuthService
    PROJECT_ID = "soul-slash-local-publisher"
    EXPECTED_CHANNEL_ID = "UCIY6AROma4bbum3jk2kfu-w"
    CONFIRMATION = "AUTHORIZE_YOUTUBE"
    SCOPES = [
      "https://www.googleapis.com/auth/youtube.readonly",
      "https://www.googleapis.com/auth/youtube.upload"
    ].freeze
    ALLOWED_SCOPES = (
      SCOPES + ["https://www.googleapis.com/auth/youtube.force-ssl"]
    ).freeze
    CALLBACK_TIMEOUT = 180
    MAX_CREDENTIAL_BYTES = 64 * 1024

    class CredentialError < StandardError; end

    def initialize(root: Dir.pwd, api: YouTubeApiClient.new, runner: BoundedCommandRunner.new, clock: -> { Time.now.utc }, random: SecureRandom, callback_timeout: CALLBACK_TIMEOUT, scopes: SCOPES, credential_name: "oauth.json", confirmation: CONFIRMATION, operation: "authorize_youtube")
      @root = File.expand_path(root)
      @api = api
      @runner = runner
      @clock = clock
      @random = random
      @callback_timeout = Float(callback_timeout)
      @scopes = Array(scopes).map(&:to_s).uniq.freeze
      @credential_name = credential_name.to_s
      @confirmation = confirmation.to_s
      @operation = operation.to_s
      raise ArgumentError, "OAuth scopes are required" if @scopes.empty? || @scopes.any?(&:empty?)
      raise ArgumentError, "OAuth scopes include an unapproved value" unless (@scopes - ALLOWED_SCOPES).empty?
      raise ArgumentError, "OAuth credential name is invalid" unless @credential_name.match?(/\A[a-z0-9][a-z0-9._-]*\.json\z/)
      raise ArgumentError, "OAuth confirmation is required" if @confirmation.empty?
      raise ArgumentError, "OAuth operation is invalid" unless @operation.match?(/\A[a-z0-9_]+\z/)
    end

    def preview(client_path:)
      client = read_client(client_path)
      scope = {
        "operation" => @operation,
        "project_id" => client.fetch("project_id"),
        "application_type" => "desktop",
        "expected_channel_id" => EXPECTED_CHANNEL_ID,
        "scopes" => @scopes,
        "credential_destination" => credential_path
      }
      outcome("blocked_for_human_review", true, "YouTube authorization requires exact approval and browser consent", data: {
        "confirmation_phrase" => @confirmation,
        "expected_digest" => digest(scope),
        "preview_scope" => scope
      })
    rescue CredentialError, Errno::ENOENT, Errno::EACCES => error
      outcome("awaiting_input", false, error.message)
    end

    def execute(client_path:, confirmation:, expected_digest:)
      return outcome("awaiting_input", false, "confirmation and expected_digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      client = read_client(client_path)
      scope = {
        "operation" => @operation,
        "project_id" => client.fetch("project_id"),
        "application_type" => "desktop",
        "expected_channel_id" => EXPECTED_CHANNEL_ID,
        "scopes" => @scopes,
        "credential_destination" => credential_path
      }
      return outcome("blocked_for_human_review", false, "YouTube authorization confirmation did not match") unless confirmation == @confirmation
      return outcome("blocked_for_human_review", false, "YouTube authorization scope changed; preview again") unless secure_compare(expected_digest, digest(scope))

      authorization = receive_authorization(client)
      token = @api.exchange_code(
        token_uri: client.fetch("token_uri"),
        client_id: client.fetch("client_id"),
        client_secret: client.fetch("client_secret"),
        code: authorization.fetch("code"),
        redirect_uri: authorization.fetch("redirect_uri"),
        code_verifier: authorization.fetch("code_verifier")
      )
      refresh_token = token["refresh_token"].to_s
      access_token = token["access_token"].to_s
      granted_scopes = token.fetch("scope", "").split(/\s+/)
      raise CredentialError, "Google did not return a refresh token; revoke the app grant and authorize again" if refresh_token.empty?
      raise CredentialError, "Google did not return an access token" if access_token.empty?
      raise CredentialError, "Google did not grant the required YouTube scopes" unless (@scopes - granted_scopes).empty?

      channel = @api.channel(access_token: access_token)
      raise CredentialError, "authorized channel does not match Soul Slash Synthesis" unless channel.fetch("id") == EXPECTED_CHANNEL_ID

      write_credentials(
        "schema_version" => "soul.youtube.oauth.v1",
        "project_id" => client.fetch("project_id"),
        "client_id" => client.fetch("client_id"),
        "client_secret" => client.fetch("client_secret"),
        "token_uri" => client.fetch("token_uri"),
        "refresh_token" => refresh_token,
        "scopes" => @scopes,
        "channel_id" => channel.fetch("id"),
        "channel_title" => channel.fetch("title"),
        "authorized_at" => @clock.call.iso8601
      )
      outcome("complete", true, "YouTube authorization stored locally for the expected channel", data: {
        "project_id" => client.fetch("project_id"),
        "channel_id" => channel.fetch("id"),
        "channel_title" => channel.fetch("title"),
        "credential_path" => credential_path,
        "scopes" => @scopes
      }, mutation: "youtube_oauth_authorized")
    rescue CredentialError, YouTubeApiClient::ApiError, Errno::ENOENT, Errno::EACCES, IOError, SystemCallError => error
      outcome("blocked_for_human_review", false, safe_message(error))
    end

    def access_context
      credential = read_stored_credentials
      token = @api.refresh_access_token(
        token_uri: credential.fetch("token_uri"),
        client_id: credential.fetch("client_id"),
        client_secret: credential.fetch("client_secret"),
        refresh_token: credential.fetch("refresh_token")
      )
      access_token = token["access_token"].to_s
      raise CredentialError, "Google did not return an access token" if access_token.empty?

      channel = @api.channel(access_token: access_token)
      unless channel.fetch("id") == EXPECTED_CHANNEL_ID && channel.fetch("id") == credential.fetch("channel_id")
        raise CredentialError, "authorized YouTube channel identity changed"
      end
      {
        "access_token" => access_token,
        "channel_id" => channel.fetch("id"),
        "channel_title" => channel.fetch("title"),
        "project_id" => credential.fetch("project_id")
      }
    end

    def status
      credential = read_stored_credentials
      outcome("complete", true, "YouTube OAuth is configured", data: {
        "configured" => true,
        "project_id" => credential.fetch("project_id"),
        "channel_id" => credential.fetch("channel_id"),
        "channel_title" => credential.fetch("channel_title"),
        "scopes" => credential.fetch("scopes"),
        "credential_path" => credential_path
      })
    rescue CredentialError, Errno::ENOENT, Errno::EACCES
      outcome("complete", true, "YouTube OAuth is not configured", data: {
        "configured" => false,
        "project_id" => PROJECT_ID,
        "expected_channel_id" => EXPECTED_CHANNEL_ID,
        "credential_path" => credential_path
      })
    end

    private

    def read_client(path)
      raise CredentialError, "OAuth client JSON is required" if path.to_s.empty?
      expanded = operator_path(path)
      raise CredentialError, "OAuth client JSON must be a regular non-symlink file" unless File.file?(expanded) && !File.symlink?(expanded)
      raise CredentialError, "OAuth client JSON permissions must be owner-only" unless (File.stat(expanded).mode & 0o077).zero?
      raise CredentialError, "OAuth client JSON exceeds size limit" unless File.size(expanded).between?(1, MAX_CREDENTIAL_BYTES)

      document = JSON.parse(File.binread(expanded, MAX_CREDENTIAL_BYTES))
      client = document["installed"]
      raise CredentialError, "OAuth client must have Desktop application type" unless client.is_a?(Hash)
      required = %w[client_id client_secret auth_uri token_uri project_id]
      raise CredentialError, "OAuth client JSON is incomplete" unless required.all? { |key| !client[key].to_s.empty? }
      raise CredentialError, "OAuth client belongs to an unexpected Google project" unless client["project_id"] == PROJECT_ID
      raise CredentialError, "OAuth endpoints must use Google HTTPS endpoints" unless google_https?(client["auth_uri"]) && google_https?(client["token_uri"])

      client
    rescue JSON::ParserError
      raise CredentialError, "OAuth client JSON is invalid"
    end

    def operator_path(path)
      value = path.to_s
      value = File.join(Dir.home, value.delete_prefix("~/")) if value.start_with?("~/")
      value = Dir.home if value == "~"
      File.expand_path(value)
    end

    def receive_authorization(client)
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      redirect_uri = "http://127.0.0.1:#{port}/oauth2/callback"
      state = @random.urlsafe_base64(32)
      verifier = @random.urlsafe_base64(64)
      challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
      query = URI.encode_www_form(
        "client_id" => client.fetch("client_id"),
        "redirect_uri" => redirect_uri,
        "response_type" => "code",
        "scope" => @scopes.join(" "),
        "access_type" => "offline",
        "prompt" => "consent",
        "state" => state,
        "code_challenge" => challenge,
        "code_challenge_method" => "S256"
      )
      launch = @runner.run("xdg-open", "#{client.fetch('auth_uri')}?#{query}", timeout_seconds: 10, max_output_bytes: 8 * 1024)
      raise CredentialError, "could not open the Google authorization page" unless launch.success?

      ready = IO.select([server], nil, nil, @callback_timeout)
      raise CredentialError, "Google authorization timed out" unless ready
      socket = server.accept
      request_line = socket.gets.to_s
      raise CredentialError, "OAuth callback request is invalid" if request_line.bytesize > 8 * 1024
      target = request_line.split(" ", 3)[1].to_s
      uri = URI.parse(target)
      parameters = URI.decode_www_form(uri.query.to_s).to_h
      valid = uri.path == "/oauth2/callback" && secure_compare(parameters["state"], state)
      if valid && !parameters["code"].to_s.empty?
        respond_callback(socket, 200, "Soul received authorization. You may close this tab.")
        {
          "code" => parameters.fetch("code"),
          "redirect_uri" => redirect_uri,
          "code_verifier" => verifier
        }
      else
        respond_callback(socket, 400, "Soul rejected this authorization response.")
        reason = parameters["error"].to_s.empty? ? "OAuth callback state or code was invalid" : "Google authorization was not granted"
        raise CredentialError, reason
      end
    ensure
      socket&.close
      server&.close
    end

    def respond_callback(socket, status, message)
      body = "<!doctype html><meta charset=\"utf-8\"><title>Soul YouTube authorization</title><p>#{message}</p>"
      socket.write("HTTP/1.1 #{status} #{status == 200 ? 'OK' : 'Bad Request'}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
    rescue IOError, SystemCallError
      nil
    end

    def read_stored_credentials
      path = credential_path
      raise CredentialError, "YouTube OAuth is not configured" unless File.file?(path) && !File.symlink?(path)
      raise CredentialError, "YouTube OAuth credential permissions must be owner-only" unless (File.stat(path).mode & 0o077).zero?
      raise CredentialError, "YouTube OAuth credential exceeds size limit" unless File.size(path).between?(1, MAX_CREDENTIAL_BYTES)

      credential = JSON.parse(File.binread(path, MAX_CREDENTIAL_BYTES))
      required = %w[project_id client_id client_secret token_uri refresh_token scopes channel_id channel_title]
      raise CredentialError, "YouTube OAuth credential is incomplete" unless required.all? { |key| !credential[key].to_s.empty? }
      raise CredentialError, "YouTube OAuth credential project is invalid" unless credential["project_id"] == PROJECT_ID
      raise CredentialError, "YouTube OAuth credential channel is invalid" unless credential["channel_id"] == EXPECTED_CHANNEL_ID
      raise CredentialError, "YouTube OAuth credential scopes are invalid" unless (@scopes - Array(credential["scopes"])).empty?

      credential
    rescue JSON::ParserError
      raise CredentialError, "YouTube OAuth credential is invalid"
    end

    def write_credentials(value)
      directory = File.dirname(credential_path)
      secure_credential_directory(directory)
      temporary = "#{credential_path}.tmp-#{Process.pid}-#{@random.hex(4)}"
      File.write(temporary, JSON.pretty_generate(value) + "\n", mode: "wx", perm: 0o600)
      File.rename(temporary, credential_path)
      File.chmod(0o600, credential_path)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def credential_path
      File.join(@root, "Soul", "runtime", "youtube_auth", @credential_name)
    end

    def secure_credential_directory(path)
      expanded = File.expand_path(path)
      raise CredentialError, "YouTube OAuth credential path is outside the Soul root" unless expanded.start_with?(@root + File::SEPARATOR)

      relative = expanded.delete_prefix(@root + File::SEPARATOR)
      current = @root
      relative.split(File::SEPARATOR).each do |component|
        current = File.join(current, component)
        raise CredentialError, "YouTube OAuth credential path contains a symlink" if File.symlink?(current)
      end
      FileUtils.mkdir_p(expanded, mode: 0o700)
      raise CredentialError, "YouTube OAuth credential path is not a directory" unless File.directory?(expanded) && !File.symlink?(expanded)
      File.chmod(0o700, expanded)
    end

    def google_https?(value)
      uri = URI.parse(value.to_s)
      uri.is_a?(URI::HTTPS) && %w[accounts.google.com oauth2.googleapis.com].include?(uri.host)
    rescue URI::InvalidURIError
      false
    end

    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))
    def secure_compare(left, right) = left.to_s.bytesize == right.to_s.bytesize && left.to_s.bytes.zip(right.to_s.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    def safe_message(error) = error.message.to_s.gsub(/ya29\.[A-Za-z0-9._-]+|1\/\/[A-Za-z0-9._-]+/, "[REDACTED]").slice(0, 500)
    def outcome(state, ok, reason, data: {}, mutation: "none") = { "ok" => ok, "lifecycle_state" => state, "reason" => reason, "data" => data, "mutation" => mutation }
  end
end
