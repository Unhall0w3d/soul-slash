#!/usr/bin/env ruby
# The proxy must remain available across backend stop/restart transactions.
require_relative "../lib/soul_core/dashboard_deployment"

deployment = SoulCore::DashboardDeployment.new(
  root: File.expand_path("..", __dir__), assigned_addresses: ["192.168.124.74"]
)
proxy = deployment.rendered_contents(lan_host: "192.168.124.74", public_host: "atelier.herz.soul").fetch("proxy_unit")
abort "proxy must request backend startup" unless proxy.lines.any? { |line| line.start_with?("Wants=") && line.split.include?("Wants=soul-dashboard.service") }
abort "proxy must not stop with backend" if proxy.match?(/^(Requires|BindsTo|PartOf)=.*soul-dashboard\.service/)
abort "backend ordering lost" unless proxy.match?(/^After=.*soul-dashboard\.service/)
abort "proxy hardening lost" unless proxy.include?("NoNewPrivileges=true") && proxy.include?("ProtectSystem=strict")
puts "PASS: startup dependency, independent lifecycle, ordering and hardening"
