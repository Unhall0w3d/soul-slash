#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/chat_responder"
require_relative "../lib/soul_core/conversation_orchestrator"
require_relative "../lib/soul_core/repository_inspection_chat_controls"
require_relative "../lib/soul_core/repository_inspection_service"

checks = []
check = lambda do |label, condition|
  raise label unless condition
  checks << label
end

Result = SoulCore::RepositoryInspectionService::CommandResult

Dir.mktmpdir("soul-repository-inspect-") do |repository|
  git = lambda do |*args|
    stdout, stderr, status = Open3.capture3({ "GIT_AUTHOR_NAME" => "Soul Test", "GIT_AUTHOR_EMAIL" => "soul@example.invalid", "GIT_COMMITTER_NAME" => "Soul Test", "GIT_COMMITTER_EMAIL" => "soul@example.invalid" }, "/usr/bin/git", *args, chdir: repository)
    raise "git #{args.join(' ')} failed: #{stderr}" unless status.success?
    stdout
  end
  git.call("init", "-q", "-b", "main")
  File.write(File.join(repository, "README.md"), "initial\n")
  git.call("add", "README.md")
  git.call("commit", "-q", "-m", "Initial fixture")
  File.write(File.join(repository, "README.md"), "initial\nworking change\n")
  File.write(File.join(repository, "notes.txt"), "staged note\n")
  git.call("add", "notes.txt")

  before_head = git.call("rev-parse", "HEAD").strip
  before_status = git.call("status", "--porcelain=v1", "-z")
  service = SoulCore::RepositoryInspectionService.new(
    root: repository,
    process_env: { "SOUL_REPOSITORY_INSPECT_ROOTS" => "fixture=." },
    clock: -> { Time.utc(2026, 8, 2, 20, 0, 0) }
  )

  roots = service.roots
  check.call("configured repository listing exposes IDs without paths",
    roots["lifecycle_state"] == "complete" && roots.dig("data", "roots") == [{ "root_id" => "fixture", "available" => true }] && !JSON.generate(roots).include?(repository))

  inspection = service.inspect(root_id: "fixture")
  data = inspection.fetch("data")
  check.call("one repository snapshot returns branch HEAD status log and both diff scopes",
    inspection["lifecycle_state"] == "complete" && data["branch"] == "main" && data["head"] == before_head &&
    data.dig("status", "count") == 2 && data.fetch("recent_commits").first.fetch("subject") == "Initial fixture" &&
    data.dig("diff", "worktree", "content").include?("working change") && data.dig("diff", "staged", "content").include?("staged note"))
  check.call("repository evidence is explicitly untrusted and non-mutating",
    data["content_trusted"] == false && data["authority"] == "reference_only" && inspection["mutation"] == "none")
  check.call("live inspection leaves HEAD and status byte-for-byte unchanged",
    git.call("rev-parse", "HEAD").strip == before_head && git.call("status", "--porcelain=v1", "-z") == before_status)

  shared = SoulCore::RepositoryInspectionChatControls.new(service: service)
  check.call("exact repository request grammar matches",
    ["show approved repository roots", "inspect repository root fixture"].all? { |text| shared.match?(text) })
  check.call("ordinary repository conversation remains conversation",
    ["I am working in a repository", "What is Git?", "Could we add repository inspection?", "commit this change"].none? { |text| shared.match?(text) })
  rendered = shared.respond("inspect repository root fixture")
  check.call("Chat renders point-in-time untrusted and non-mutation boundaries",
    rendered.include?("Approved repository inspection complete") && rendered.include?("point-in-time") && rendered.include?("Mutation: none"))

  facade = SoulCore::ApplicationFacade.new(root: repository, repository_inspection_service: service)
  envelope = facade.call({
    "schema_version" => "soul.application.v1",
    "request_id" => "repository-inspect-a1-test",
    "operation" => "repository.inspect",
    "parameters" => { "root_id" => "fixture" },
    "context" => { "interface" => "dashboard_test" }
  })
  check.call("application API returns one complete non-mutating envelope",
    envelope["lifecycle_state"] == "complete" && envelope.dig("meta", "mutation") == "none" && envelope.dig("data", "branch") == "main")

  orchestrator = SoulCore::ConversationOrchestrator.new
  decision = orchestrator.plan(message: "inspect repository root fixture", provider_available: true)
  discussion = orchestrator.plan(message: "I changed a repository yesterday", provider_available: true)
  check.call("explicit requests route deterministically while discussion does not",
    decision.kind == "deterministic_passthrough" && decision.flags["repository_inspection_control"] == true &&
    !(discussion.flags["repository_inspection_control"] rescue false))

  unknown = service.inspect(root_id: "other")
  check.call("unknown repository authority stops for input without path disclosure",
    unknown["lifecycle_state"] == "awaiting_input" && !JSON.generate(unknown).include?(repository))

  nested_service = SoulCore::RepositoryInspectionService.new(
    root: repository,
    process_env: { "SOUL_REPOSITORY_INSPECT_ROOTS" => "nested=docs" }
  )
  FileUtils.mkdir_p(File.join(repository, "docs"))
  check.call("configured paths must be the exact Git top level",
    nested_service.inspect(root_id: "nested")["lifecycle_state"] == "blocked_for_human_review")

  symlink = File.join(File.dirname(repository), "repository-link")
  File.symlink(repository, symlink)
  linked_service = SoulCore::RepositoryInspectionService.new(
    root: repository,
    process_env: { "SOUL_REPOSITORY_INSPECT_ROOTS" => "linked=#{symlink}" }
  )
  check.call("symlink repository roots fail closed",
    linked_service.inspect(root_id: "linked")["lifecycle_state"] == "blocked_for_human_review")
  FileUtils.rm_f(symlink)
