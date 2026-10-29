# frozen_string_literal: true
require_relative 'roster_source_navigation_skills'
module SoulCore
  class RosterSymbolPageSkills < RosterSourceNavigationSkills
    PAGE_SIZE=4
    MAX_PAGES=64
    SNAPSHOTS={'navigation-a2'=>RosterNavigationSkills::FILES,'soul-workflows-a1'=>RosterSourceNavigationSkills::FILES}.freeze
    def self.binding
      super.merge('lib/soul_core/roster_source_navigation_skills.rb'=>Digest::SHA256.file(File.join(__dir__,'roster_source_navigation_skills.rb')).hexdigest)
    end
    def self.operation(text)
      if text.is_a?(String) && text.strip.start_with?('ruby symbols snapshot ') && text.include?(' page ')
        return 'symbols.invalid' unless text.bytesize<=160 && (m=/\Aruby symbols snapshot (navigation-a2|soul-workflows-a1) ([a-z_]+\.rb) page (.*)\z/.match(text.strip))
        return 'symbols.invalid' unless SNAPSHOTS.fetch(m[1]).include?(m[2]) && /\A[1-9][0-9]{0,2}\z/.match?(m[3]) && m[3].to_i<=MAX_PAGES
        return "symbols.page|#{m[1]}|#{m[2]}|#{m[3]}"
      end
      super
    end
    def call(operation:,deadline:,cancel:)
      check!(deadline,cancel)
      return invalid('Use page 1 through 64 with an enrolled snapshot/file.') if operation=='symbols.invalid'
      if operation.start_with?('symbols.page|')
        fields=operation.split('|',-1);snapshot,file,page=fields.drop(1)
        unless fields.length==4 && SNAPSHOTS.fetch(snapshot,[]).include?(file) && /\A[1-9][0-9]{0,2}\z/.match?(page) && page.to_i<=MAX_PAGES
          raise ArgumentError,'invalid bounded page operation'
        end
        prefix=snapshot=='navigation-a2' ? 'ruby' : 'corpus'
        result=super(operation:"#{prefix}.symbols|#{file}|0|0",deadline:deadline,cancel:cancel)
        return paginate(result,snapshot:snapshot,file:file,page:page.to_i)
      end
      result=super
      if (m=/\A(ruby|corpus)\.symbols\|([^|]+)\|0\|0\z/.match(operation))
        return paginate(result,snapshot:m[1]=='ruby' ? 'navigation-a2' : 'soul-workflows-a1',file:m[2],page:1)
      end
      if %w[skills.list ruby.snapshots].include?(operation)
        result['data']['symbol_pagination']='Symbol queries return page 1; append page N. Four symbols per page, at most 64 pages. Follow the exact next_command.'
      end
      result
    end
    private
    def invalid(message,extra={})
      {'state'=>'awaiting_input','data'=>{'message'=>message,'model_invoked'=>false}.merge(extra)}
    end
    def paginate(result,snapshot:,file:,page:)
      return result unless result['state']=='complete'
      data=result.fetch('data');items=data['locations']
      unless data['snapshot']==snapshot && data['file']==file && /\A[a-f0-9]{64}\z/.match?(data['snapshot_sha256'].to_s) && items.is_a?(Array) &&
          items.all?{|x|x.is_a?(Array)&&x.length==3&&x[0].is_a?(String)&&x[0].bytesize<=512&&x[1].is_a?(Integer)&&x[1].between?(1,26)&&x[2].is_a?(Integer)&&x[2].between?(0,9999)}
        raise IOError,'invalid symbol evidence'
      end
      items=items.sort;pages=[1,(items.length+PAGE_SIZE-1)/PAGE_SIZE].max
      raise IOError,'bounded symbol set exceeded; no partial report' if pages>MAX_PAGES
      set_hash=RosterConversationGateway.digest({'snapshot'=>snapshot,'snapshot_sha256'=>data['snapshot_sha256'],'file'=>file,'symbols'=>items})
      common={'snapshot'=>snapshot,'snapshot_sha256'=>data['snapshot_sha256'],'file'=>file,'symbol_set_sha256'=>set_hash,'page_count'=>pages,'total_symbols'=>items.length}
      return invalid("Page #{page} is outside this report. Choose page 1 through #{pages}.",common) unless page.between?(1,pages)
      output=common.merge('page'=>page,'page_size'=>PAGE_SIZE,'complete'=>page==pages,
        'symbols'=>items.slice((page-1)*PAGE_SIZE,PAGE_SIZE) || [],'location_convention'=>'qualified name, LSP kind, zero-based source line',
        'evidence_sha256'=>RosterConversationGateway.digest(data),'source_is_untrusted_data'=>true,
        'next_command'=>page<pages ? "ruby symbols snapshot #{snapshot} #{file} page #{page+1}" : nil)
      raise IOError,'symbol page display bound' if JSON.pretty_generate(output).bytesize>8192
      {'state'=>'complete','data'=>output}
    end
  end
end
