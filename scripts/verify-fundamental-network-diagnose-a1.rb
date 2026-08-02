#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "socket"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/conversation_orchestrator"
require_relative "../lib/soul_core/network_diagnostic_chat_controls"
require_relative "../lib/soul_core/network_diagnostic_service"

FakeInterface = Struct.new(:name, :addr)
FakeStatus = Struct.new(:exitstatus)

checks = []
check = lambda do |label, condition|
  raise label unless condition
  checks << label
end

ping_calls = []
socket_calls = []
resolver_calls = []
route_fixture = <<~ROUTES
  Iface Destination Gateway Flags RefCnt Use Metric Mask MTU Window IRTT
  eth0 00000000 0101A8C0 0003 0 0 100 00000000 0 0 0
  eth0 0001A8C0 00000000 0001 0 0 100 00FFFFFF 0 0 0
ROUTES

service = SoulCore::NetworkDiagnosticService.new(
  clock: -> { Time.utc(2026, 8, 2, 18, 0, 0) },
  address_source: -> {
    [
      FakeInterface.new("eth0", Addrinfo.ip("192.168.1.20")),
      FakeInterface.new("lo", Addrinfo.ip("127.0.0.1")),
      FakeInterface.new("eth0", Addrinfo.ip("192.168.1.20")),
      FakeInterface.new("bad\nname", Addrinfo.ip("192.168.1.21"))
    ]
  },
  route_reader: -> { route_fixture },
  resolver: ->(target) {
    resolver_calls << target
    ["2001:db8::20", "192.0.2.20", "192.0.2.20"]
  },
  ping_path: "/usr/bin/ping",
  ping_runner: ->(argv) {
    ping_calls << argv
    ["64 bytes from example.test: time=1.25 ms\n", "", FakeStatus.new(0)]
  },
  socket_connector: ->(target, port, timeout) {
    socket_calls << [target, port, timeout]
    true
  }
)

snapshot = service.snapshot
checks_data = snapshot.fetch("data")
check.call("local snapshot is bounded and omits hardware addresses",
  snapshot["lifecycle_state"] == "complete" &&
  checks_data.dig("addresses", "count") == 2 &&
  checks_data.dig("addresses", "records").none? { |record| record.key?("mac") })
check.call("Linux route evidence is decoded without a command",
  checks_data.dig("routes", "records", 0, "destination") == "0.0.0.0/0" &&
  checks_data.dig("routes", "records", 0, "gateway") == "192.168.1.1" &&
  checks_data.dig("routes", "records", 1, "destination") == "192.168.1.0/24")

many_addresses = (1..80).map do |index|
  third = ((index - 1) / 254) + 1
  fourth = ((index - 1) % 254) + 1
  FakeInterface.new("veth#{index}", Addrinfo.ip("10.#{third}.0.#{fourth}"))
end
bounded_snapshot = SoulCore::NetworkDiagnosticService.new(
  address_source: -> { many_addresses },
  route_reader: -> { route_fixture }
).snapshot
check.call("address results stop at the reviewed return limit",
  bounded_snapshot.dig("data", "addresses", "count") == 64 && bounded_snapshot.dig("data", "addresses", "truncated") == true)
many_routes = route_fixture.lines.first + ([route_fixture.lines[1]] * 70).join
bounded_routes = SoulCore::NetworkDiagnosticService.new(
  address_source: -> { [] },
  route_reader: -> { many_routes }
).snapshot
check.call("route results stop at the reviewed return limit",
  bounded_routes.dig("data", "routes", "count") == 64 && bounded_routes.dig("data", "routes", "truncated") == true)

resolution = service.resolve(target: "Example.TEST")
check.call("one hostname resolution is normalized deduplicated and bounded",
  resolver_calls == ["example.test"] && resolution.dig("data", "addresses") == ["2001:db8::20", "192.0.2.20"])
bounded_dns = SoulCore::NetworkDiagnosticService.new(
  resolver: ->(_target) { (1..12).map { |index| "192.0.2.#{index}" } }
).resolve(target: "many.example")
check.call("DNS results stop at the reviewed return limit",
  bounded_dns.dig("data", "count") == 8 && bounded_dns.dig("data", "truncated") == true)
literal = service.resolve(target: "192.0.2.44")
check.call("IP literals complete without resolver access",
  resolver_calls.length == 1 && literal.dig("data", "addresses") == ["192.0.2.44"])

