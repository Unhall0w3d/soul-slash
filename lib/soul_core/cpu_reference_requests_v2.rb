# frozen_string_literal: true
require_relative 'cpu_reference_requests'
module SoulCore
  # Frozen predecessor retains its exact execution environment. This version
  # lets the native weather runner find the same verified Ruby interpreter.
  class CpuReferenceRequestsV2 < CpuReferenceRequests
    def call(query:, deadline:, cancel:)
      raise ArgumentError, 'explicit reference request required' unless self.class.parse(query)
      check = -> { raise RosterChatExchange::Stopped, 'reference request canceled or expired' if cancel.call || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline }
      check.call
      input, output = IO.pipe
      child_input, parent_output = IO.pipe
      pid = Process.spawn({'PATH'=>File.dirname(RbConfig.ruby)+':/usr/bin:/bin','LANG'=>'C.UTF-8','HOME'=>Dir.home}, RbConfig.ruby,
        File.join(ROOT,'scripts/cpu-reference-operation.rb'), in:child_input, out:output, err:File::NULL,
        pgroup:true, unsetenv_others:true, chdir:ROOT)
      output.close; child_input.close; parent_output.write(query); parent_output.close
      bytes = ''.b
      limit = [deadline, Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60].min
      loop do
        check.call
        raise RosterChatExchange::Stopped, 'reference helper deadline' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= limit
        next unless IO.select([input],nil,nil,0.05)
        chunk = input.read_nonblock(4096,exception:false)
        break if chunk.nil?
        bytes << chunk unless chunk == :wait_readable
        raise IOError, 'reference output bound' if bytes.bytesize > MAX_BYTES
      end
      status = nil
      until status
        check.call
        raise RosterChatExchange::Stopped, 'reference helper deadline' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= limit
        finished = Process.waitpid2(pid,Process::WNOHANG); status=finished.last if finished
        sleep 0.02 unless status
      end
      raise IOError, 'reference helper failed' unless status.success?
      check.call
      CpuMemberOperations.validate!(JSON.parse(bytes,allow_duplicate_key:false))
    ensure
      if pid
        Process.kill('KILL',-pid) rescue Errno::ESRCH
        Process.waitpid(pid) rescue Errno::ECHILD
      end
      [input,output,child_input,parent_output].each { |io| io&.close unless io&.closed? }
    end
  end
end
