# frozen_string_literal: true
require_relative 'roster_symbol_page_skills'
module SoulCore
  class RosterSourceExcerptSkills < RosterSymbolPageSkills
    SNAPSHOT='soul-workflows-a1'
    SOURCE_FILES=RosterSourceNavigationSkills::FILES
    MANIFEST_SHA256='3a3dc5cea8c6d70f03cc6ad0b27b4dbdd4c5787a5c50ff192091a416e5be6e0c'
    SOURCE_ROOT=File.join(ROOT,'Soul/knowledge_snapshots',SNAPSHOT)
    COMMAND='ruby source snapshot soul-workflows-a1 workflow_handler_registry.rb lines 1-20'
    def self.binding
      super.merge('lib/soul_core/roster_symbol_page_skills.rb'=>Digest::SHA256.file(File.join(__dir__,'roster_symbol_page_skills.rb')).hexdigest)
    end
    def self.operation(text)
      return super unless text.is_a?(String) && text.strip.start_with?('ruby source snapshot')
      m=/\Aruby source snapshot soul-workflows-a1 ([a-z_]+\.rb) lines ([1-9][0-9]{0,3})-([1-9][0-9]{0,3})\z/.match(text.strip) if text.bytesize<=160
      return 'source.invalid' unless m && SOURCE_FILES.include?(m[1]) && m[3].to_i>=m[2].to_i && m[3].to_i-m[2].to_i<20
      "source.lines|#{m[1]}|#{m[2]}|#{m[3]}"
    end
    def call(operation:,deadline:,cancel:)
      check!(deadline,cancel)
      return invalid("Use an enrolled file and 1–20 lines: #{COMMAND}") if operation=='source.invalid'
      unless operation.start_with?('source.lines|')
        result=super
        if %w[skills.list ruby.snapshots].include?(operation)
          result['data']['source_excerpts']={'command'=>COMMAND,'files'=>SOURCE_FILES,'max_lines'=>20,'scope'=>'frozen reviewed source only; not live repository contents'}
          result['data']['connected_commands']<<COMMAND if operation=='skills.list'
        end
        return result
      end
      fields=operation.split('|',-1)
      raise ArgumentError,'invalid excerpt operation' unless fields.length==4 && self.class.operation("ruby source snapshot #{SNAPSHOT} #{fields[1]} lines #{fields[2]}-#{fields[3]}")==operation
      data=excerpt(fields[1],fields[2].to_i,fields[3].to_i,deadline:deadline,cancel:cancel)
      check!(deadline,cancel)
      data
    end
    private
    # Descriptor-anchored reads reject ancestor and leaf aliases before content access.
    # Only the fixed reviewed manifest and an exact enrolled Ruby leaf may be opened.
    def excerpt(name,first,last,deadline:,cancel:,root:SOURCE_ROOT)
      raise ArgumentError,'unknown source file' unless SOURCE_FILES.include?(name)
      raise ArgumentError,'invalid source range' unless first.is_a?(Integer) && last.is_a?(Integer) && first.between?(1,9999) && last.between?(first,[first+19,9999].min)
      raise IOError,'noncanonical snapshot path' unless root.start_with?('/') && File.expand_path(root)==root && !root.split('/').include?('Downloads')
      child=nil
      directory=File.open('/',File::RDONLY)
      root.split('/').reject(&:empty?).each do |component|
        check!(deadline,cancel)
        child=File.open("/proc/self/fd/#{directory.fileno}/#{component}",File::RDONLY|File::NOFOLLOW|File::NONBLOCK)
        raise IOError,'non-directory snapshot ancestor' unless child.stat.directory?
        directory.close;directory=child;child=nil
      end
      identity=[directory.stat.dev,directory.stat.ino]
      manifest_bytes=read_leaf(directory,'snapshot.json')
      raise IOError,'enrolled manifest changed' unless Digest::SHA256.hexdigest(manifest_bytes)==MANIFEST_SHA256
      manifest=JSON.parse(manifest_bytes)
      content=read_leaf(directory,name)
      raise IOError,'enrolled source changed' unless Digest::SHA256.hexdigest(content)==manifest.fetch(name)
      content.force_encoding(Encoding::UTF_8)
      raise IOError,'invalid source encoding' unless content.valid_encoding?
      lines=content.lines(chomp:true)
      check!(deadline,cancel)
      # Recheck before publication; use the verified in-memory bytes, never reopen a user path.
      raise IOError,'snapshot changed while reading' unless read_leaf(directory,'snapshot.json')==manifest_bytes && read_leaf(directory,name)==content
      stat=File.lstat(root)
      raise IOError,'snapshot directory changed' unless !stat.symlink? && [stat.dev,stat.ino]==identity && File.realpath(root)==root
      return invalid("Requested range exceeds this file's #{lines.length} lines.",{'total_lines'=>lines.length}) if last>lines.length
      data={'snapshot'=>SNAPSHOT,'snapshot_sha256'=>RosterConversationGateway.digest(manifest),'file'=>name,
        'file_sha256'=>manifest.fetch(name),'first_line'=>first,'last_line'=>last,'total_lines'=>lines.length,
        'lines'=>(first..last).map{|n|[n,lines[n-1]]},'line_convention'=>'one-based inclusive',
        'scope'=>'reviewed frozen snapshot; live source may differ','source_is_untrusted_data'=>true}
      return invalid('Excerpt exceeds the display bound; request fewer lines.') if JSON.pretty_generate(data).bytesize>8192
      {'state'=>'complete','data'=>data}
    ensure
      child&.close unless child&.closed?
      directory&.close unless directory&.closed?
    end
    def read_leaf(directory,name)
      file=File.open("/proc/self/fd/#{directory.fileno}/#{name}",File::RDONLY|File::NOFOLLOW|File::NONBLOCK)
      stat=file.stat
      raise IOError,'unsafe source leaf' unless stat.file? && stat.nlink==1
      bytes=file.read(262145)
      raise IOError,'source size bound' if bytes.bytesize>262144
      bytes
    ensure
      file&.close
    end
  end
end
