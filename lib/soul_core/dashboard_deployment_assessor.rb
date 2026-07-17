# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "dashboard_authentication"
require_relative "dashboard_deployment"
require_relative "dashboard_http_application"

module SoulCore
  class DashboardDeploymentAssessor
    class NullFacade
      attr_reader :calls

      def initialize
        @calls = []
      end

      def call(request)
        @calls << request
        { "schema_version" => "soul.application.v1", "request_id" => request["request_id"], "operation" => request["operation"], "ok" => true, "lifecycle_state" => "complete", "data" => {}, "errors" => [], "warnings" => [], "meta" => { "mutation" => "none" } }
      end
    end

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      checks = {}
      Dir.mktmpdir("soul-deploy-root-") do |temporary_root|
        Dir.mktmpdir("soul-deploy-home-") do |temporary_home|
          prepare_fixture(temporary_root)
          commands = []
          runner = lambda do |command|
            commands << command
            { "success" => true, "stdout" => "fixture-ok", "stderr" => "" }
          end
          deployment = DashboardDeployment.new(
            root: temporary_root,
            home: temporary_home,
            ruby_path: fixture_executable(temporary_root, "ruby"),
            caddy_path: fixture_executable(temporary_root, "caddy"),
            systemctl_path: fixture_executable(temporary_root, "systemctl"),
            assigned_addresses: ["192.168.50.10"],
            command_runner: runner,
            clock: -> { Time.utc(2026, 7, 15, 16, 0, 0) }
          )

          rejected_hosts = ["0.0.0.0", "127.0.0.1", "192.168.50.11", "not-an-ip"]
          checks["plan_rejects_wildcard_loopback_unassigned_and_invalid_hosts"] = rejected_hosts.all? { |host| !deployment.plan(lan_host: host).ok }
          checks["plan_rejects_privileged_colliding_and_invalid_ports"] = [443, 4567, 70_000, "bad"].all? { |port| !deployment.plan(lan_host: "192.168.50.10", https_port: port).ok }

          plan = deployment.plan(lan_host: "192.168.50.10", https_port: 8443)
          checks["valid_plan_is_review_blocked_and_portable"] =
            plan.ok && plan.lifecycle_state == "blocked_for_human_review" &&
            plan.details["public_origin"] == "https://192.168.50.10:8443" &&
            plan.details["soul_bind"] == "127.0.0.1:4567" &&
            plan.details["confirmation_phrase"] == DashboardDeployment::CONFIRM_INSTALL

          contents = deployment.rendered_contents(lan_host: "192.168.50.10", https_port: 8443)
          combined = contents.values.join("\n")
          checks["rendered_configuration_keeps_soul_loopback_and_caddy_exact"] =
            contents["environment"].include?("SOUL_DASHBOARD_BIND_HOST=127.0.0.1") &&
            contents["environment"].include?("SOUL_DASHBOARD_PUBLIC_ORIGIN=https://192.168.50.10:8443") &&
            contents["caddyfile"].include?("bind 192.168.50.10") &&
            contents["caddyfile"].include?("tls internal") &&
            contents["caddyfile"].include?("admin off") &&
            !contents["caddyfile"].include?("0.0.0.0")
          checks["rendered_services_are_bounded_and_have_no_polling_or_extra_units"] =
            contents["soul_unit"].include?("Restart=on-failure") && contents["proxy_unit"].include?("Restart=on-failure") &&
            contents["soul_unit"].include?("WorkingDirectory=#{temporary_root}") && !contents["soul_unit"].include?("WorkingDirectory=\"") &&
            combined.scan("StartLimitBurst=3").length == 2 &&
            %w[.timer .socket health_uri setInterval setTimeout cron].none? { |primitive| combined.include?(primitive) }
          checks["rendered_files_contain_no_authentication_secret"] =
            !combined.include?("soul123") && !combined.include?("password_hash") && !combined.include?("soul_session")

          awaiting = deployment.install(lan_host: "192.168.50.10", confirmation: "wrong")
          checks["install_requires_exact_confirmation_before_writes"] = awaiting.lifecycle_state == "awaiting_input" && commands.empty? && plan.details["files"].values.none? { |path| File.exist?(path) }

          installed = deployment.install(lan_host: "192.168.50.10", confirmation: DashboardDeployment::CONFIRM_INSTALL)
          checks["confirmed_install_validates_renders_and_enables_two_services"] =
            installed.ok && installed.lifecycle_state == "complete" &&
            commands.any? { |command| command.include?("validate") } &&
            commands.count { |command| command.include?("enable") && !command.include?("--now") } == 2 &&
            commands.count { |command| command.include?("restart") } == 2 &&
            plan.details["files"].values.all? { |path| File.file?(path) && (File.stat(path).mode & 0o077).zero? }

          credential_path = File.join(temporary_root, DashboardAuthentication::CREDENTIAL_PATH)
          caddy_state = File.join(temporary_home, ".local/share/caddy/preserved.txt")
          FileUtils.mkdir_p(File.dirname(caddy_state))
          File.write(caddy_state, "preserve")
          uninstall_wait = deployment.uninstall(confirmation: "wrong")
          uninstalled = deployment.uninstall(confirmation: DashboardDeployment::CONFIRM_UNINSTALL)
          checks["uninstall_is_confirmed_bounded_and_preserves_private_state"] =
            uninstall_wait.lifecycle_state == "awaiting_input" && uninstalled.ok &&
            plan.details["files"].values.none? { |path| File.exist?(path) } &&
            File.file?(credential_path) && File.file?(caddy_state)

          forced_root = File.join(temporary_root, "forced")
          prepare_fixture(forced_root, password_change_required: true)
          forced = DashboardDeployment.new(root: forced_root, home: temporary_home, ruby_path: fixture_executable(forced_root, "ruby"), caddy_path: fixture_executable(forced_root, "caddy"), systemctl_path: fixture_executable(forced_root, "systemctl"), assigned_addresses: ["192.168.50.10"], command_runner: runner)
          checks["bootstrap_credential_blocks_persistent_lan_deployment"] = !forced.plan(lan_host: "192.168.50.10").ok

          remote_http_checks(checks, temporary_root)
        end
      end

      source_checks(checks)
      blockers = checks.filter_map { |name, passed| name unless passed }
      {
        "ok" => blockers.empty?,
        "assessment" => "protected_lan_systemd_deployment",
        "phase" => "deployment",
        "status" => blockers.empty? ? "blocked_for_human_review" : "blocked",
        "blockers" => blockers,
        "verification" => checks,
        "memory_keys" => [],
        "lifecycle_states" => %w[complete failed awaiting_input canceled blocked_for_human_review],
        "risk_class" => "Class 5: persistent service, LAN network listener, TLS trust, and private runtime access",
        "human_deployment_review_required" => true,
        "human_merge_review_required" => true
      }
    end

    def render(report)
      lines = ["Soul Protected LAN and systemd Deployment Assessment", "Status: #{report['status']}", "", "Verification"]
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |item| lines << "- #{item}" }
      lines.join("\n")
    end

    private

    def prepare_fixture(root, password_change_required: false)
      FileUtils.mkdir_p(File.join(root, "bin"))
      File.write(File.join(root, "bin/soul"), "#!/usr/bin/env ruby\n")
      File.chmod(0o700, File.join(root, "bin/soul"))
      auth = DashboardAuthentication.new(root: root, iterations: 1_000)
      return if password_change_required

      login = auth.authenticate(username: "admin", password: "soul123")
      auth.change_password(token: login.token, current_password: "soul123", new_password: "Fixture deployment password 2026", confirmation: "Fixture deployment password 2026")
    end

    def fixture_executable(root, name)
      path = File.join(root, "bin", name)
      File.write(path, "#!/bin/sh\nexit 0\n")
      File.chmod(0o700, path)
      path
    end

    def remote_http_checks(checks, root)
      auth = DashboardAuthentication.new(root: root, iterations: 1_000)
      facade = NullFacade.new
      app = DashboardHttpApplication.new(root: @root, facade: facade, bind_host: "127.0.0.1", port: 4567, csrf_token: "deploy-csrf", authentication: auth, public_origin: "https://192.168.50.10:8443")
      public_headers = { "Host" => "192.168.50.10:8443", "Origin" => "https://192.168.50.10:8443", "Content-Type" => "application/json", "X-Soul-CSRF" => "deploy-csrf" }
      rejected = app.call(method: "GET", target: "/", headers: { "Host" => "192.168.50.11:8443" })
      wrong_origin = app.call(method: "POST", target: "/auth/v1/login", headers: public_headers.merge("Origin" => "https://evil.example"), body: JSON.generate({ "username" => "admin", "password" => "Fixture deployment password 2026" }))
      login = app.call(method: "POST", target: "/auth/v1/login", headers: public_headers, body: JSON.generate({ "username" => "admin", "password" => "Fixture deployment password 2026" }))
      checks["public_authority_is_exact_and_wrong_hosts_origins_fail_closed"] = rejected.status == 400 && wrong_origin.status == 403
      checks["accepted_https_origin_receives_secure_host_only_cookie"] = login.status == 200 && login.headers["Set-Cookie"].include?("Secure") && login.headers["Set-Cookie"].include?("HttpOnly") && login.headers["Set-Cookie"].include?("SameSite=Strict") && !login.headers["Set-Cookie"].include?("Domain=")
    end

    def source_checks(checks)
      brief = File.read(File.join(@root, "docs/soul/PROTECTED_LAN_SYSTEMD_DEPLOYMENT_BRIEF.md"))
      installer = File.read(File.join(@root, "lib/soul_core/dashboard_deployment.rb"))
      checks["brief_explicitly_authorizes_only_two_user_services"] = brief.include?("persistent_services_authorized: exactly two user services") && DashboardDeployment::SERVICE_NAMES.length == 2
      forbidden_commands = %w[iptables nftables ufw firewall-cmd upnp port-forward pacman apt dnf]
      checks["installer_does_not_mutate_firewall_router_or_private_data"] = forbidden_commands.none? { |primitive| installer.match?(/\b#{Regexp.escape(primitive)}\b/i) }
    end
  end
end
