#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require "timeout"
require "open3"
require "rbconfig"
require_relative "../lib/soul_core/reviewer/fake_runner"

R = SoulCore::Reviewer
L = SoulCore::ContinuityLab
checks = 0
check = lambda do |name, &block|
  raise "FAIL: #{name}" unless block.call
  checks += 1
  puts "ok: #{name}"
end
rejects = lambda do |*classes, &block|
  block.call
  false
rescue *classes
  true
end
request = lambda do |id = "review-1", now = 100|
  answer = "Synthetic answer"
  { "schema" => "soul.reviewer.request.v1", "review_id" => id, "source_event_id" => "event-1",
    "source_answer" => answer, "source_revision" => R::Contract.text_digest(answer),
    "evidence" => [], "evidence_revision" => R::Contract.digest([]), "question" => "Check answer",
    "constraints" => [], "rubric" => ["Use only the supplied evidence"],
    "validation_requirement" => "independent_required", "created_at" => now, "expires_at" => now + 1000 }
end
with_store = lambda do |&block|
  Dir.mktmpdir("reviewer-recovery-m1-") do |root|
    path = File.join(root, "reviews")
    store = R::Store.create(path: path)
    begin
      block.call(store, path, root)
    ensure
      store.close
    end
  end
end

check.call("runtime fingerprint binds contract, store and actual fake runner") do
  implementation = %w[contract.rb store.rb fake_runner.rb].to_h do |name|
    [name, Digest::SHA256.file(File.expand_path("../lib/soul_core/reviewer/#{name}", __dir__)).hexdigest]
  end
  original = R::Contract.digest(implementation)
  changed = R::Contract.digest(implementation.merge("fake_runner.rb" => "0" * 64))
  R::FakeRunner.runtime["implementation_sha256"] == original && changed != original
end

%i[before_write after_stage after_rename after_commit].each do |cut|
  with_store.call do |store, path, _|
    store.close
    store = R::Store.open(path: path, fault: ->(point, _) { raise IOError, "injected power loss" if point == cut })
    check.call("#{cut}: uncertain append refuses success") { rejects.call(L::IntegrityError) { store.enqueue(request.call, now: 100) } }
    store.close
    reopened = R::Store.open(path: path)
    expected = %i[after_rename after_commit].include?(cut) ? 1 : 0
    check.call("#{cut}: replay only committed record") { reopened.snapshot["reviews"].length == expected }
    check.call("#{cut}: abandoned stages retained, not silently removed") { Dir.children(path).grep(R::Store::STAGE).length == (cut == :after_stage ? 1 : 0) }
    # Idempotent resubmission never duplicates an already committed admission.
    reopened.enqueue(request.call, now: 100)
    check.call("#{cut}: exact retry admits at most once") { reopened.snapshot["sequence"] == 1 }
    reopened.close
  end
end

%i[after_rename after_commit].each do |cut|
  with_store.call do |store, path, _|
    store.enqueue(request.call, now: 100)
    store.close
    interrupted = R::Store.open(path: path, fault: lambda do |point, record|
      raise Interrupt if point == cut && record["kind"] == "completed"
    end)
    check.call("#{cut}: completion interruption preserves original signal") do
      rejects.call(Interrupt) { R::FakeRunner.new(store: interrupted).run(review_id: "review-1", now: 101, available: true) }
    end
    interrupted.close
    reopened = R::Store.open(path: path)
    check.call("#{cut}: interrupted acknowledged-or-not completion remains historical") { reopened.snapshot["reviews"]["review-1"]["status"] == "completed" }
    reopened.close
  end
end

with_store.call do |store, path, _|
  store.enqueue(request.call, now: 100)
  lease = store.lease(review_id: "review-1", now: 101)
  store.start(review_id: "review-1", attempt_id: lease["attempt_id"], now: 102)
  store.close
  faulty = R::Store.open(path: path, fault: ->(point, record) { raise IOError if point == :after_stage && record["kind"] == "completed" })
  response = { "review_id" => "review-1", "verdict" => "insufficient_evidence", "findings" => [], "omissions" => [] }
  check.call("partial completion is not acknowledged") do
    rejects.call(L::IntegrityError) { faulty.complete(review_id: "review-1", attempt_id: lease["attempt_id"], response: response, runtime: R::FakeRunner.runtime, now: 103) }
  end
  faulty.close
  reopened = R::Store.open(path: path)
  check.call("partial completion remains running, not completed") { reopened.snapshot["reviews"]["review-1"]["artifact"].nil? }
  check.call("explicit recovery marks unresolved expired work indeterminate") { reopened.recover(now: 132)["changed"] == ["review-1"] && reopened.snapshot["reviews"]["review-1"]["status"] == "indeterminate" }
  check.call("indeterminate work is never silently rerun") { rejects.call(L::Conflict) { R::FakeRunner.new(store: reopened).run(review_id: "review-1", now: 133, available: true) } }
  reopened.close
