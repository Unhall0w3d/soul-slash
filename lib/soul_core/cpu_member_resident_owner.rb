# frozen_string_literal: true
require 'net/http'
require 'tmpdir'
require_relative 'cpu_member_loopback_client'
module SoulCore
  class CpuMemberResidentOwner
    ROOT=File.expand_path('../..',__dir__)
    def initialize(path:,clock:->{Process.clock_gettime(Process::CLOCK_MONOTONIC)},idle_seconds:nil)
      raise ArgumentError unless idle_seconds.nil?
      @path,@clock,@idle=path,clock,idle_seconds;@client=CpuMemberLoopbackClient.new;@pid=nil;@last=nil
    end
    def request(*args,deadline:,cancel:)
      start(deadline,cancel) unless @pid
      raise CpuMemberGateway::Refused,'CPU telemetry unavailable' unless admitted?
      @last=@clock.call
      @client.request(*args,deadline:deadline,cancel:cancel)
    end
    def admitted?
      return true unless @pid # Admission is rechecked before the lazy launch.
      stat=JSON.parse(File.read(File.join(@output,'status.json')))
      stat['state']=='running'&&(Time.now.to_f-stat['sampled_at']).between?(0,3)&&alive?
    rescue StandardError
      false
    end
    def start(deadline,cancel)
      @output=Dir.mktmpdir('runtime-',@path)
      @exited=false
      @pid=Process.spawn('/usr/bin/python3',File.join(ROOT,'scripts/cpu-member-resident-runtime.py'),@output,Process.pid.to_s,
        out:File.join(@output,'owner.log'),err:[:child,:out],pgroup:true)
      loop do
        raise CpuMemberGateway::Refused,'CPU startup canceled or timed out' if cancel.call||@clock.call>=deadline
        raise CpuMemberGateway::Refused,'CPU owner exited' unless alive?
        if File.file?(File.join(@output,'status.json'))&&admitted?
          begin
            http=Net::HTTP.new('127.0.0.1',18084,nil);http.open_timeout=1;http.read_timeout=1
            break if http.get('/health').code=='200'
          rescue IOError,SystemCallError,Timeout::Error
          end
        end
        sleep 0.1
      end
      @last=@clock.call
    rescue StandardError
      stop;raise
    end
    def alive?
      return false if @exited
      @exited=!!Process.waitpid(@pid,Process::WNOHANG)
      !@exited
    rescue Errno::ECHILD
      @exited=true;false
    end
    def touch = (@last=@clock.call)
    def tick
      stop if @pid&&!admitted?
    end
    def status = {'state'=>@pid ? 'loaded' : 'unloaded','idle_seconds'=>nil,'residency'=>'until_stop_or_guard_failure','cpu_only'=>true}
    def stop
      pid=@pid;return true unless pid
      begin
        Process.kill('TERM',pid) unless @exited
        deadline=@clock.call+12
        loop do
          break if @exited || Process.waitpid(pid,Process::WNOHANG)
          raise CpuMemberGateway::Refused,'CPU owner cleanup unconfirmed' if @clock.call>=deadline
          sleep 0.05
        end
      rescue Errno::ESRCH,Errno::ECHILD
      end
      receipt=JSON.parse(File.read(File.join(@output,'receipt.json')))
      raise CpuMemberGateway::Refused,'CPU cleanup unconfirmed' unless receipt['owned_process_exited']&&receipt['port_closed']
      @pid=nil;@last=nil;true
    end
  end
end
