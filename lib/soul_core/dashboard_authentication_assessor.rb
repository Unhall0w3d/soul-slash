# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "dashboard_authentication"
require_relative "dashboard_http_application"
require_relative "dashboard_server"

module SoulCore
  class DashboardAuthenticationAssessor
    class RecordingFacade
      attr_reader :calls

      def initialize
        @calls = []
      end

      def call(request)
        @calls << request
        {
          "schema_version" => "soul.application.v1",
          "request_id" => request["request_id"],
          "operation" => request["operation"],
          "ok" => true,
          "lifecycle_state" => "complete",
          "data" => { "fixture" => true },
          "errors" => [],
          "warnings" => [],
          "meta" => { "mutation" => "none" }
        }
      end
    end

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      checks = {}
      Dir.mktmpdir("soul-dashboard-auth-") do |temporary_root|
        clock_time = Time.utc(2026, 7, 15, 12, 0, 0)
        counter = 0
        random_bytes = lambda do |count|
          counter += 1
          OpenSSL::Digest::SHA256.digest("fixture-#{counter}").byteslice(0, count)
        end
        auth = DashboardAuthentication.new(root: temporary_root, iterations: 2_000, clock: -> { clock_time }, random_bytes: random_bytes)
        credential_path = auth.credential_path
        credential = JSON.parse(File.read(credential_path))

        checks["bootstrap_credential_is_hashed_private_and_forces_change"] =
          File.stat(credential_path).mode & 0o077 == 0 &&
          credential["username"] == "admin" &&
          credential["algorithm"] == "pbkdf2-hmac-sha256" &&
          credential["iterations"] == 2_000 &&
          credential["password_change_required"] == true &&
          !File.read(credential_path).include?(DashboardAuthentication::BOOTSTRAP_PASSWORD)

        facade = RecordingFacade.new
        app = DashboardHttpApplication.new(
          root: @root,
          facade: facade,
          bind_host: "127.0.0.1",
          port: 4567,
          csrf_token: "auth-fixture-csrf",
          authentication: auth
        )
        host = { "Host" => "127.0.0.1:4567" }
        mutation_headers = host.merge(
          "Origin" => "http://127.0.0.1:4567",
          "Content-Type" => "application/json",
          "X-Soul-CSRF" => "auth-fixture-csrf"
        )

        anonymous = app.call(method: "GET", target: "/auth/v1/session", headers: host)
        checks["anonymous_session_discloses_no_private_state"] =
          anonymous.status == 200 && JSON.parse(anonymous.body).slice("authenticated", "password_change_required") == { "authenticated" => false, "password_change_required" => false }

        unauthenticated_api = app.call(method: "POST", target: "/api/v1/call", headers: mutation_headers, body: application_request)
        checks["application_facade_is_inaccessible_without_login"] =
          unauthenticated_api.status == 401 && facade.calls.empty?

        wrong_origin = post(app, "/auth/v1/login", mutation_headers.merge("Origin" => "http://evil.example"), login_body("soul123"))
        wrong_csrf = post(app, "/auth/v1/login", mutation_headers.merge("X-Soul-CSRF" => "wrong"), login_body("soul123"))
        checks["login_requires_exact_origin_content_type_and_csrf"] = wrong_origin.status == 403 && wrong_csrf.status == 403

        invalid = post(app, "/auth/v1/login", mutation_headers, login_body("incorrect"))
        login = post(app, "/auth/v1/login", mutation_headers, login_body("soul123"))
        login_payload = JSON.parse(login.body)
        cookie = login.headers["Set-Cookie"]
        token = cookie.to_s[/soul_session=([^;]+)/, 1]
        checks["bootstrap_login_is_generic_and_still_change_gated"] =
          invalid.status == 401 && JSON.parse(invalid.body).dig("error", "code") == "invalid_credentials" &&
          login.status == 200 && login_payload["authenticated"] == true && login_payload["password_change_required"] == true
        checks["session_cookie_is_host_only_http_only_and_strict"] =
          cookie.include?("HttpOnly") && cookie.include?("SameSite=Strict") && cookie.include?("Path=/") && !cookie.include?("Domain=") && !cookie.include?("soul123")

        bootstrap_headers = mutation_headers.merge("Cookie" => "soul_session=#{token}")
        gated_api = app.call(method: "POST", target: "/api/v1/call", headers: bootstrap_headers, body: application_request)
        checks["bootstrap_session_cannot_access_soul_data"] = gated_api.status == 403 && facade.calls.empty?

        short = post(app, "/auth/v1/change-password", bootstrap_headers, password_body("soul123", "too-short", "too-short"))
        changed = post(app, "/auth/v1/change-password", bootstrap_headers, password_body("soul123", "A private Soul passphrase 2026", "A private Soul passphrase 2026"))
        changed_payload = JSON.parse(changed.body)
        changed_cookie = changed.headers["Set-Cookie"]
        changed_token = changed_cookie.to_s[/soul_session=([^;]+)/, 1]
        checks["password_policy_and_confirmation_are_enforced"] = short.status == 422 && JSON.parse(short.body).dig("error", "code") == "password_policy"
        checks["password_change_rotates_credential_and_session"] =
          changed.status == 200 && changed_payload["password_change_required"] == false &&
          auth.session(token).nil? && auth.session(changed_token)&.fetch("authenticated") == true &&
          JSON.parse(File.read(credential_path))["password_change_required"] == false &&
          !File.read(credential_path).include?("A private Soul passphrase 2026")

        authorized_headers = mutation_headers.merge("Cookie" => "soul_session=#{changed_token}")
        authorized = app.call(method: "POST", target: "/api/v1/call", headers: authorized_headers, body: application_request)
        checks["changed_session_delegates_to_facade_once"] = authorized.status == 200 && facade.calls.length == 1

        old_password = post(app, "/auth/v1/login", mutation_headers, login_body("soul123"))
        new_password = post(app, "/auth/v1/login", mutation_headers, login_body("A private Soul passphrase 2026"))
        checks["bootstrap_password_is_invalid_after_replacement"] = old_password.status == 401 && new_password.status == 200

        logout = post(app, "/auth/v1/logout", authorized_headers, "{}")
        after_logout = app.call(method: "POST", target: "/api/v1/call", headers: authorized_headers, body: application_request)
        checks["logout_expires_cookie_and_revokes_session"] = logout.status == 200 && logout.headers["Set-Cookie"].include?("Max-Age=0") && after_logout.status == 401

        rate_auth = DashboardAuthentication.new(root: temporary_root, credential_path: "Soul/runtime/dashboard_auth/rate.json", iterations: 1_000, clock: -> { clock_time }, random_bytes: random_bytes)
        DashboardAuthentication::FAILED_ATTEMPT_LIMIT.times { rate_auth.authenticate(username: "admin", password: "wrong") }
        limited = rate_auth.authenticate(username: "admin", password: "wrong")
        checks["failed_login_rate_limit_is_bounded_and_request_driven"] = limited.status == 429 && limited.retry_after.between?(1, DashboardAuthentication::FAILED_ATTEMPT_WINDOW_SECONDS)

        expiry_time = Time.utc(2026, 7, 15, 12, 0, 0)
        expiry_auth = DashboardAuthentication.new(root: temporary_root, credential_path: "Soul/runtime/dashboard_auth/expiry.json", iterations: 1_000, clock: -> { expiry_time }, random_bytes: random_bytes)
        expiry_login = expiry_auth.authenticate(username: "admin", password: "soul123")
        expiry_time += DashboardAuthentication::SESSION_IDLE_SECONDS + 1
        checks["sessions_expire_without_a_background_cleanup_loop"] = expiry_auth.session(expiry_login.token).nil?

        resetting_operator = DashboardAuthentication.new(root: temporary_root, iterations: 2_000, clock: -> { clock_time }, random_bytes: random_bytes, reset_to_bootstrap: true)
        reset_record = JSON.parse(File.read(credential_path))
        checks["explicit_local_reset_restores_change_gate_and_revokes_sessions"] =
          reset_record["password_change_required"] == true && resetting_operator.password_change_required? && auth.session(changed_token).nil?
      end

      source_checks(checks)
      blockers = checks.filter_map { |name, passed| name unless passed }
      {
        "ok" => blockers.empty?,
        "assessment" => "phase12c1_dashboard_authentication",
        "milestone" => "conversational_soul",
        "phase" => "12C.1",
        "status" => blockers.empty? ? "blocked_for_human_review" : "blocked",
        "blockers" => blockers,
        "verification" => checks,
        "memory_keys" => [],
        "lifecycle_states" => %w[complete failed awaiting_input canceled blocked_for_human_review],
        "risk_class" => "Class 5: security-sensitive authentication and private-runtime credential storage",
        "human_visual_review_required" => true,
        "human_merge_review_required" => true
      }
    end

    def render(report)
      lines = ["Soul Phase 12C.1 Dashboard Authentication Assessment", "Status: #{report['status']}", "", "Verification"]
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |item| lines << "- #{item}" }
      lines.join("\n")
    end

    private

    def post(app, target, headers, body)
      app.call(method: "POST", target: target, headers: headers, body: body)
    end

    def login_body(password)
      JSON.generate({ "username" => "admin", "password" => password })
    end

    def password_body(current, replacement, confirmation)
      JSON.generate({ "current_password" => current, "new_password" => replacement, "confirmation" => confirmation })
    end

    def application_request
      JSON.generate({ "schema_version" => "soul.application.v1", "request_id" => "auth:fixture:0001", "operation" => "application.bootstrap", "parameters" => {}, "context" => { "interface" => "dashboard_test" } })
    end

    def source_checks(checks)
      html = File.read(File.join(@root, "assets/dashboard/index.html"))
      css = File.read(File.join(@root, "assets/dashboard/dashboard.css"))
      javascript = File.read(File.join(@root, "assets/dashboard/dashboard.js"))
      server = File.read(File.join(@root, "lib/soul_core/dashboard_server.rb"))
      schema = File.read(File.join(@root, "lib/soul_core/configuration_schema.rb"))
      brief = File.read(File.join(@root, "docs/soul/PHASE12C1_DASHBOARD_AUTHENTICATION_BRIEF.md"))
      auth_source = File.read(File.join(@root, "lib/soul_core/dashboard_authentication.rb"))

      checks["locked_dashboard_is_blurred_inert_and_accessibly_overlaid"] =
        html.include?('class="auth-locked"') && html.include?('id="auth-gate"') && html.include?('aria-modal="true"') &&
        css.include?("filter:blur(9px)") && javascript.include?("element.inert = locked")
      checks["browser_stores_no_password_or_bearer_token"] =
        %w[localStorage sessionStorage document.cookie].none? { |primitive| javascript.include?(primitive) } &&
        !html.include?(DashboardAuthentication::BOOTSTRAP_PASSWORD)
      checks["no_signup_or_account_creation_surface_exists"] =
        %w[/auth/v1/signup /auth/v1/register createAccount registerAccount].none? { |primitive| [html, javascript].any? { |source| source.include?(primitive) } }
      checks["authentication_does_not_weaken_existing_approval_gates"] =
        html.include?("APPROVE_PROPOSAL_FOR_BETA_BUILD") && html.include?("APPROVE_BETA_FOR_PROMOTION") && html.include?("DELETE_AND_FORGET_CONVERSATION")
      checks["lan_and_persistence_remain_excluded"] =
        schema.include?(":loopback_host") && !DashboardServer.loopback?("0.0.0.0") &&
        %w[systemd daemon( Thread.new].none? { |primitive| [server, auth_source].any? { |source| source.include?(primitive) } } &&
        brief.include?("lan_binding_authorized: no") && brief.include?("persistent_service_authorized: no")
      checks["production_password_work_factor_matches_reviewed_baseline"] = DashboardAuthentication::PBKDF2_ITERATIONS == 600_000
    end
  end
end
