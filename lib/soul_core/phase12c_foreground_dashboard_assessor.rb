# frozen_string_literal: true

require "json"
require_relative "dashboard_http_application"
require_relative "dashboard_server"

module SoulCore
  class Phase12cForegroundDashboardAssessor
    class RecordingFacade
      attr_reader :calls

      def initialize
        @calls = []
      end

      def call(request)
        @calls << request
        if request["operation"] == "unknown.operation"
          return envelope(request, "failed", {}, [{ "code" => "invalid_request", "message" => "unknown application operation" }])
        end

        envelope(request, request.dig("parameters", "fixture_lifecycle") || "complete", { "fixture" => true })
      end

      private

      def envelope(request, lifecycle, data, errors = [])
        {
          "schema_version" => "soul.application.v1",
          "request_id" => request["request_id"],
          "operation" => request["operation"],
          "ok" => lifecycle == "complete",
          "lifecycle_state" => lifecycle,
          "data" => data,
          "errors" => errors,
          "warnings" => [],
          "meta" => { "mutation" => "none" }
        }
      end
    end

    class RecordingAuthentication
      def session(token, touch: true)
        return nil unless token == "fixture-session"

        { "authenticated" => true, "username" => "admin", "password_change_required" => false }
      end
    end

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      checks = {}
      facade = RecordingFacade.new
      app = DashboardHttpApplication.new(root: @root, facade: facade, bind_host: "127.0.0.1", port: 4567, csrf_token: "fixture-csrf-token", authentication: RecordingAuthentication.new)
      get_headers = { "Host" => "127.0.0.1:4567" }
      api_headers = get_headers.merge("Origin" => "http://127.0.0.1:4567", "Content-Type" => "application/json", "X-Soul-CSRF" => "fixture-csrf-token", "Cookie" => "soul_session=fixture-session")

      document = app.call(method: "GET", target: "/", headers: get_headers)
      head = app.call(method: "HEAD", target: "/", headers: get_headers)
      checks["dashboard_document_and_head_are_allowlisted"] = document.status == 200 && head.status == 200 && head.body.empty? && document.body.include?("Soul/") && document.body.include?("fixture-csrf-token")

      static_responses = DashboardHttpApplication::STATIC_ROUTES.keys.map { |route| app.call(method: "GET", target: route, headers: get_headers) }
      skill_studio_asset = DashboardHttpApplication::STATIC_ROUTES["/brand/skill-studio.png"]
      checks["exact_static_allowlist_serves_only_approved_assets"] =
        static_responses.all? { |response| response.status == 200 && response.headers["Cache-Control"] == "no-store" } &&
        DashboardHttpApplication::STATIC_ROUTES.length == 7 &&
        skill_studio_asset == ["assets/brand/soul-slash-skill-studio.png", "image/png"]

      rejected_targets = ["/../.env", "/%2e%2e/.env", "/assets/../.env", "/assets/dashboard.js?x=1", "/unknown.png"]
      checks["traversal_query_confusion_and_unknown_paths_fail_closed"] = rejected_targets.all? { |target| app.call(method: "GET", target: target, headers: get_headers).status == 404 }

      checks["unsupported_methods_fail_closed"] = app.call(method: "POST", target: "/", headers: get_headers).status == 405 && app.call(method: "GET", target: "/api/v1/call", headers: get_headers).status == 405

      checks["host_authority_is_required_and_bounded"] = [nil, "evil.example:4567", "127.0.0.1:9999"].all? { |host| app.call(method: "GET", target: "/", headers: { "Host" => host }).status == 400 } && app.call(method: "GET", target: "/", headers: { "Host" => "localhost:4567" }).status == 200

      valid_body = request_json("application.bootstrap")
      invalid_origin = api_headers.merge("Origin" => "http://evil.example:4567")
      invalid_csrf = api_headers.merge("X-Soul-CSRF" => "wrong")
      checks["api_requires_exact_origin_and_csrf"] = app.call(method: "POST", target: "/api/v1/call", headers: invalid_origin, body: valid_body).status == 403 && app.call(method: "POST", target: "/api/v1/call", headers: invalid_csrf, body: valid_body).status == 403

      checks["api_requires_json_and_valid_bounded_body"] = app.call(method: "POST", target: "/api/v1/call", headers: api_headers.merge("Content-Type" => "text/plain"), body: valid_body).status == 415 && app.call(method: "POST", target: "/api/v1/call", headers: api_headers, body: "{").status == 400 && app.call(method: "POST", target: "/api/v1/call", headers: api_headers, body: "x" * (128 * 1024 + 1)).status == 413

      before = facade.calls.length
      valid = app.call(method: "POST", target: "/api/v1/call", headers: api_headers, body: valid_body)
      checks["valid_api_request_delegates_to_facade_exactly_once"] = valid.status == 200 && facade.calls.length == before + 1 && facade.calls.last["operation"] == "application.bootstrap"

      unknown = app.call(method: "POST", target: "/api/v1/call", headers: api_headers, body: request_json("unknown.operation"))
      checks["application_lifecycle_and_failure_are_returned_unchanged"] = JSON.parse(valid.body)["lifecycle_state"] == "complete" && JSON.parse(unknown.body)["lifecycle_state"] == "failed"

      headers = document.headers
      checks["browser_security_headers_and_no_store_are_present"] = headers["Content-Security-Policy"].include?("default-src 'self'") && headers["Content-Security-Policy"].include?("frame-ancestors 'none'") && headers["X-Frame-Options"] == "DENY" && headers["X-Content-Type-Options"] == "nosniff" && headers["Cache-Control"] == "no-store"

      html = File.read(File.join(@root, "assets/dashboard/index.html"))
      css = File.read(File.join(@root, "assets/dashboard/dashboard.css"))
      js = File.read(File.join(@root, "assets/dashboard/dashboard.js"))
      server = File.read(File.join(@root, "lib/soul_core/dashboard_server.rb"))
      command = File.read(File.join(@root, "lib/soul_core/dashboard_command.rb"))

      forbidden_frontend = %w[setInterval setTimeout WebSocket EventSource serviceWorker innerHTML eval( insertAdjacentHTML http:// https://]
      checks["frontend_has_no_polling_remote_or_unsafe_dom_primitive"] = forbidden_frontend.none? { |needle| [html, css, js].any? { |source| source.include?(needle) } } && js.include?("replaceChildren") && js.include?("textContent")

      checks["bootstrap_collects_status_once_and_refresh_remains_explicit"] =
        js.match?(/async function bootstrap\(\)[\s\S]{0,1600}await refreshStatus\(\{ automatic: true \}\)/) &&
        js.include?('byId("refresh-status").addEventListener("click", refreshStatus)') &&
        js.scan('"system_status.refresh"').length == 1 &&
        %w[setInterval setTimeout WebSocket EventSource].none? { |primitive| js.include?(primitive) }

      required_operations = %w[application.bootstrap chats.list chats.messages chats.create chats.send chats.pin chats.unpin chats.clear.preview chats.clear.execute workspace.chat inbox.list system_status.refresh]
      checks["chat_uses_registered_phase12b_operations"] = required_operations.all? { |operation| js.include?(operation) }

      legacy_preview = html.include?("Intentionally inert") && html.include?("Phase 12D")
      gated_phase12d =
        html.include?('id="proposal-approval"') &&
        html.include?('id="beta-promotion-card"') &&
        (html.include?("No automatic implementation, registration, or promotion") || html.include?("Nothing is implemented, registered, or promoted automatically")) &&
        js.include?("skill_studio.proposals.approval.preview") &&
        js.include?("skill_studio.betas.promotion.preview") &&
        !js.include?("skill.execute")
      checks["skill_studio_surface_respects_current_phase"] = html.include?('id="studio-tab"') && (legacy_preview || gated_phase12d)

      required_dom = ['role="tablist"', 'role="tabpanel"', '<main>', '<form id="composer"', '<label for="message-input"', 'role="status"']
      review_boundary = html.downcase.include?("human visual review") || (html.include?("Operator Gate 1") && html.include?("Operator Gate 2"))
      checks["semantic_accessible_reviewable_dom_is_present"] = required_dom.all? { |needle| html.include?(needle) } && review_boundary

      tokens = %w[#060B11 #D4AF37 #00E5FF #FF1744 #B7D8DC]
      checks["approved_visual_tokens_and_brand_assets_are_used"] = tokens.all? { |token| css.include?(token) } && html.scan("/brand/micro-mark.svg").length >= 4 && html.include?("rel=\"icon\"") && !html.include?("/brand/supporting-scene.png")

      checks["readable_type_scale_and_signal_interactions_replace_legacy_microcopy"] =
        css.include?("--type-micro:11px") &&
        css.include?("--type-label:12px") &&
        css.include?("--type-copy:14px") &&
        css.include?(".workflow-stages span { display:block; margin-bottom:19px; color:var(--cyan); font:700 12px") &&
        css.include?(".studio-header>div>p:last-child,.improvement-header>div>p:last-child { max-width:800px; margin:0; color:#91B2B7; font-size:14px") &&
        !css.include?("rgba(110,61,223")

      checks["focus_reduced_motion_and_responsive_rules_exist"] = css.include?(":focus-visible") && css.include?("prefers-reduced-motion") && css.scan("@media").length >= 3

      forbidden_server = %w[Thread.new fork( daemon( Process.spawn systemd cron launchd inotify]
      checks["foreground_server_has_no_worker_or_persistence_primitive"] = forbidden_server.none? { |needle| [server, command].any? { |source| source.include?(needle) } }

      checks["listener_rejects_non_loopback_before_bind"] = !DashboardServer.loopback?("0.0.0.0") && !DashboardServer.loopback?("192.168.1.10") && DashboardServer.loopback?("127.0.0.1") && raises_argument? { DashboardServer.new(host: "0.0.0.0", port: 4567, application: app) }

      checks["listener_limits_and_clean_request_cap_are_explicit"] = server.include?("REQUEST_LINE_LIMIT = 2 * 1024") && server.include?("HEADER_BYTES_LIMIT = 16 * 1024") && server.include?("BODY_LIMIT = 128 * 1024") && server.include?("READ_TIMEOUT = 5") && server.include?("@max_requests") && server.include?("Connection")

      checks["command_uses_typed_configuration_and_explicit_foreground_lifecycle"] = command.include?("ConfigurationResolver.new") && command.include?('dashboard.bind_host') && command.include?('dashboard.port') && command.include?("--max-requests") && command.include?("DashboardServer.new")

      blockers = checks.filter_map { |name, passed| name unless passed }
      {
        "ok" => blockers.empty?,
        "assessment" => "phase12c_foreground_loopback_dashboard",
        "milestone" => "conversational_soul",
        "phase" => "12C",
        "status" => blockers.empty? ? "blocked_for_human_review" : "blocked",
        "blockers" => blockers,
        "verification" => checks,
        "details" => { "route_count" => DashboardHttpApplication::STATIC_ROUTES.length + 2, "facade_call_count" => facade.calls.length },
        "memory_keys" => [],
        "lifecycle_states" => %w[complete failed awaiting_input canceled blocked_for_human_review],
        "risk_class" => "Class 5: Security-sensitive foreground network listener exception",
        "human_visual_review_required" => true,
        "human_merge_review_required" => true
      }
    end

    def render(report)
      lines = ["Soul Phase 12C Foreground Loopback Dashboard Assessment", "Status: #{report['status']}", "", "Verification"]
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |item| lines << "- #{item}" }
      lines.join("\n")
    end

    private

    def request_json(operation)
      JSON.generate({ "schema_version" => "soul.application.v1", "request_id" => "dashboard:fixture:0001", "operation" => operation, "parameters" => {}, "context" => { "interface" => "dashboard_test" } })
    end

    def raises_argument?
      yield
      false
    rescue ArgumentError
      true
    end
  end
end