end

Dir.mktmpdir("soul-repository-fake-") do |repository|
  commands = []
  status_entries = (1..105).map { |index| " M file#{index}.txt\0" }.join + " M .env\0"
  log_lines = (1..12).map { |index| "#{format('%040x', index)}\t#{format('%07x', index)}\t2026-08-02T20:00:00+00:00\tTester\tCommit #{index}\n" }.join
  runner = lambda do |argv, chdir:, max_bytes:, timeout:|
    commands << { argv: argv, chdir: chdir, max_bytes: max_bytes, timeout: timeout }
    tail = argv.drop(6)
    stdout = case
             when tail == %w[rev-parse --show-toplevel] then "#{repository}\n"
             when tail == %w[rev-parse --verify HEAD] then "#{'a' * 40}\n"
             when tail == %w[symbolic-ref --quiet --short HEAD] then "feature/test\n"
             when tail.first(2) == %w[status --porcelain=v1] then status_entries
             when tail.first == "log" then log_lines
             when tail.first == "diff" then "diff --git a/file.txt b/file.txt\n+bounded\n"
             else ""
             end
    Result.new(stdout: stdout, stderr: "", success: true, truncated: false, timed_out: false)
  end
  service = SoulCore::RepositoryInspectionService.new(
    root: repository,
    process_env: { "SOUL_REPOSITORY_INSPECT_ROOTS" => "fixture=." },
    command_runner: runner,
    git_path: "/usr/bin/git"
  )
  bounded = service.inspect(root_id: "fixture")
  check.call("status and log results stop at reviewed limits",
    bounded.dig("data", "status", "count") == 100 && bounded.dig("data", "status", "truncated") == true && bounded.dig("data", "recent_commits").length == 10)
  check.call("secret-shaped status paths are omitted",
    bounded.dig("data", "status", "entries").none? { |entry| entry.fetch("path").include?(".env") })
  check.call("all Git execution is fixed absolute argv-only read plumbing",
    commands.all? { |call| call.fetch(:argv).first == "/usr/bin/git" && call.fetch(:argv).include?("--no-pager") && call.fetch(:argv).include?("core.fsmonitor=false") && call.fetch(:timeout) == 5 } &&
    commands.none? { |call| (call.fetch(:argv) & %w[checkout switch restore reset clean add commit tag stash merge rebase fetch pull push]).any? })
  diff_commands = commands.select { |call| call.fetch(:argv).include?("diff") }
  check.call("diff commands disable extension points and exclude secret path shapes",
    diff_commands.length == 2 && diff_commands.all? { |call| call.fetch(:argv).include?("--no-ext-diff") && call.fetch(:argv).include?("--no-textconv") && call.fetch(:argv).any? { |arg| arg.include?(".env") } })

  credential_runner = lambda do |argv, chdir:, max_bytes:, timeout:|
    tail = argv.drop(6)
    stdout = if tail == %w[rev-parse --show-toplevel]
               "#{repository}\n"
             elsif tail == %w[rev-parse --verify HEAD]
               "#{'b' * 40}\n"
             elsif tail.first == "diff"
               "-----BEGIN PRIVATE KEY-----\n"
             else
               ""
             end
    Result.new(stdout: stdout, stderr: "", success: true, truncated: false, timed_out: false)
  end
  withheld = SoulCore::RepositoryInspectionService.new(
    root: repository,
    process_env: { "SOUL_REPOSITORY_INSPECT_ROOTS" => "fixture=." },
    command_runner: credential_runner,
    git_path: "/usr/bin/git"
  ).inspect(root_id: "fixture")
  check.call("credential-like diff content is withheld rather than returned",
    withheld.dig("data", "diff", "worktree", "withheld") == true && !JSON.generate(withheld).include?("BEGIN PRIVATE KEY"))

  invalid_runner = lambda do |argv, chdir:, max_bytes:, timeout:|
    tail = argv.drop(6)
    stdout = if tail == %w[rev-parse --show-toplevel]
               "#{repository}\n"
             elsif tail == %w[rev-parse --verify HEAD]
               "#{'c' * 40}\n"
             elsif tail.first == "diff"
               "diff\n\xFF".b
             else
               ""
             end
    Result.new(stdout: stdout, stderr: "", success: true, truncated: false, timed_out: false)
  end
  invalid = SoulCore::RepositoryInspectionService.new(
    root: repository,
    process_env: { "SOUL_REPOSITORY_INSPECT_ROOTS" => "fixture=." },
    command_runner: invalid_runner,
    git_path: "/usr/bin/git"
  ).inspect(root_id: "fixture")
  check.call("non-UTF-8 diff content is withheld safely",
    invalid.dig("data", "diff", "worktree", "withheld") == true && JSON.generate(invalid).valid_encoding?)

  timeout_runner = lambda do |_argv, chdir:, max_bytes:, timeout:|
    Result.new(stdout: "", stderr: "", success: false, truncated: false, timed_out: true)
  end
  timed = SoulCore::RepositoryInspectionService.new(
    root: repository,
    process_env: { "SOUL_REPOSITORY_INSPECT_ROOTS" => "fixture=." },
    command_runner: timeout_runner,
    git_path: "/usr/bin/git"
  ).inspect(root_id: "fixture")
  check.call("command timeout terminates as blocked review state",
    timed["lifecycle_state"] == "blocked_for_human_review")
end

puts "Fundamental repository.inspect A1 verification:"
checks.each { |label| puts "PASS: #{label}" }
puts "#{checks.length} checks passed."
