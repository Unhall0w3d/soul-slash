# frozen_string_literal: true
require_relative 'roster_memory_context'
require_relative 'cpu_member_adapter'
module SoulCore
  # Reuses the canonical ledger's already-filtered lexical ranking. GPU bindings
  # remain frozen; no CPU identity is mapped onto a GPU member.
  class CpuMemberMemoryContext < RosterMemoryContext
    MAX_BYTES=2048
    def select(member:CpuMemberAdapter::MODEL,query:,chat_id:nil,limit:4)
      raise ArgumentError,'CPU member required' unless member==CpuMemberAdapter::MODEL
      raise ArgumentError,'bounded memory query' unless query.is_a?(String)&&query.valid_encoding?&&query.bytesize<=65_536&&limit.is_a?(Integer)&&limit.between?(1,4)
      records=View.new(@store,member).context_for(query:query,chat_id:chat_id,limit:limit).fetch('records')
      chosen=[]
      records.each{|r|chosen<<r if render(chosen+[r]).bytesize<=MAX_BYTES}
      selection={'version'=>VERSION,'member'=>member,'stage'=>'selected_not_supplied','records'=>chosen,'rendered'=>render(chosen),'revisions'=>chosen.map{|r|{'id'=>r.fetch('id'),'sha256'=>self.class.digest(r)}}}
      selection['selection_sha256']=self.class.digest(selection)
      JSON.parse(JSON.generate(selection))
    end
    def validate_current!(selection)
      unsigned=selection.reject{|k,_|k=='selection_sha256'}
      raise Changed,'CPU memory binding changed' unless selection['version']==VERSION&&selection['member']==CpuMemberAdapter::MODEL&&selection['stage']=='selected_not_supplied'&&self.class.digest(unsigned)==selection['selection_sha256']
      records=selection.fetch('records')
      raise Changed,'memory bound' unless records.is_a?(Array)&&records.length<=4&&render(records).bytesize<=MAX_BYTES
      raise Changed,'projection changed' unless selection['rendered']==render(records)&&selection['revisions']==records.map{|r|{'id'=>r.fetch('id'),'sha256'=>self.class.digest(r)}}
      records.each do |r|
        current=@store.find(r.fetch('id'))
        raise Changed,'memory revoked or changed' unless self.class.visible?(current,CpuMemberAdapter::MODEL)&&self.class.digest(current)==self.class.digest(r)
      end
      true
    end
  end
end
