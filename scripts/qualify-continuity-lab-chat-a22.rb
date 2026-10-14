#!/usr/bin/env ruby
# frozen_string_literal: true

require "timeout"
require_relative "../lib/soul_core/continuity_lab/chat_gateway"
require_relative "../lib/soul_core/continuity_lab/chat_executor"
require_relative "../lib/soul_core/continuity_lab/chat_application"

if $PROGRAM_NAME == __FILE__
  lab = SoulCore::ContinuityLab
  abort "Requires --approved-quiet-window (six synthetic generations, ten minutes maximum)" unless ARGV == ["--approved-quiet-window"]
  File.umask(0o077)
  root = File.expand_path("..", __dir__)
  base = File.join(root, "Soul/runtime/qualification")
  abort "Noncanonical qualification root" unless File.realpath(base) == base
  prior = Dir.glob(File.join(base, "**", "*"), File::FNM_DOTMATCH).select { |path| File.lstat(path).file? }
    .to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
  evidence = File.join(base, "continuity-lab-a22-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}")
  Dir.mkdir(evidence, 0o700)
  write = lambda do |name, value|
    File.open(File.join(evidence, name), File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
      file.write(lab.encode(value) + "\n")
      file.flush
      file.fsync
    end
  end
  $stdout.sync = true
  puts "Evidence: #{evidence}"
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  executor = lab::ChatExecutor.new(deadline: started + 580, max_generations: 6)
  records = []
  gateway, failure, idle = nil, nil, false
  histories = Hash.new { |hash, key| hash[key] = [] }
  token = "synthetic-a22-not-a-credential-000000"
  corpus = [{ "id" => "orchid-note", "content" => "The fictional blue parcel arrives on Tuesday. This is a synthetic test, not a real order." }]
  cases = [
    ["conversation-a", "Let's plan a quiet rainy afternoon. I prefer reading and tea to going out. Give two relaxed ideas."],
    ["conversation-a", "Actually, coffee rather than tea. Keep it indoors and pick one."],
    ["conversation-a", "What drink did I correct my preference to?"],
    ["conversation-b", "In the supplied orchid-note, what is the exact delivery day for the fictional blue parcel? Answer only the day."],
    ["conversation-b", "Does that record tell you who signed for it? If not, say you don't know."],
    ["conversation-c", "What drink did I ask you to remember in another conversation?"]
  ]
  begin
    Timeout.timeout(600) do
      executor.prepare!
      write.call("baseline.json", { "version" => lab::ChatGateway::VERSION, "host" => executor.observer.last_evidence,
        "config" => executor.config.to_h, "profile" => executor.profile,
        "code_hashes" => lab::ChatGateway.implementation_hashes, "cases" => cases, "corpus" => corpus,
        "prior_evidence" => prior, "limits" => { "new_generation_calls" => 6, "seconds" => 600 },
        "scope" => "synthetic_application_gateway_fresh_worker_live_qwen_not_librechat_ui" })
      state = File.join(evidence, "adapter")
      lab::ChatGateway.create(path: state, executor: executor, corpus: corpus)
      gateway = lab::ChatGateway.new(path: state, executor: executor)
      application = lab::ChatApplication.new(backend: gateway, bearer_token: token)
      cases.each_with_index do |(conversation, prompt), index|
        if index == 2
          gateway.close
          gateway = lab::ChatGateway.new(path: state, executor: executor)
          application = lab::ChatApplication.new(backend: gateway, bearer_token: token)
        end
        history = histories[conversation] + [{ "role" => "user", "content" => prompt }]
        input = { method: "POST", target: "/v1/chat/completions", headers: {
          "authorization" => "Bearer #{token}", "x-soul-conversation-id" => conversation },
          body: lab.encode("model" => lab::ChatGateway::MODEL, "messages" => history, "stream" => false) }
        turn_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        puts "START #{index + 1}/6 #{conversation}"
        response = application.call(**input)
        body = lab.parse(response.body)
        record = { "index" => index + 1, "conversation" => conversation, "prompt" => prompt,
          "seconds" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - turn_start,
          "status" => response.status, "body" => body,
          "worker" => executor.last_outcome, "broker_receipts" => executor.last_receipts }
        records << record
        write.call("case-#{index + 1}.json", record)
        raise lab::Error, "live request failed; retain state, no automatic retry" unless response.status == 200
        histories[conversation] = history + [body.fetch("choices").first.fetch("message")]
        before_retry = executor.last_outcome
        retry_response = application.call(**input)
        retry_body = lab.parse(retry_response.body)
        raise lab::IntegrityError, "retry did not recover durable reply" unless retry_response.status == 200 &&
          retry_body["id"] == body["id"] && retry_body["choices"] == body["choices"] &&
          retry_body.dig("soul", "replayed") == true && executor.last_outcome.equal?(before_retry)
        write.call("retry-#{index + 1}.json", { "same_id_and_reply" => true, "replayed" => true, "executor_not_called" => true })
        puts "COMPLETE #{index + 1}/6: #{record['seconds'].round(2)}s; retry recovered without inference"
      end
      executor.idle!
      idle = true
    end
  rescue StandardError, Interrupt => error
    failure = { "class" => error.class.name, "message" => error.message }
    puts "STOP #{failure}"
  ensure
    executor.cancel!
    gateway&.close
    changed = prior.keys.reject { |path| File.file?(path) && Digest::SHA256.file(path).hexdigest == prior.fetch(path) }
    summary = { "state" => failure ? "failed" : "complete", "failure" => failure,
      "seconds" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
      "completed_requests" => records.count { |record| record["status"] == 200 },
      "idle_verified" => idle == true, "historical_files_checked" => prior.length,
      "historical_changed" => changed, "semantic_assessment" => "requires_primary_transcript_review",
      "librechat_connected" => false, "listener_started" => false }
    write.call("summary.json", summary)
    puts lab.encode(summary)
  end
  exit(failure || !idle || !changed.empty? ? 1 : 0)
end