end

with_store.call do |store, path, _|
  store.close
  read, write = IO.pipe
  pid = fork do
    read.close
    child = R::Store.open(path: path, fault: lambda do |point, _|
      if point == :after_stage
        write.write("ready\n")
        write.flush
        sleep 30
      end
    end)
    child.enqueue(request.call, now: 100)
    exit! 1
  end
  write.close
  begin
    ready = Timeout.timeout(5) { read.gets }
    check.call("owned child reached durable staging") { ready == "ready\n" }
    contender = R::Store.open(path: path) rescue $!
    check.call("second process cannot read through occupied writer") { contender.is_a?(L::Busy) }
    Process.kill("KILL", pid)
    Process.wait(pid)
    pid = nil
    reopened = R::Store.open(path: path)
    check.call("SIGKILL releases OS lock but does not commit stage") { reopened.snapshot["sequence"] == 0 && Dir.children(path).grep(R::Store::STAGE).length == 1 }
    reopened.close
  ensure
    if pid
      Process.kill("KILL", pid) rescue nil
      Process.wait(pid) rescue nil
    end
    read.close
  end
end

with_store.call do |store, path, root|
  store.enqueue(request.call, now: 100)
  store.close
  commit = File.join(path, "commit-00000001.json")
  original = File.binread(commit)
  # Synthetic corruption, never a live journal.
  File.write(commit, original.sub("Synthetic answer", "Synthetic altered"))
  check.call("corrupt committed content rejected") { rejects.call(L::IntegrityError) { R::Store.open(path: path) } }
  File.write(commit, original)
  File.chmod(0o644, commit)
  check.call("public record permissions rejected") { rejects.call(L::IntegrityError) { R::Store.open(path: path) } }
  File.chmod(0o600, commit)
  File.link(commit, File.join(root, "alias"))
  check.call("hardlinked record rejected") { rejects.call(L::IntegrityError) { R::Store.open(path: path) } }
end

with_store.call do |store, path, root|
  store.close
  outside = File.join(root, "outside")
  File.write(outside, "{}\n", perm: 0o600)
  File.symlink(outside, File.join(path, "stage-#{'a' * 32}"))
  check.call("symlinked stage rejected without following it") { rejects.call(L::IntegrityError) { R::Store.open(path: path) } && File.read(outside) == "{}\n" }
end

with_store.call do |store, path, _|
  store.close
  File.write(File.join(path, "unexpected"), "x", perm: 0o600)
  check.call("unknown entry rejected") { rejects.call(L::IntegrityError) { R::Store.open(path: path) } }
end

with_store.call do |store, path, _|
  store.enqueue(request.call, now: 100)
  check.call("clock rollback refuses new mutation") { rejects.call(L::Conflict) { store.unavailable(review_id: "review-1", now: 99) } }
  store.close
  File.open(File.join(path, "stage-#{'b' * 32}"), "wb", 0o600) { |f| f.truncate(R::Store::MAX_RECORD_BYTES + 1) }
  check.call("oversized orphan staging fails closed") { rejects.call(L::IntegrityError) { R::Store.open(path: path) } }
end

with_store.call do |store, _, _|
  R::Store::MAX_REVIEWS.times { |i| store.enqueue(request.call("r-#{i}"), now: 100) }
  check.call("retained request count bounded including terminal records") { rejects.call(L::QuotaExceeded) { store.enqueue(request.call("overflow"), now: 100) } }
end

with_store.call do |store, path, _|
  store.enqueue(request.call, now: 100)
  check.call("queued expiry does not fabricate a review or validation") do
    store.recover(now: 1100)["changed"] == ["review-1"] && store.snapshot["reviews"]["review-1"]["status"] == "expired" &&
      store.snapshot["reviews"]["review-1"]["artifact"].nil?
  end
  check.call("expired queued request cannot begin a late fake attempt") { rejects.call(L::Conflict) { store.lease(review_id: "review-1", now: 1101) } }
  store.close
  check.call("create refuses to replace an existing populated root") { rejects.call(L::Conflict) { R::Store.create(path: path) } && File.exist?(File.join(path, "commit-00000002.json")) }
