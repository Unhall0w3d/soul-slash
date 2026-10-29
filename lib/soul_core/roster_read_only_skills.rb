# frozen_string_literal: true
require 'json'
require 'rbconfig'
require_relative 'roster_conversation_gateway'
module SoulCore
  # Only trusted last-user commands enter here. Model replies never dispatch.
  class RosterReadOnlySkills
    ROOT=File.expand_path('../..',__dir__)
    OPERATIONS=%w[host.status roster.status skills.list repository.roots repository.inspect].freeze
    MAX_BYTES=48*1024
    def self.operation(text)
      return unless text.is_a?(String) && text.bytesize<=160
      value=text.strip.sub(/\Aplease\s+/i,'').sub(/[?.!]\z/,'').strip.downcase
      case value
      when 'host status','system status','show host status','assess host system' then 'host.status'
      when 'soul status','roster status','show soul status' then 'roster.status'
      when 'list skills','show skills','what skills do you have','what can you do','show capabilities' then 'skills.list'
      when 'show approved repository roots','list approved repository roots' then 'repository.roots'
      when 'inspect repository root project','inspect repository in approved root project' then 'repository.inspect'
      end
    end
    def initialize(status:)
      @status=status
    end
    def call(operation:,deadline:,cancel:)
      raise ArgumentError,'unknown read-only operation' unless OPERATIONS.include?(operation)
      check!(deadline,cancel)
      if operation=='roster.status'
        return {'state'=>'complete','data'=>@status.call.slice('state','model','idle_seconds','residency_limit_seconds')}
      end
      input,output=IO.pipe
      pid=Process.spawn({'PATH'=>'/usr/bin:/bin','LANG'=>'C.UTF-8'},RbConfig.ruby,
        File.join(ROOT,'scripts/roster-read-only-operation.rb'),operation,
        out:output,err:File::NULL,in:File::NULL,pgroup:true,unsetenv_others:true,chdir:ROOT)
      output.close
      bytes=''.b; limit=[deadline,now+30].min
      loop do
        check!(limit,cancel)
        if IO.select([input],nil,nil,0.05)
          chunk=input.read_nonblock(4096,exception:false)
          break if chunk.nil?
          bytes<<chunk unless chunk==:wait_readable
          raise IOError,'read-only output bound' if bytes.bytesize>MAX_BYTES
        end
      end
      check!(limit,cancel)
      status=nil
      until status
        check!(limit,cancel)
        finished=Process.waitpid2(pid,Process::WNOHANG)
        status=finished.last if finished
        sleep 0.02 unless status
      end
      raise IOError,'read-only operation failed' unless status.success?
      result=JSON.parse(bytes)
      raise IOError,'invalid read-only result' unless result.is_a?(Hash) && result.keys.sort==%w[data state] && %w[complete failed awaiting_input blocked_for_human_review].include?(result['state'])
      result
    ensure
      # Kill any descendant left behind even if the immediate helper exited.
      if pid
        Process.kill('KILL',-pid) rescue Errno::ESRCH
        Process.waitpid(pid) rescue Errno::ECHILD
      end
      input&.close unless input&.closed?
      output&.close unless output&.closed?
    end
    private
    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    def check!(deadline,cancel)
      raise RosterChatExchange::Stopped,'read-only operation canceled or expired' if cancel.call || now>=deadline
    end
  end
end
