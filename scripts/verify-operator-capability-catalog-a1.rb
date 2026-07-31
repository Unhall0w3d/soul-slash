#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/operator_capability_catalog"

ROOT = File.expand_path("..", __dir__)
checks = {}
check = ->(name, value) { checks[name] = value == true }

catalog = SoulCore::OperatorCapabilityCatalog.new(root: ROOT)
surfaces = catalog.surfaces
registry = YAML.safe_load_file(File.join(ROOT, "Soul/skills/registry.yaml"), permitted_classes: [], aliases: false).fetch("skills")
invocations = YAML.safe_load_file(File.join(ROOT, "config/invocation_catalog.yaml"), permitted_classes: [], aliases: false)
  .fetch("entries").map { |entry| entry.fetch("id") }

check.call("catalog is bounded and uniquely identified",
           surfaces.length.between?(10, SoulCore::OperatorCapabilityCatalog::MAX_SURFACES) &&
             surfaces.map { |surface| surface["id"] }.uniq.length == surfaces.length)
check.call("every declared application operation exists",
           surfaces.flat_map { |surface| surface["operations"] }.all? { |operation| SoulCore::ApplicationContract::OPERATIONS.key?(operation) })
check.call("every declared production skill exists",
           surfaces.flat_map { |surface| surface["skills"] }.all? { |skill_id| registry.key?(skill_id) })
check.call("every declared invocation exists",
           surfaces.flat_map { |surface| surface["invocations"] }.all? { |invocation_id| invocations.include?(invocation_id) })
check.call("all surfaces declare dashboard chat and voice coverage",
           surfaces.all? { |surface| surface["coverage"].keys.sort == %w[chat dashboard voice] })

maintenance = catalog.find("guided_maintenance")
check.call("routine maintenance is mapped to the existing fixed controller",
           maintenance["skills"] == ["maintenance.device"] &&
             maintenance["operations"].include?("maintenance.device.execute") &&
             maintenance.dig("authority", "conversational_confirmation") == ["device package maintenance"])
check.call("maintenance reboot and workstation mutation remain protected",
           maintenance.dig("authority", "operator_gesture_required").sort == ["reboot", "workstation maintenance"].sort)

backups = catalog.find("backup_and_recovery")
publication = catalog.find("youtube_publication")
skill_studio = catalog.find("skill_studio")
check.call("destructive and external workflows retain Operator gestures",
           backups.dig("authority", "operator_gesture_required").include?("snapshot deletion") &&
             publication.dig("authority", "operator_gesture_required").include?("publication") &&
             skill_studio.dig("authority", "operator_gesture_required").include?("promotion"))

guide_source = File.read(File.join(ROOT, "lib/soul_core/dashboard_capability_guide.rb"))
check.call("dashboard self-recognition consumes the shared catalog",
           guide_source.include?("OperatorCapabilityCatalog") && !guide_source.include?("SURFACES ="))

failed = checks.reject { |_name, passed| passed }
puts "Operator capability catalog A1 verification:"
checks.each { |name, passed| puts "- #{name}: #{passed ? 'ok' : 'missing'}" }
abort("#{failed.length} operator capability catalog checks failed") unless failed.empty?
puts "Operator capability catalog A1 verification passed."
