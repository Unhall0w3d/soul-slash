#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/chat_responder"
require_relative "../lib/soul_core/conversation_orchestrator"
require_relative "../lib/soul_core/file_inspection_chat_controls"
require_relative "../lib/soul_core/file_inspection_service"

checks = []

def check(checks, label, condition)
  raise label unless condition
  checks << label
end

Dir.mktmpdir("soul-files-inspect-") do |root|
  FileUtils.mkdir_p(File.join(root, "docs"))
  File.write(File.join(root, "README.md"), "# Example\n\nSafe reference text.\n")
  File.write(File.join(root, "docs", "guide.md"), "# Guide\n\nBounded content.\n")
  File.write(File.join(root, "docs", ".hidden.md"), "hidden\n")
  File.write(File.join(root, ".env"), "TOKEN=not-returned\n")
  File.write(File.join(root, "secret.pem"), "not-returned\n")
  File.write(File.join(root, "credentials.txt"), "not-returned\n")
  File.write(File.join(root, "private-key.txt"), "-----BEGIN PRIVATE KEY-----\nexample\n")
  File.binwrite(File.join(root, "binary.bin"), "\x00\x01")
  File.write(File.join(root, "large.md"), "x" * (SoulCore::FileInspectionService::MAX_READ_BYTES + 1))
  File.symlink("README.md", File.join(root, "linked.md"))
  File.symlink("docs", File.join(root, "linked-docs"))
  before = Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).sort.to_h do |path|
    [path.delete_prefix("#{root}/"), File.lstat(path).then { |stat| [stat.mode, stat.size, stat.mtime.to_f] }]
  end

  environment = { "SOUL_FILES_INSPECT_ROOTS" => "project=.;docs=#{File.join(root, 'docs')}" }
  service = SoulCore::FileInspectionService.new(root: root, process_env: environment, clock: -> { Time.utc(2026, 8, 2, 12, 0, 0) })

  roots = service.roots
  check(checks, "only configured root IDs are exposed", roots["lifecycle_state"] == "complete" && roots.dig("data", "roots").map { |entry| entry["root_id"] } == %w[project docs] && !roots.to_s.include?(root))

  listing = service.list(root_id: "project", relative_path: ".")
  names = listing.dig("data", "entries").map { |entry| entry["name"] }
  check(checks, "listing is one-level bounded and omits protected entries", listing["lifecycle_state"] == "complete" && names.include?("README.md") && names.include?("docs") && (names & %w[.env secret.pem credentials.txt linked.md linked-docs]).empty?)

  stat = service.stat(root_id: "project", relative_path: "README.md")
  check(checks, "stat returns exact non-symlink metadata", stat["lifecycle_state"] == "complete" && stat.dig("data", "entry", "type") == "file" && stat.dig("data", "entry", "bytes") == File.size(File.join(root, "README.md")))

  read = service.read(root_id: "project", relative_path: "README.md")
  check(checks, "read returns bounded untrusted text with digest", read["lifecycle_state"] == "complete" && read.dig("data", "content").include?("Safe reference text") && read.dig("data", "sha256").match?(/\A[a-f0-9]{64}\z/) && read.dig("data", "content_trusted") == false)

  check(checks, "unknown roots await an exact configured ID", service.read(root_id: "unknown", relative_path: "README.md")["lifecycle_state"] == "awaiting_input")
  check(checks, "absolute and traversal paths fail closed", service.read(root_id: "project", relative_path: "/etc/hosts")["lifecycle_state"] == "blocked_for_human_review" && service.read(root_id: "project", relative_path: "../outside.md")["lifecycle_state"] == "blocked_for_human_review")
  check(checks, "hidden and secret-bearing names fail closed", service.read(root_id: "project", relative_path: ".env")["lifecycle_state"] == "blocked_for_human_review" && service.read(root_id: "project", relative_path: "secret.pem")["lifecycle_state"] == "blocked_for_human_review" && service.read(root_id: "project", relative_path: "credentials.txt")["lifecycle_state"] == "blocked_for_human_review")
  check(checks, "symlink traversal fails closed", service.read(root_id: "project", relative_path: "linked.md")["lifecycle_state"] == "blocked_for_human_review" && service.list(root_id: "project", relative_path: "linked-docs")["lifecycle_state"] == "blocked_for_human_review")
  check(checks, "binary oversized and credential content fail closed", service.read(root_id: "project", relative_path: "binary.bin")["lifecycle_state"] == "blocked_for_human_review" && service.read(root_id: "project", relative_path: "large.md")["lifecycle_state"] == "blocked_for_human_review" && service.read(root_id: "project", relative_path: "private-key.txt")["lifecycle_state"] == "blocked_for_human_review")

  after_service = Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).sort.to_h do |path|
    [path.delete_prefix("#{root}/"), File.lstat(path).then { |entry| [entry.mode, entry.size, entry.mtime.to_f] }]
  end
  check(checks, "all service inspection paths leave the approved roots unchanged", before == after_service)

  controls = SoulCore::FileInspectionChatControls.new(root: root, service: service)
  check(checks, "explicit approved-root wording matches", controls.match?("Read file from root project at README.md") && controls.match?("Show approved file roots"))
  check(checks, "ordinary file conversation does not match", !controls.match?("I read a file about our project yesterday.") && !controls.match?("Could you look around my home directory?"))
  rendered = controls.respond("Read file from root project at README.md")
  check(checks, "chat renders source and non-mutation boundary", rendered.include?("Safe reference text") && rendered.include?("Lifecycle: complete. Mutation: none."))

  orchestrator = SoulCore::ConversationOrchestrator.new
  routed = orchestrator.plan(message: "List files in root project at docs", provider_available: true)
  discussion = orchestrator.plan(message: "I reorganized the files in this project.", provider_available: true)
  check(checks, "explicit request routes deterministically", routed.kind == "deterministic_passthrough" && routed.flags["file_inspection_control"] == true && routed.requires_model == false)
  check(checks, "topical discussion remains conversation", discussion.flags["file_inspection_control"] != true)

  responder = SoulCore::ChatResponder.new(root: root)
  response = responder.respond("Stat file in root project at README.md")
  check(checks, "shared Chat path exposes the bounded handler", response.include?("Approved path inspection complete") && response.include?("Mutation: none"))

  facade = SoulCore::ApplicationFacade.new(root: root, process_env: environment, file_inspection_service: service)
  envelope = facade.call({
    "schema_version" => "soul.application.v1",
    "request_id" => "files-inspect-a1-test",
    "operation" => "files.read",
    "parameters" => { "root_id" => "project", "relative_path" => "README.md" },
    "context" => { "interface" => "dashboard_test" }
  })
  check(checks, "application API returns a complete non-mutating envelope", envelope["lifecycle_state"] == "complete" && envelope.dig("meta", "mutation") == "none" && envelope.dig("data", "content").include?("Safe reference text"))

end

puts "Fundamental files.inspect A1 verification:"
checks.each { |label| puts "PASS: #{label}" }
puts "#{checks.length} checks passed."
