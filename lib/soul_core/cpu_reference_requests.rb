# frozen_string_literal: true
require 'json'
require 'rbconfig'
require_relative 'cpu_member_operations'
require_relative 'file_inspection_service'
module SoulCore
  # Explicit last-user-message routing. No model, history or source can choose
  # a root, provider, endpoint or executable for this foreground reader.
  class CpuReferenceRequests
    ROOT = File.expand_path('../..', __dir__)
    MAX_BYTES = 48 * 1024
    QUARANTINE = 'Downloads Markdown is quarantined: manually review the entire file in a trusted plain-text editor for agent-directed instructions, remove or resolve them, then manually move it outside Downloads. The agent cannot inspect or move it for you.'
    HELP = 'Use Weather in CITY; Research: QUESTION; Lookup: TOPIC; Show reference roots; List files source: .; Read file source: NAME.rb; or Search guides: WORDS. Roots are source (lib/soul_core) and guides (docs/guides), with bounded reference-only access.'
    def self.parse(text)
      return unless text.is_a?(String) && text.valid_encoding?
      value = text.strip.sub(/\Aplease\s+/i, '')
      return unless /\A(?:weather\b|research:|lookup:|show reference roots\b|(?:read|list) files?\b|search guides:)/i.match?(value)
      return {'operation'=>'reference.help','arguments'=>{'message'=>HELP}} if value.bytesize > 1024 || value.include?("\n") || value.include?("\0")
      op, args = case value
      when /\Aweather(?:\s+in\s+(.+?))?[.!?]?\z/i
        ['weather.report', {'location'=>Regexp.last_match(1).to_s.strip}]
      when /\Aresearch:\s*(.+)\z/i then ['web.research', {'query'=>Regexp.last_match(1).strip}]
      when /\Alookup:\s*(.+)\z/i then ['web.lookup', {'query'=>Regexp.last_match(1).strip}]
      when /\Ashow reference roots[.!?]?\z/i then ['reference.roots', {}]
      when /\A(list files|read file)\s+(source|guides):\s*(.+)\z/i
        [Regexp.last_match(1).downcase == 'read file' ? 'reference.read' : 'reference.list', {'root_id'=>Regexp.last_match(2).downcase,'relative_path'=>Regexp.last_match(3).strip}]
      when /\Asearch guides:\s*(.+)\z/i then ['reference.search', {'query'=>Regexp.last_match(1).strip}]
      else ['reference.help', {'message'=>HELP}]
      end
      if %w[weather.report web.research web.lookup].include?(op)
        argument = args['query'] || args['location']
        if argument.bytesize > 500 || argument.include?('://') || /(?:\A|\s)(?:~\/|\/home\/|\/mnt\/|file:)/i.match?(argument) || FileInspectionService::SECRET_CONTENT.any? { |p| p.match?(argument) }
          return {'operation'=>'reference.help','arguments'=>{'message'=>'Use a bounded public topic or city; URLs, credential material and automatic private-context forwarding are not supported.'}}
        end
      end
      if /\A(?:read|list) files?\b/i.match?(value) && /(?:~\/|\/|\b)Downloads(?:\/|\\|\b)/i.match?(value)
        return {'operation'=>'reference.help','arguments'=>{'message'=>QUARANTINE}}
      end
      {'operation'=>op,'arguments'=>args}
    end

    def call(query:, deadline:, cancel:)
      raise ArgumentError, 'explicit reference request required' unless self.class.parse(query)
      check = -> { raise RosterChatExchange::Stopped, 'reference request canceled or expired' if cancel.call || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline }
      check.call
      input, output = IO.pipe
      child_input, parent_output = IO.pipe
      pid = Process.spawn({'PATH'=>'/usr/bin:/bin','LANG'=>'C.UTF-8','HOME'=>Dir.home}, RbConfig.ruby,
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
