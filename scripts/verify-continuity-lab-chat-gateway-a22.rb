#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require "timeout"
require_relative "../lib/soul_core/continuity_lab/chat_gateway"
require_relative "../lib/soul_core/continuity_lab/runtime"

Lab = SoulCore::ContinuityLab

class A22GatewayFixtureExecutor
  attr_reader :config, :profile, :backend, :calls

  def initialize(config: Lab::Config.new("context_mode" => "explicit_v1"), responses: nil,
                 before_run: nil, after_run: nil, held_run: nil)
    @config = config
    @profile = "fixture_a22"
    @backend = Lab::FakeBackend.new(responses: responses || Array.new(16, '{"action":"reply","content":"durable answer"}'))
    @before_run, @after_run, @held_run = before_run, after_run, held_run
    @calls = 0
  end

  def run(state_directory:, event_id:, content:)
    @calls += 1
    @before_run&.call
    @held_run&.call
    store = Lab::Store.open(path: File.join(state_directory, "store"), config: config)
    Lab::Runtime.new(store: store, backend: backend).submit(event_id: event_id, content: content)
  ensure
    store&.close
    @after_run&.call
  end
end

module VerifyContinuityLabChatGatewayA22
  module_function

  def check(name, count)
    raise "FAIL: #{name}" unless yield

    count[0] += 1
    puts "PASS: #{name}"
  rescue StandardError => error
    count[1] << [name, error.class, error.message]
    puts "FAIL: #{name} (#{error.class}: #{error.message})"
  end

  def raises(error_class)
    yield
    false
  rescue error_class
    true
  end

  def config
    Lab::Config.new("context_mode" => "explicit_v1")
  end

  def messages(content)
    [{ "role" => "user", "content" => content }]
  end

  def transcript(content, answer)
    [{ "role" => "user", "content" => content }, { "role" => "assistant", "content" => answer }]
  end

  def gateway(root, executor)
    Lab::ChatGateway.create(path: root, executor: executor)
    Lab::ChatGateway.new(path: root, executor: executor)
  end

  def with_directory_write_override(override)
    directory_class = Lab::ChatGateway::Directory
    original_write = directory_class.instance_method(:write)
    directory_class.define_method(:write) do |name, data|
      override.call(self, name, data, original_write)
    end
    yield
  ensure
    directory_class.define_method(:write, original_write)
  end

  def session_path(root, conversation_id)
    File.join(root, "c-#{Digest::SHA256.hexdigest(conversation_id)}")
  end

  def run
    checks = [0, []]
    Dir.mktmpdir("soul-a22-gateway-") do |temporary|
      root = File.join(temporary, "adapter")
      executor = A22GatewayFixtureExecutor.new
      adapter = gateway(root, executor)

      first = adapter.complete(conversation_id: "fixture-a22", messages: messages("First question?"))
      check("create succeeds below the fresh owner-private fixture parent", checks) do
        first["content"] == "durable answer" && first.dig("soul", "event_id") == "turn-0001" &&
          File.stat(File.dirname(root)).mode & 0o777 == 0o700 && File.stat(root).mode & 0o777 == 0o700 &&
          executor.calls == 1 && executor.backend.calls == 1
      end
      duplicate = adapter.complete(conversation_id: "fixture-a22", messages: messages("First question?"))
      check("same-content retry returns the same durable reply without another executor call", checks) do
        duplicate["content"] == first["content"] && duplicate["id"] == first["id"] &&
          duplicate.dig("soul", "replayed") == true && executor.calls == 1 && executor.backend.calls == 1
      end

      second = adapter.complete(conversation_id: "fixture-a22", messages: transcript("First question?", "durable answer") + messages("Next question?"))
      check("next turn validates complete history and advances the conversation journal", checks) do
        second["content"] == "durable answer" && second.dig("soul", "event_id") == "turn-0002" &&
          second.dig("soul", "lineage_id") == first.dig("soul", "lineage_id") && executor.backend.calls == 2
      end
      check("edits, incomplete histories, and imported histories conflict without execution", checks) do
        before = executor.backend.calls
        edits = raises(Lab::Conflict) { adapter.complete(conversation_id: "fixture-a22", messages: messages("Changed question?")) }
        mismatch = raises(Lab::Conflict) do
          adapter.complete(conversation_id: "fixture-a22", messages: transcript("First question?", "edited answer") + messages("Third?"))
        end
        import = raises(Lab::Conflict) { adapter.complete(conversation_id: "fixture-a22", messages: transcript("foreign", "history") + messages("Fourth?")) }
        edits && mismatch && import && executor.backend.calls == before
      end

      separate = adapter.complete(conversation_id: "fixture-a22-other", messages: messages("First question?"))
      check("separate conversation identifiers receive independent journal lineages", checks) do
        separate.dig("soul", "lineage_id") != first.dig("soul", "lineage_id") && executor.backend.calls == 3
      end
      adapter.close
      reopened_executor = A22GatewayFixtureExecutor.new
      reopened = Lab::ChatGateway.new(path: root, executor: reopened_executor)
      recovered = reopened.complete(conversation_id: "fixture-a22", messages: messages("First question?"))
      check("close, reopen, and retry recover the same durable reply without a new model call", checks) do
        recovered["id"] == first["id"] && recovered["content"] == first["content"] &&
          recovered.dig("soul", "replayed") && reopened_executor.calls.zero? && reopened_executor.backend.calls.zero?
      end

      before = reopened_executor.calls
      invalid_inputs = [
        ["bad/id", messages("x")], ["new", messages("x")], ["fixture-a22", []],
        ["fixture-a22", transcript("x", "y")], ["fixture-a22", [{ "role" => "system", "content" => "x" }]],
        ["fixture-a22", [{ "role" => "user", "content" => "" }]],
        ["fixture-a22", [{ "role" => "user", "content" => "x", "path" => "/tmp" }]],
        ["fixture-a22", [{ "role" => "user", "content" => "x" * 16_385 }]],
        ["fixture-a22", Array.new(65) { |index| { "role" => index.even? ? "user" : "assistant", "content" => "x" } }]
      ]
      strict = invalid_inputs.all? do |id, rows|
        raises(Lab::ValidationError) { reopened.complete(conversation_id: id, messages: rows) }
      end
      check("strict input validation rejects identifiers, shape, role, text, and turn bounds", checks) do
        strict && reopened_executor.calls == before
      end

      reopened.close
      drift = A22GatewayFixtureExecutor.new(config: Lab::Config.new("context_mode" => "explicit_v1", "max_event_bytes" => 8192))
      check("configuration drift is rejected on reopen", checks) do
        raises(Lab::IntegrityError) { Lab::ChatGateway.new(path: root, executor: drift) }
      end

      Dir.mktmpdir("soul-a22-gateway-binding-") do |binding_parent|
        binding_root = File.join(binding_parent, "adapter")
        binding_executor = A22GatewayFixtureExecutor.new
        binding_adapter = gateway(binding_root, binding_executor)
        binding_adapter.close
        manifest = File.join(binding_root, "adapter.json")
        decoded = Lab.parse(File.read(manifest))
        decoded["corpus"] = [{ "id" => "drift", "content" => "different source" }]
        File.write(manifest, Lab.encode(decoded) + "\n")
        File.chmod(0o600, manifest)
        check("corpus binding drift is rejected before requests", checks) do
          raises(Lab::IntegrityError) { Lab::ChatGateway.new(path: binding_root, executor: binding_executor) }
        end
      end

      unprivate_parent = File.join(temporary, "unprivate-parent")
      Dir.mkdir(unprivate_parent, 0o755)
      unprivate_target = File.join(unprivate_parent, "adapter")
      check("create rejects a 0755 parent without creating its target", checks) do
        raises(Lab::IntegrityError) { Lab::ChatGateway.create(path: unprivate_target, executor: A22GatewayFixtureExecutor.new) } &&
          !File.exist?(unprivate_target) && !File.symlink?(unprivate_target)
      end

      symlink_parent_real = File.join(temporary, "private-real-parent")
      Dir.mkdir(symlink_parent_real, 0o700)
      symlink_parent = File.join(temporary, "parent-link")
      File.symlink(symlink_parent_real, symlink_parent)
      symlink_target = File.join(symlink_parent, "adapter")
      check("create rejects a symlink parent without creating the target", checks) do
        raises(Lab::IntegrityError) { Lab::ChatGateway.create(path: symlink_target, executor: A22GatewayFixtureExecutor.new) } &&
          !File.exist?(symlink_target) && !File.symlink?(symlink_target) && Dir.empty?(symlink_parent_real)
      end

      interrupted_parent = File.join(temporary, "interrupted-parent")
      Dir.mkdir(interrupted_parent, 0o700)
      interrupted_target = File.join(interrupted_parent, "adapter")
      injected = false
      injected_write = lambda do |directory, name, data, original_write|
        if name == "lock" && File.basename(directory.path).match?(/\Astage-[a-f0-9]{32}\z/)
          injected = true
          raise IOError, "synthetic initialization write failure"
        end
        original_write.bind(directory).call(name, data)
      end
      with_directory_write_override(injected_write) do
        raises(IOError) { Lab::ChatGateway.create(path: interrupted_target, executor: A22GatewayFixtureExecutor.new) }
      end
      interrupted_stages = Dir.children(interrupted_parent).grep(/\Astage-[a-f0-9]{32}\z/)
      check("failed staged initialization retains its sibling stage and publishes no final root", checks) do
        injected && !File.exist?(interrupted_target) && interrupted_stages.length == 1 &&
          File.file?(File.join(interrupted_parent, interrupted_stages.first, "adapter.json")) &&
          !File.exist?(File.join(interrupted_parent, interrupted_stages.first, "lock"))
      end
      orphan_stage = File.join(interrupted_parent, interrupted_stages.fetch(0))
      retry_created = Lab::ChatGateway.create(path: interrupted_target, executor: A22GatewayFixtureExecutor.new)
      reopened_after_retry = Lab::ChatGateway.new(path: interrupted_target, executor: A22GatewayFixtureExecutor.new)
      check("fresh init after interruption succeeds and preserves the orphan stage", checks) do
        retry_created && File.directory?(interrupted_target) && File.directory?(orphan_stage) &&
          !reopened_after_retry.nil?
      end
      reopened_after_retry.close

      empty_target = File.join(temporary, "preexisting-empty-target")
      Dir.mkdir(empty_target, 0o700)
      empty_target_identity = [File.stat(empty_target).dev, File.stat(empty_target).ino]
      check("existing empty final target is refused without replacement", checks) do
        raises(Lab::Conflict) { Lab::ChatGateway.create(path: empty_target, executor: A22GatewayFixtureExecutor.new) } &&
          File.directory?(empty_target) && Dir.empty?(empty_target) &&
          [File.stat(empty_target).dev, File.stat(empty_target).ino] == empty_target_identity
      end
      immutable_target = File.join(temporary, "existing-final-root")
      Lab::ChatGateway.create(path: immutable_target, executor: A22GatewayFixtureExecutor.new)
      immutable_identity = [File.stat(immutable_target).dev, File.stat(immutable_target).ino]
      immutable_manifest = File.binread(File.join(immutable_target, "adapter.json"))
      check("existing initialized final root refuses replacement", checks) do
        raises(Lab::Conflict) { Lab::ChatGateway.create(path: immutable_target, executor: A22GatewayFixtureExecutor.new) } &&
          [File.stat(immutable_target).dev, File.stat(immutable_target).ino] == immutable_identity &&
          File.binread(File.join(immutable_target, "adapter.json")) == immutable_manifest
      end

      concurrent_parent = File.join(temporary, "concurrent-parent")
      Dir.mkdir(concurrent_parent, 0o700)
      concurrent_target = File.join(concurrent_parent, "adapter")
      first_inside_write = Queue.new
      release_first_write = Queue.new
      second_entered_create = Queue.new
      first_result = Queue.new
      second_result = Queue.new
      write_override = lambda do |directory, name, data, original_write|
        result = original_write.bind(directory).call(name, data)
        if name == "adapter.json" && Thread.current[:a22_create_writer] == :first
          first_inside_write << true
          release_first_write.pop
        end
        result
      end
      class_singleton = Lab::ChatGateway.singleton_class
      original_create = Lab::ChatGateway.method(:create)
      with_directory_write_override(write_override) do
        class_singleton.define_method(:create) do |**arguments|
          second_entered_create << true if Thread.current[:a22_create_writer] == :second
          original_create.call(**arguments)
        end
        first_thread = Thread.new do
          Thread.current[:a22_create_writer] = :first
          first_result << (Lab::ChatGateway.create(path: concurrent_target, executor: A22GatewayFixtureExecutor.new) rescue $!)
        end
        first_inside_write.pop
        second_thread = Thread.new do
          Thread.current[:a22_create_writer] = :second
          second_result << (Lab::ChatGateway.create(path: concurrent_target, executor: A22GatewayFixtureExecutor.new) rescue $!)
        end
        second_entered_create.pop
      second_outcome = Timeout.timeout(2) { second_result.pop }
      second_refused_while_first_staged = second_outcome.instance_of?(Lab::Busy) && !File.exist?(concurrent_target)
        release_first_write << true
        first_thread.join
        second_thread.join
        class_singleton.define_method(:create, original_create)
      first_outcome = first_result.pop
        check("concurrent create serializes staging and promotes exactly one final root", checks) do
          second_refused_while_first_staged && first_outcome == true &&
            File.directory?(concurrent_target) && Dir.children(concurrent_parent).grep(/\Astage-[a-f0-9]{32}\z/).empty?
        end
      ensure
        release_first_write << true
        first_thread&.join
        second_thread&.join
        class_singleton.define_method(:create, original_create)
      end

      symlink = File.join(temporary, "adapter-link")
      File.symlink(root, symlink)
      check("symlink roots are rejected", checks) do
        error = begin
          Lab::ChatGateway.new(path: symlink, executor: reopened_executor)
          nil
        rescue StandardError => caught
          caught
        end
        raise error if error && !error.instance_of?(Lab::IntegrityError)
        error.instance_of?(Lab::IntegrityError)
      end
      File.chmod(0o755, root)
      check("non-private root permissions are rejected", checks) do
        raises(Lab::IntegrityError) { Lab::ChatGateway.new(path: root, executor: reopened_executor) }
      end
      File.chmod(0o700, root)

      # The 32-turn request ceiling accepts the largest complete transcript,
      # while transport validation rejects any request that would be turn 33.
      largest = Array.new(63) { |index| { "role" => index.even? ? "user" : "assistant", "content" => "x" } }
      check("input bounds allow 32 turns and reject a 33rd", checks) do
        Lab::ChatGateway.validate_input!("limit32", largest)
        raises(Lab::ValidationError) do
          Lab::ChatGateway.validate_input!("limit32", largest + [{ "role" => "assistant", "content" => "x" }, { "role" => "user", "content" => "x" }])
        end
      end

      # Seed a pending model intent through the real Store. Runtime must turn
      # this uncertain request into a human-review terminal without calling the
      # fixture backend again.
      pending_root = File.join(temporary, "pending-root")
      fail_before_pending = true
      pending_executor = A22GatewayFixtureExecutor.new(before_run: -> { if fail_before_pending then fail_before_pending = false; raise "provision session only" end })
      pending_adapter = gateway(pending_root, pending_executor)
      raises(RuntimeError) { pending_adapter.complete(conversation_id: "pending-case", messages: messages("uncertain?")) }
      pending_store = Lab::Store.open(path: File.join(session_path(pending_root, "pending-case"), "worker", "store"), config: config)
      pending_store.synchronize do |state|
        pending_store.append("accepted", { "event_id" => "turn-0001", "content" => "uncertain?", "content_digest" => Digest::SHA256.hexdigest("uncertain?") })
        pending_store.append("model_intent", { "event_id" => "turn-0001", "call_index" => 0,
          "context" => Lab::ContextBuilder.build(state: state, event_id: "turn-0001", config: config) })
      end
      pending_store.close
      check("unresolved existing model intent blocks regeneration", checks) do
        raises(Lab::Conflict) { pending_adapter.complete(conversation_id: "pending-case", messages: messages("uncertain?")) } &&
        pending_executor.backend.calls.zero?
      end
      pending_adapter.close

      # An exception after Runtime has durably committed is recovered as a
      # replay. A pre-event exception is retryable and invokes Runtime once.
      durable_root = File.join(temporary, "durable-failure")
      after_once = true
      durable_executor = A22GatewayFixtureExecutor.new(after_run: -> { if after_once then after_once = false; raise "after durable reply" end })
      durable_gateway = gateway(durable_root, durable_executor)
      check("durable terminal reply survives executor failure and retry does not execute again", checks) do
        raises(RuntimeError) { durable_gateway.complete(conversation_id: "durable", messages: messages("persist this")) }
        recovered_durable = durable_gateway.complete(conversation_id: "durable", messages: messages("persist this"))
        recovered_durable.dig("soul", "replayed") && durable_executor.backend.calls == 1
      end
      durable_gateway.close

      pre_event_root = File.join(temporary, "pre-event-failure")
      fail_once = true
      pre_event_executor = A22GatewayFixtureExecutor.new(before_run: -> { if fail_once then fail_once = false; raise "before event" end })
      pre_event_gateway = gateway(pre_event_root, pre_event_executor)
      check("exception before event admission permits retry through Runtime", checks) do
        raises(RuntimeError) { pre_event_gateway.complete(conversation_id: "retry", messages: messages("retry me")) }
        result = pre_event_gateway.complete(conversation_id: "retry", messages: messages("retry me"))
        result["content"] == "durable answer" && pre_event_executor.backend.calls == 1
      end
      pre_event_gateway.close

      failed_executor = A22GatewayFixtureExecutor.new(responses: ['{"action":"reply","content":""}'])
      failed_root = File.join(temporary, "terminal-failure")
      failed_gateway = gateway(failed_root, failed_executor)
      check("failed terminal events are reused without a new model call", checks) do
        raises(Lab::Conflict) { failed_gateway.complete(conversation_id: "failed", messages: messages("invalid action response")) }
        raises(Lab::Conflict) { failed_gateway.complete(conversation_id: "failed", messages: messages("invalid action response")) }
        failed_executor.calls == 1 && failed_executor.backend.calls == 1
      end
      failed_gateway.close

      busy_root = File.join(temporary, "busy")
      entered = Queue.new
      release = Queue.new
      busy_executor = A22GatewayFixtureExecutor.new(held_run: -> { entered << true; release.pop })
      busy_gateway = gateway(busy_root, busy_executor)
      thread = Thread.new { busy_gateway.complete(conversation_id: "busy", messages: messages("hold")) }
      entered.pop
      check("concurrent request returns busy instead of queueing", checks) do
        raises(Lab::Busy) { busy_gateway.complete(conversation_id: "busy", messages: messages("hold")) }
      end
      release << true
      thread.value
      busy_gateway.close

      quota_root = File.join(temporary, "quota")
      quota_executor = A22GatewayFixtureExecutor.new
      quota_gateway = gateway(quota_root, quota_executor)
      15.times do |index|
        quota_gateway.complete(conversation_id: "quota-#{index}", messages: messages("q"))
      end
      Dir.mkdir(File.join(quota_root, "stage-#{'a' * 32}"), 0o700)
      check("session quota counts retained staging directories", checks) do
        raises(Lab::QuotaExceeded) { quota_gateway.complete(conversation_id: "quota-final", messages: messages("q")) }
      end
      quota_gateway.close

      puts "RESULT: #{checks[0]} A22 chat gateway checks passed, #{checks[1].length} failed; actual journal/runtime with scripted FakeBackend; all state confined to fresh temporary directories."
      checks[1].each { |name, klass, message| warn "FAILURE DETAIL: #{name}: #{klass}: #{message}" }
      raise "#{checks[1].length} A22 gateway verifier check(s) failed" unless checks[1].empty?
    end
  end
end

VerifyContinuityLabChatGatewayA22.run
