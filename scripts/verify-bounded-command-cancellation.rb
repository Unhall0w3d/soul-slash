#!/usr/bin/env ruby
require 'tmpdir'
require 'rbconfig'
require_relative '../lib/soul_core/bounded_command_runner'

Dir.mktmpdir('soul-cancel-test-') do |directory|
  marker = File.join(directory, 'child.pid')
  parent = Thread.current
  interrupter = Thread.new do
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
    sleep 0.01 until File.file?(marker) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    parent.raise(Interrupt)
  end
  interrupted = false
  begin
    SoulCore::BoundedCommandRunner.new.run(RbConfig.ruby, '-e', 'File.write(ARGV[0],Process.pid); sleep 30', marker, timeout_seconds: 10)
  rescue Interrupt
    interrupted = true
  ensure
    interrupter.join
  end
  raise 'interrupt was not propagated' unless interrupted
  pid = Integer(File.read(marker))
  begin
    Process.kill(0, pid)
    raise 'owned child survived cancellation'
  rescue Errno::ESRCH
    puts 'PASS: cancellation reaps the owned child before propagating'
  end
end
