#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/winboat_inventory_adapter"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class WinboatFakeRunner
  attr_reader :calls

  def initialize(state: "running\ttrue\t2026-08-02T12:00:00Z\t2\tghcr.io/dockur/windows:5.14\n", network: "172.18.0.2\n", bindings: nil, failure: nil)
    @state = state
    @network = network
    @bindings = bindings || JSON.generate(
      "3389/tcp" => [{"HostIp" => "127.0.0.1", "HostPort" => "47300"}],
      "7148/tcp" => [{"HostIp" => "127.0.0.1", "HostPort" => "47280"}]
    )
    @failure = failure
    @calls = []
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    return result("", "container unavailable", 1, "failed") if @failure
    if argv[1] == "port"
      return result("127.0.0.1:47300\n", "", 0, "ok") if argv.last == "3389/tcp"
      return result("127.0.0.1:47280\n", "", 0, "ok") if argv.last == "7148/tcp"
    end

    format = argv.fetch(argv.index("--format") + 1)
    stdout = if format.include?(".State.Status")
               @state
             elsif format.include?(".NetworkSettings.Networks")
               @network
             elsif format.include?(".HostConfig.PortBindings")
               @bindings
             else
               return result("", "unexpected inspect format", 1, "failed")
             end
    result(stdout, "", 0, "ok")
  end

  private

  def result(stdout, stderr, exit_status, status)
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: stdout, stderr: stderr, exit_status: exit_status, status: status, truncated: false
    )
  end
end

puts "WinBoat host-local inventory A1 verification:"

runner = WinboatFakeRunner.new
probes = []
adapter = SoulCore::WinboatInventoryAdapter.new(
  runner: runner,
  tcp_probe: ->(host, port) { probes << [host, port]; true }
)
inventory = adapter.collect(container_name: "WinBoat", fqdn: "chancery.example.test", guest_address: "172.30.0.2")

check.call("fixed read-only inspection returns a healthy Windows guest identity",
           inventory["available"] == true && inventory["healthy"] == true &&
             inventory["fqdn"] == "chancery.example.test" && inventory["guest_address"] == "172.30.0.2" &&
             inventory["container_address"] == "172.18.0.2" && inventory["restart_count"] == 2)
check.call("only expected loopback bindings are probed",
           probes == [["127.0.0.1", 47_300], ["127.0.0.1", 47_280]] && inventory["loopback_only"] == true)
check.call("Docker commands use fixed inspect fields and fixed port resolution without requesting environment data",
           runner.calls.length == 5 && runner.calls.all? do |call|
             argv = call.fetch("argv")
             ((argv[0, 4] == ["/usr/bin/docker", "inspect", "--type", "container"] && argv.last == "WinBoat") ||
               (argv[0, 3] == ["/usr/bin/docker", "port", "WinBoat"] && %w[3389/tcp 7148/tcp].include?(argv.last))) &&
               !argv.join(" ").include?(".Config.Env") &&
               call.dig("options", :max_output_bytes) == 16 * 1024
           end)

exposed_runner = WinboatFakeRunner.new(bindings: JSON.generate(
  "3389/tcp" => [{"HostIp" => "0.0.0.0", "HostPort" => "47300"}],
  "7148/tcp" => [{"HostIp" => "127.0.0.1", "HostPort" => "47280"}]
))
exposed_probes = []
exposed = SoulCore::WinboatInventoryAdapter.new(
  runner: exposed_runner,
  tcp_probe: ->(host, port) { exposed_probes << [host, port]; true }
).collect(container_name: "WinBoat", fqdn: "chancery.example.test", guest_address: "172.30.0.2")
check.call("non-loopback publication fails closed and is not treated as reachable",
           exposed["available"] == true && exposed["loopback_only"] == false &&
             exposed["reachable"] == false && !exposed_probes.include?(["127.0.0.1", 47_300]))

unavailable = SoulCore::WinboatInventoryAdapter.new(
  runner: WinboatFakeRunner.new(failure: true), tcp_probe: ->(_host, _port) { true }
).collect(container_name: "WinBoat", fqdn: "chancery.example.test", guest_address: "172.30.0.2")
check.call("missing container returns bounded unavailable evidence",
           unavailable["available"] == false && unavailable["reachable"] == false && unavailable["evidence"].length == 1)

invalid = adapter.collect(container_name: "WinBoat;sh", fqdn: "chancery.example.test", guest_address: "172.30.0.2")
check.call("untrusted container names are rejected before command execution", invalid["available"] == false && runner.calls.length == 5)

source = File.read(File.join(__dir__, "../lib/soul_core/maintenance_fleet_status_service.rb"))
dashboard = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
check.call("fleet integration remains read-only and host-local",
           source.include?('"management_channel" => "host_local_inventory"') &&
             source.include?('"mutation_supported" => false') &&
             source.include?('"network_scope" => "host_local"') &&
             source.include?('control: "inventory_only"'))
check.call("dashboard identifies host-local inventory without mutation controls",
           dashboard.include?("Host-local inventory only · no guest mutation or LAN authority") &&
             dashboard.include?('device.facts?.fqdn ? [["Identity", device.facts.fqdn]]') &&
             dashboard.include?("Workstation-contained systems") && dashboard.include?("not LAN-routed"))

abort("WinBoat inventory verification failed: #{errors.join(', ')}") unless errors.empty?

puts "WinBoat inventory verification passed."
