#!/usr/bin/env ruby
# frozen_string_literal: true

require "socket"
require "stringio"
require "tmpdir"
require "timeout"
require_relative "../lib/soul_core/continuity_lab/sandbox_runner"
require_relative "../lib/soul_core/continuity_lab/broker_session"
require_relative "continuity-lab-chat"

module VerifyContinuityLabChatLifecycleA22
  Lab = SoulCore::ContinuityLab
  Response = Struct.new(:status, :headers, :body, keyword_init: true)
  BLOCKED = Class.new(StandardError)
  @checks = 0

  class Cancellation
    def initialize
      @canceled = false
    end

    def cancel! = @canceled = true
    def canceled? = @canceled
  end

  class TimeoutApplication
    attr_reader :runner, :finished

    def initialize(state_directory:, cancellation:)
      @runner = Lab::SandboxRunner.new(state_directory: state_directory, timeout_seconds: 8)
      @broker = Lab::BrokerSession.new(responses: ["synthetic unused response"])
      @cancellation = cancellation
      @finished = Queue.new
    end

    def call(**_request)
      outcome = nil
      begin
        @runner.run(request: { "mode" => "timeout_probe" }, broker: @broker,
          cancel: -> { @cancellation.canceled? })
        outcome = "unexpected worker completion"
      rescue Lab::SandboxFailure => error
        outcome = "#{error.class}: #{error.message}"
      ensure
        @finished << { "pid" => @runner.pid, "reap_state" => reap_state(@runner.pid), "outcome" => outcome }
      end
      Response.new(status: 500, headers: { "content-type" => "text/plain" }, body: outcome)
    end

    private

    def reap_state(pid)
      return "no_child" unless pid

      begin
        waited = Process.waitpid(pid, Process::WNOHANG)
        waited ? "still_waitable" : "still_running_or_unreaped"
      rescue Errno::ECHILD
        "already_reaped"
      end
    end
  end

  def self.check(condition, label)
    raise "FAIL: #{label}" unless condition

    @checks += 1
    puts "PASS: #{label}"
  end

  def self.monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def self.wait_until(deadline, label)
    until yield
      raise Timeout::Error, label if monotonic >= deadline

      sleep 0.01
    end
  end

  def self.live_pid?(pid)
    return false unless pid

    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def self.run_case(reason:, deadline_stop:)
    Dir.mktmpdir("soul-a22-lifecycle-") do |temporary|
      state_directory = File.join(temporary, "worker")
      Dir.mkdir(state_directory, 0o700)
      cancellation = Cancellation.new
      application = TimeoutApplication.new(state_directory: state_directory, cancellation: cancellation)
      server = SoulCore::ContinuityLab::ForegroundChatServer.new(executor: cancellation,
        host: "127.0.0.1", port: 0, application: application, output: StringIO.new)
      server_thread = Thread.new { server.run }
      server_thread.report_on_exception = false
      client = nil
      deadline = monotonic + 8

      wait_until(deadline, "listener did not bind") do
        raise server_thread.value unless server_thread.alive?

        server.instance_variable_get(:@listener)
      end
      listener = server.instance_variable_get(:@listener)
      port = listener.addr.fetch(1)
      client = TCPSocket.new("127.0.0.1", port)
      client.write("GET /synthetic-worker-probe HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
      wait_until(deadline, "timeout_probe child did not start") do
        live_pid?(application.runner.pid) || !application.finished.empty?
      end
      if !live_pid?(application.runner.pid)
        failed = application.finished.pop
        if !failed["pid"] && failed["outcome"].match?(/worker channel unavailable: Errno::(?:EPERM|EACCES|ENOENT)/)
          raise BLOCKED, failed.fetch("outcome")
        end
        raise "timeout_probe exited before stop: #{failed.inspect}"
      end
      child_pid = application.runner.pid
      check(live_pid?(child_pid), "#{reason}: timeout_probe sandbox child is alive before stop")

      if deadline_stop
        remaining = deadline - monotonic
        raise Timeout::Error, "deadline stop budget exhausted" unless remaining > 0.25

        supervisor = Thread.new do
          sleep 0.1
          server.stop
        end
        supervisor.join([deadline - monotonic, 2].min)
        check(!supervisor.alive?, "#{reason}: bounded deadline supervisor returned")
      else
        server.stop
      end

      client.close unless client.closed?
      wait_until(deadline, "active request did not finish after stop") { !application.finished.empty? }
      outcome = application.finished.pop
      check(outcome.fetch("pid") == child_pid && outcome.fetch("reap_state") == "already_reaped" &&
            outcome.fetch("outcome").include?("worker canceled"),
        "#{reason}: request observes cancellation and child already reaped before response")
      joined = server_thread.join([deadline - monotonic, 2].min)
      check(joined && !server_thread.alive?, "#{reason}: server thread returned within bound")
      check(listener.closed? && server.instance_variable_get(:@request_threads).empty?,
        "#{reason}: listener and request-thread registry are clear after return")
      check(cancellation.canceled?, "#{reason}: stop reached the executor cancellation hook")
    ensure
      client&.close unless client&.closed?
      server&.stop
      server_thread&.join(1)
      server_thread&.kill if server_thread&.alive?
    end
  rescue SystemCallError => error
    if %w[EPERM EACCES ENOENT].include?(error.class.name.split("::").last)
      raise BLOCKED, "#{error.class}: #{error.message}"
    end
    raise
  rescue RuntimeError => error
    raise BLOCKED, error.message if error.message.include?("worker channel unavailable: Errno::EPERM") ||
                                    error.message.include?("worker channel unavailable: Errno::EACCES") ||
                                    error.message.include?("worker channel unavailable: Errno::ENOENT")

    raise
  end

  def self.run
    puts "Evidence scope: synthetic timeout_probe worker; no inference, model, GPU, or service use."
    unless File.executable?("/usr/bin/bwrap")
      raise BLOCKED, "required isolated worker launcher /usr/bin/bwrap is unavailable"
    end

    run_case(reason: "explicit stop", deadline_stop: false)
    run_case(reason: "bounded deadline-style stop", deadline_stop: true)
    puts "RESULT: #{@checks} lifecycle assertions passed; synthetic timeout_probe worker only."
  rescue BLOCKED => error
    warn "BLOCKED: #{error.message}"
    warn "Primary host command: /home/bhones/.rbenv/versions/4.0.7/bin/ruby scripts/verify-continuity-lab-chat-lifecycle-a22.rb"
    exit 2
  end
end

VerifyContinuityLabChatLifecycleA22.run
