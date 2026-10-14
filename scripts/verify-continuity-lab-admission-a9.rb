#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require "timeout"
require_relative "../lib/soul_core/continuity_lab/admission_gate"
Lab = SoulCore::ContinuityLab
checks = 0
check = ->(name, ok) { checks += 1; raise "FAIL: #{name}" unless ok; puts "PASS: #{name}" }
denied = lambda do |klass, &block|
  block.call
  false
rescue klass
  true
end
fixture = lambda do |&block|
  Dir.mktmpdir("continuity-admission-a9-") do |root|
    store = SoulCore::ModelRuntimeLeaseStore.new(root: root)
    now = [100.0]
    snapshot = -> { { "active_slots" => 0, "captured_at" => now[0], "core" => "amd-free",
      "dedicated_window" => true, "model_file" => "Qwen3-8B-Q4_K_M.gguf", "pending_transition" => false,
      "profile_id" => "nvidia-fallback", "service_active" => true } }
    block.call(store, now, snapshot, root)
  end
end

[0, 1, 3, 100].each do |failures|
  fixture.call do |store, now, snapshot|
    original = store.method(:with_control_lock)
    attempts = bodies = observations = 0
    store.define_singleton_method(:with_control_lock) do |&body|
      attempts += 1
      raise SoulCore::ModelRuntimeLeaseStore::LockUnavailable if attempts <= failures
      original.call(&body)
    end
    events = []
    gate = Lab::AdmissionGate.new(lease_store: store, snapshot_provider: -> { observations += 1; snapshot.call },
      clock: -> { now[0] }, lock_wait_seconds: 5, sleeper: ->(seconds) { now[0] += seconds },
      on_contention: ->(event) { events << event })
    outcome = begin
      gate.with_window { bodies += 1; :once }
    rescue Lab::AdmissionDenied
      :denied
    end
    check.call("contention #{failures}: only successful admission observes/yields",
      failures < 100 ? outcome == :once && bodies == 1 && observations == 1 && attempts == failures + 1 :
        outcome == :denied && bodies.zero? && observations.zero? && attempts <= 21 && now[0] == 105)
    check.call("contention #{failures}: bounded receipt count", events.length == [failures, 20].min)
    # Restore the real lock and independently check it is not held.
    store.define_singleton_method(:with_control_lock, original)
    check.call("contention #{failures}: lock released", store.with_control_lock { true })
  end
end

fixture.call do |store, now, snapshot|
  attempts = 0
  store.define_singleton_method(:with_control_lock) { attempts += 1; raise SoulCore::ModelRuntimeLeaseStore::LockUnavailable }
  gate = Lab::AdmissionGate.new(lease_store: store, snapshot_provider: snapshot, clock: -> { now[0] },
    sleeper: ->(_) { raise "default must not sleep" })
  check.call("default remains one attempt", denied.call(Lab::AdmissionDenied) { gate.with_window {} } && attempts == 1)
  gate = Lab::AdmissionGate.new(lease_store: store, snapshot_provider: snapshot, clock: -> { now[0] },
    lock_wait_seconds: 5, sleeper: ->(_) {})
  attempts = 0
  check.call("stalled clock still has attempt cap", denied.call(Lab::AdmissionDenied) { gate.with_window {} } && attempts == 21)
  attempts = 0
  gate = Lab::AdmissionGate.new(lease_store: store, snapshot_provider: snapshot, clock: -> { now[0] },
    lock_wait_seconds: 5, sleeper: ->(_) { raise Interrupt })
  check.call("wait interruption does not retry", denied.call(Interrupt) { gate.with_window {} } && attempts == 1)
  attempts = 0
  gate = Lab::AdmissionGate.new(lease_store: store, snapshot_provider: snapshot, clock: -> { now[0] },
    lock_wait_seconds: 5, on_contention: ->(_) { raise "receipt failure" })
  check.call("receipt failure does not retry", denied.call(RuntimeError) { gate.with_window {} } && attempts == 1)
end

[:provider, :body, :integrity, :io, :timeout, :interrupt, :busy, :retained].each do |failure|
  fixture.call do |store, now, snapshot|
    original = store.method(:with_control_lock)
    attempts = bodies = observations = 0
    store.define_singleton_method(:with_control_lock) { |&body| attempts += 1; original.call(&body) }
    provider = lambda do
      observations += 1
      case failure
      when :provider then raise SoulCore::ModelRuntimeLeaseStore::LockUnavailable
      when :integrity then raise SoulCore::ModelRuntimeLeaseStore::IntegrityError
      when :io then raise Errno::EIO
      when :busy then snapshot.call.merge("active_slots" => 1)
      else snapshot.call
      end
    end
    if failure == :retained
      store.define_singleton_method(:leases_for_quiescent_admission_unlocked) { [{ "retained" => true }] }
    end
    gate = Lab::AdmissionGate.new(lease_store: store, snapshot_provider: provider, clock: -> { now[0] },
      lock_wait_seconds: 5, sleeper: ->(_) { raise "must not replay entered window" })
    expected = { io: Errno::EIO, timeout: Timeout::Error, interrupt: Interrupt }.fetch(failure, Lab::AdmissionDenied)
    caught = denied.call(expected) do
      gate.with_window do
        bodies += 1
        case failure
        when :body then raise SoulCore::ModelRuntimeLeaseStore::LockUnavailable
        when :timeout then raise Timeout::Error
        when :interrupt then raise Interrupt
        end
      end
    end
    check.call("#{failure}: no replay after entry", caught && attempts == 1 && bodies <= 1 && observations <= 1)
    check.call("#{failure}: real lock released", original.call { true })
  end
end

fixture.call do |store, now, snapshot, root|
  [nil, "5", -1, 5.01, Float::NAN, Float::INFINITY].each do |value|
    check.call("invalid wait #{value.inspect}", denied.call(Lab::ValidationError) do
      Lab::AdmissionGate.new(lease_store: store, snapshot_provider: snapshot, lock_wait_seconds: value)
    end)
  end
  # Actual flock contention (not a synthetic acquisition exception), released by
  # the injected foreground sleeper before the next attempt.
  store.with_control_lock {}
  lock = File.open(File.join(root, SoulCore::ModelRuntimeLeaseStore::DEFAULT_DIRECTORY, "control.lock"), "r+")
  lock.flock(File::LOCK_EX | File::LOCK_NB)
  events = []
  gate = Lab::AdmissionGate.new(lease_store: store, snapshot_provider: snapshot, clock: -> { now[0] },
    lock_wait_seconds: 5, sleeper: ->(seconds) { lock.flock(File::LOCK_UN); now[0] += seconds },
    on_contention: ->(event) { events << event })
  check.call("real flock retry acquires after owner release", gate.with_window { true } && events.length == 1)
ensure
  lock&.close
end
puts "#{checks}/#{checks} checks passed"
