# frozen_string_literal: true
require_relative 'roster_read_only_skills'
module SoulCore
  class RosterNavigationSkills < RosterReadOnlySkills
    FILES=%w[alpha.rb beta.rb location.rb child.rb calls.rb].freeze
    COMMANDS=['ruby snapshots','ruby symbols snapshot navigation-a2 alpha.rb',
      'ruby definition snapshot navigation-a2 calls.rb:4:36',
      'ruby possible references snapshot navigation-a2 alpha.rb:5:11'].freeze
    def self.binding
      paths=%w[scripts/roster-ruby-navigation-operation.py scripts/pilot-ruby-navigation.py scripts/pilot-ruby-navigation-multifile.py test/fixtures/ruby_navigation_a2/snapshot.json test/fixtures/ruby_navigation_a2/dependencies.json]
      paths.to_h{|n|[n,Digest::SHA256.file(File.join(ROOT,n)).hexdigest]}
    end
    def self.operation(text)
      old=super;return old if old
      return unless text.is_a?(String) && text.bytesize<=160
      value=text.strip
      return 'ruby.snapshots' if value=='ruby snapshots'
      if (m=/\Aruby symbols snapshot navigation-a2 ([a-z]+\.rb)\z/.match(value)) && FILES.include?(m[1])
        return "ruby.symbols|#{m[1]}|0|0"
      end
      if (m=/\Aruby (definition|possible references) snapshot navigation-a2 ([a-z]+\.rb):([1-9][0-9]{0,3}):([1-9][0-9]{0,3})\z/.match(value)) && FILES.include?(m[2])
        return "ruby.#{m[1]=='definition' ? 'definition' : 'references'}|#{m[2]}|#{m[3].to_i-1}|#{m[4].to_i-1}"
      end
      nil
    end
    def call(operation:,deadline:,cancel:)
      unless operation.start_with?('ruby.')
        result=super
        if operation=='skills.list'
          result['data']['connected_commands']+=COMMANDS
          result['data']['ruby_scope']='Only reviewed snapshot navigation-a2; references are possible matches.'
        end
        return result
      end
      check!(deadline,cancel)
      if operation=='ruby.snapshots'
        return {'state'=>'complete','data'=>{'snapshots'=>[{'id'=>'navigation-a2','files'=>FILES,'scope'=>'reviewed synthetic fixture','commands'=>COMMANDS}],
          'boundary'=>'No arbitrary repository paths. Explicit user commands only. References are possible matches.'}}
      end
      parts=operation.split('|',-1);action=parts[0].delete_prefix('ruby.')
      unless parts.length==4 && %w[definition symbols references].include?(action) && FILES.include?(parts[1]) && parts.last(2).all?{|v|/\A(?:0|[1-9][0-9]{0,3})\z/.match?(v)}
        raise ArgumentError,'invalid navigation operation'
      end
      input,output=IO.pipe
      pid=Process.spawn({'PATH'=>'/usr/bin:/bin','LANG'=>'C.UTF-8'},'/usr/bin/python3',
        File.join(ROOT,'scripts/roster-ruby-navigation-operation.py'),action,*parts.drop(1),
        out:output,err:File::NULL,in:File::NULL,pgroup:true,unsetenv_others:true,chdir:ROOT)
      output.close;bytes=''.b;limit=[deadline,now+30].min
      loop do
        check!(limit,cancel)
        if IO.select([input],nil,nil,0.05)
          chunk=input.read_nonblock(4096,exception:false);break if chunk.nil?
          bytes<<chunk unless chunk==:wait_readable
          raise IOError,'navigation output bound' if bytes.bytesize>MAX_BYTES
        end
      end
      status=nil
      until status
        check!(limit,cancel);finished=Process.waitpid2(pid,Process::WNOHANG);status=finished.last if finished;sleep 0.02 unless status
      end
      raise IOError,'navigation failed; evidence retained by gateway' unless status.success?
      result=JSON.parse(bytes)
      raise IOError,'invalid navigation result' unless result.is_a?(Hash) && result.keys.sort==%w[data state] && result['state']=='complete' && result['data'].is_a?(Hash)
      check!(limit,cancel);result
    ensure
      if pid
        # Allow the helper to remove its private snapshot, then enforce teardown.
        Process.kill('TERM',-pid) rescue Errno::ESRCH
        cleanup_until=now+2
        loop do
          break if (Process.waitpid(pid,Process::WNOHANG) rescue true) || now>=cleanup_until
          sleep 0.02
        end
        Process.kill('KILL',-pid) rescue Errno::ESRCH
        Process.waitpid(pid) rescue Errno::ECHILD
      end
      input&.close unless input&.closed?
      output&.close unless output&.closed?
    end
  end
end