reachability = service.reachability(target: "example.test")
check.call("reachability uses one fixed argv-only ping template",
  ping_calls == [["/usr/bin/ping", "-n", "-c", "1", "-W", "2", "--", "example.test"]] &&
  reachability.dig("data", "reachable") == true &&
  reachability.dig("data", "attempts") == 1 &&
  reachability.dig("data", "latency_ms") == 1.25)

socket = service.socket(target: "example.test", port: 443)
check.call("socket diagnosis performs one bounded zero-payload connect",
  socket_calls == [["example.test", 443, 3]] &&
  socket.dig("data", "connected") == true &&
  socket.dig("data", "payload_bytes_sent") == 0 &&
  socket.dig("data", "attempts") == 1)

bad_targets = ["https://example.test", "192.0.2.0/24", "192.0.2.1-8", "999.999.999.999", "*.example.test", "-c", "one,two"]
blocked = bad_targets.map { |target| service.resolve(target: target) }
check.call("URL CIDR range wildcard option and multiple-target shapes fail closed",
  blocked.all? { |outcome| outcome["lifecycle_state"] == "blocked_for_human_review" })
bad_ports = [0, 65_536, "1-10", "443,444"]
check.call("port ranges lists and out-of-range ports fail closed",
  bad_ports.all? { |port| service.socket(target: "example.test", port: port)["lifecycle_state"] == "blocked_for_human_review" } && socket_calls.length == 1)

no_reply_service = SoulCore::NetworkDiagnosticService.new(
  ping_path: "/usr/bin/ping",
  ping_runner: ->(_argv) { ["", "", FakeStatus.new(1)] }
)
no_reply = no_reply_service.reachability(target: "192.0.2.55")
check.call("one missing reply remains terminal point-in-time evidence",
  no_reply["lifecycle_state"] == "complete" && no_reply.dig("data", "observation") == "no_reply")

refused_service = SoulCore::NetworkDiagnosticService.new(
  socket_connector: ->(_target, _port, _timeout) { raise Errno::ECONNREFUSED }
)
refused = refused_service.socket(target: "192.0.2.60", port: 22)
check.call("connection refusal is distinct zero-payload evidence",
  refused["lifecycle_state"] == "complete" && refused.dig("data", "observation") == "connection_refused" && refused.dig("data", "payload_bytes_sent") == 0)

controls = SoulCore::NetworkDiagnosticChatControls.new(service: service)
check.call("explicit network request grammar matches",
  ["diagnose local network", "resolve example.com", "ping 192.0.2.10", "check socket example.com port 443", "check port 443 on example.com"].all? { |text| controls.match?(text) })
check.call("ordinary networking conversation remains conversation",
  ["Networking is interesting", "I changed my router", "What is DNS?", "Could we build a network skill?"].none? { |text| controls.match?(text) })
rendered = controls.respond("resolve example.com")
check.call("Chat renders point-in-time and non-mutation boundaries",
  rendered.include?("DNS diagnosis for example.com") && rendered.include?("point-in-time") && rendered.include?("Mutation: none"))

orchestrator = SoulCore::ConversationOrchestrator.new
decision = orchestrator.plan(message: "check reachability to 192.0.2.10", provider_available: true)
discussion = orchestrator.plan(message: "I changed my router yesterday", provider_available: true)
check.call("explicit requests route deterministically while discussion does not",
  decision.kind == "deterministic_passthrough" && decision.flags["network_diagnostic_control"] == true &&
  !(discussion.flags["network_diagnostic_control"] rescue false))

facade = SoulCore::ApplicationFacade.new(root: Dir.pwd, network_diagnostic_service: service)
envelope = facade.call({
  "schema_version" => "soul.application.v1",
  "request_id" => "network-diagnose-a1-test",
  "operation" => "network.socket",
  "parameters" => { "target" => "example.test", "port" => 443 },
  "context" => { "interface" => "dashboard_test" }
})
check.call("application API returns one complete non-mutating envelope",
  envelope["lifecycle_state"] == "complete" && envelope.dig("meta", "mutation") == "none" && envelope.dig("data", "payload_bytes_sent") == 0)

shared = SoulCore::ChatResponder.new(root: Dir.pwd).respond("resolve 192.0.2.90")
check.call("shared Chat and Voice path exposes deterministic literal resolution",
  shared.include?("DNS diagnosis for 192.0.2.90") && shared.include?("Mutation: none"))

puts "Fundamental network.diagnose A1 verification:"
checks.each { |label| puts "PASS: #{label}" }
puts "#{checks.length} checks passed."
