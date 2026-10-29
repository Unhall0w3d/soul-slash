# frozen_string_literal: true
require_relative 'cpu_member_operations'
module SoulCore
  class CpuMemberOperationsV2 < CpuMemberOperations
    def call(operation:,query:,deadline:,cancel:)
      raise ArgumentError,'unsupported operation' unless OPERATIONS.include?(operation)&&self.class.resolve(query)==operation
      check!(deadline,cancel)
      input,output=IO.pipe;query_input,query_output=IO.pipe
      pid=Process.spawn({'PATH'=>'/usr/bin:/bin','LANG'=>'C.UTF-8','HOME'=>Dir.home},RbConfig.ruby,
        File.join(ROOT,'scripts/cpu-member-read-only-operation-v2.rb'),operation,
        out:output,err:File::NULL,in:query_input,pgroup:true,unsetenv_others:true,chdir:ROOT)
      output.close;query_input.close;query_output.write(query);query_output.close;bytes=''.b;limit=[deadline,now+60].min
      loop do
        check!(limit,cancel)
        next unless IO.select([input],nil,nil,0.05)
        chunk=input.read_nonblock(4096,exception:false)
        break if chunk.nil?
        bytes<<chunk unless chunk==:wait_readable
        raise IOError,'operational output bound' if bytes.bytesize>MAX_BYTES
      end
      status=nil
      until status
        check!(limit,cancel)
        finished=Process.waitpid2(pid,Process::WNOHANG);status=finished.last if finished
        sleep 0.02 unless status
      end
      raise IOError,'operational helper failed' unless status.success?
      check!(limit,cancel);self.class.validate!(JSON.parse(bytes))
    ensure
      if pid
        Process.kill('KILL',-pid) rescue Errno::ESRCH
        Process.waitpid(pid) rescue Errno::ECHILD
      end
      [input,output,query_input,query_output].each{|io|io&.close unless io&.closed?}
    end
  end
end