end

with_store.call do |store, _, _|
  store.enqueue(request.call, now: 100)
  attempt = store.lease(review_id: "review-1", now: 101)["attempt_id"]
  failed = store.fail(review_id: "review-1", attempt_id: attempt, reason: "fake_failure", now: 102)
  check.call("failed attempt is explicit and cannot be silently retried") do
    failed["status"] == "failed" && failed["artifact"].nil? && rejects.call(L::Conflict) { store.lease(review_id: "review-1", now: 103) }
  end
end

with_store.call do |store, path, _|
  store.enqueue(request.call, now: 100)
  store.close
  previous = L.parse(File.read(File.join(path, "commit-00000001.json")))
  (2..R::Store::MAX_RECORDS).each do |sequence|
    record = previous.merge("sequence" => sequence, "previous_digest" => previous["digest"],
      "kind" => "unavailable", "payload" => { "review_id" => "review-1" })
    record["digest"] = R::Contract.digest(record.reject { |key, _| key == "digest" })
    File.write(File.join(path, format("commit-%08d.json", sequence)), L.encode(record)+"\n", perm: 0o600)
    previous = record
  end
  reopened = R::Store.open(path: path)
  check.call("full bounded journal remains inspectable but refuses extra mutation") do
    reopened.snapshot["sequence"] == R::Store::MAX_RECORDS &&
      rejects.call(L::QuotaExceeded) { reopened.unavailable(review_id: "review-1", now: 100) }
  end
  reopened.close
end

with_store.call do |store, path, _|
  store.close
  count = R::Store::MAX_BYTES / R::Store::MAX_RECORD_BYTES + 1
  count.times do |i|
    File.open(File.join(path, "stage-#{format('%032x', i)}"), "wb", 0o600) { |f| f.truncate(R::Store::MAX_RECORD_BYTES) }
  end
  check.call("retained interrupted stages count against byte quota") { rejects.call(L::QuotaExceeded) { R::Store.open(path: path) } }
end

Dir.mktmpdir("reviewer-cli-m1-") do |root|
  path = File.join(root, "reviews")
  cli = File.expand_path("soul-reviewer", __dir__)
  run = lambda do |*args, input: ""|
    output, error, result = Open3.capture3(RbConfig.ruby, cli, *args, stdin_data: input)
    [L.parse(output), result.exitstatus, error]
  end
  check.call("CLI creates fake-only detached root") { run.call("init", path)[0]["mode"] == "detached_fake_only" }
  now = Time.now.to_i
  check.call("CLI admits bounded synthetic request") { run.call("enqueue", path, input: L.encode(request.call("cli-1", now)))[1] == 0 }
  unavailable = run.call("run-fake", path, "cli-1", "--unavailable")
  check.call("CLI unavailability retains independent-validation requirement") { unavailable[0]["task_disposition"] == "pending_independent_validation" && unavailable[0].dig("review", "status") == "queued" }
  complete = run.call("run-fake", path, "cli-1")
  check.call("CLI fake completion explicitly is not validation") { complete[0]["status"] == "completed" && complete[0]["task_disposition"] == "pending_independent_validation" && complete[0].dig("review", "artifact", "semantic_review_performed") == false }
  current = request.call("cli-1", now)
  stale = run.call("status", path, "cli-1", R::Contract.text_digest("new answer"), current["evidence_revision"])
  check.call("CLI freshness inspection preserves historical completion") { stale[0].dig("review", "freshness") == "stale" && stale[0].dig("review", "status") == "completed" }
  check.call("CLI exact request retry remains completed") { run.call("enqueue", path, input: L.encode(current))[0].dig("review", "status") == "completed" }
  check.call("CLI unsupported provider command cannot launch model") { run.call("run-amd", path, "cli-1")[1] == 2 }
  check.call("CLI rejects duplicate JSON keys") { run.call("enqueue", path, input: '{"review_id":"a","review_id":"b"}')[1] == 2 }
  check.call("CLI explicit recovery does not replay completed work") { run.call("recover", path)[0].dig("recovery", "changed") == [] }
end

puts "#{checks} reviewer recovery/CLI checks passed"
