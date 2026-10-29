# frozen_string_literal: true
require 'json'
require 'rbconfig'
require_relative 'invocation_catalog_service'
require_relative 'roster_chat_exchange'
module SoulCore
  # Only exact current-user wording reaches fixed collectors. Model replies and
  # reference text are never dispatched through this reader.
  class CpuMemberOperations
    ROOT=File.expand_path('../..',__dir__)
    MAX_BYTES=48*1024
    OPERATIONS=%w[invocations.list security.status fleet.observability].freeze
    def self.resolve(text)
      return unless text.is_a?(String)&&text.valid_encoding?&&text.bytesize<=512
      value=text.strip.sub(/\Aplease\s+/i,'').sub(/[?.!]\z/,'').downcase
      return 'security.status' if %w[security\ status check\ security\ status show\ security\ status].include?(value)
      return 'fleet.observability' if ['fleet status','fleet observability','check fleet status','show fleet status'].include?(value)
      return 'invocations.list' if ['show commands','list commands','show supported requests','list supported requests'].include?(value)||InvocationCatalogService.new(root:ROOT).match?(text)
      nil
    end
    def call(operation:,query:,deadline:,cancel:)
      raise ArgumentError,'unsupported operation' unless OPERATIONS.include?(operation)&&self.class.resolve(query)==operation
      check!(deadline,cancel)
      input,output=IO.pipe;query_input,query_output=IO.pipe
      pid=Process.spawn({'PATH'=>'/usr/bin:/bin','LANG'=>'C.UTF-8','HOME'=>Dir.home},RbConfig.ruby,
        File.join(ROOT,'scripts/cpu-member-read-only-operation.rb'),operation,
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
    def self.validate!(outcome)
      raise ArgumentError,'operational result' unless outcome.is_a?(Hash)&&outcome.keys.sort==%w[content mutation report state]&&%w[complete failed awaiting_input blocked_for_human_review].include?(outcome['state'])&&outcome['report'].is_a?(Hash)&&%w[none private_status_caches_only].include?(outcome['mutation'])&&outcome['content'].is_a?(String)&&outcome['content'].valid_encoding?&&!outcome['content'].strip.empty?&&JSON.generate(outcome).bytesize<=MAX_BYTES
      outcome
    end
    private
    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    def check!(deadline,cancel)
      raise RosterChatExchange::Stopped,'operational request canceled or expired' if cancel.call||now>=deadline
    end
  end
end
