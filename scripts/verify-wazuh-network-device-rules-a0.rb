#!/usr/bin/env ruby
# frozen_string_literal: true

require "rexml/document"

root = File.expand_path("..", __dir__)
decoder_path = File.join(root, "deploy/wazuh/vigil/soul-network-device-decoders.xml")
rule_path = File.join(root, "deploy/wazuh/vigil/soul-network-device-rules.xml")

decoder_body = File.read(decoder_path)
rule_body = File.read(rule_path)
REXML::Document.new("<root>#{decoder_body}</root>")
rules = REXML::Document.new(rule_body)

def check(label, condition)
  raise "FAIL: #{label}" unless condition
  puts "- #{label}: ok"
end

ids = []
REXML::XPath.each(rules, "//rule") { |rule| ids << rule.attributes["id"] }
check("custom rule IDs preserve correlation precedence", ids == %w[100100 100101 100102 100103])
check("decoder uses one vendor-signature stage",
      decoder_body.scan('<decoder name="soul-network-device">').length == 1 &&
      !decoder_body.include?("<parent>"))
check("decoder requires the fixed network-device envelope",
      decoder_body.include?("%[A-Z0-9]+-[A-Z]-[A-Z0-9]+:"))

sample_pattern = /^\s*(\d{1,3}(?:\.\d{1,3}){3}) %([A-Z0-9]+)-([A-Z])-([A-Z0-9]+): (.*)$/
loom = "192.168.124.11 %AAA-I-DISCONNECT: http connection terminated"
lattice = "192.168.124.10 %SYSTEM-W-LOGINFAIL: authentication rejected"
check("representative Loom and Lattice envelopes parse exactly",
      loom.match(sample_pattern)&.captures&.first(4) == %w[192.168.124.11 AAA I DISCONNECT] &&
      lattice.match(sample_pattern)&.captures&.first(4) == %w[192.168.124.10 SYSTEM W LOGINFAIL])
check("routine events remain low severity", rule_body.include?('<rule id="100100" level="3">'))
check("warning and error events are elevated without overlapping SNMP authentication",
      rule_body.include?('<rule id="100103" level="7">') &&
      rule_body.include?("%(?!SNMP-W-SNMPAUTHFAIL:)[A-Z0-9]+-[WE]-[A-Z0-9]+:"))
check("individual SNMP authentication failures are counting-only",
      rule_body.include?('<rule id="100101" level="1">') && rule_body.include?("below the alert threshold"))
check("SNMP authentication repetition is bounded", rule_body.include?('<rule id="100102" level="8" frequency="2" timeframe="900" ignore="900">') && rule_body.include?("<if_matched_sid>100101</if_matched_sid>"))
check("candidate adds no response or notification authority", !rule_body.match?(/active.response|command|email|notification/i))

puts "Wazuh network-device rules A0 static verification passed."
