# frozen_string_literal: true
require 'json'
module SoulCore
  # Only literal user commands supply these operands. No model expression evaluator.
  module CpuMemberCalculation
    NAME=/\A[a-zA-Z][a-zA-Z0-9_-]{0,31}\z/
    def self.parse(text)
      return nil unless text.start_with?('/calculate')
      raise ArgumentError,'Use /calculate with operation, sources, left and right JSON fields.' unless text.start_with?('/calculate ') && text.bytesize<=2048
      data=JSON.parse(text.delete_prefix('/calculate '),allow_duplicate_key:false)
      raise ArgumentError,'Exact calculation fields required' unless data.is_a?(Hash)&&data.keys.sort==%w[left operation right sources]
      sources=data['sources']
      raise ArgumentError,'Two named integer sources required' unless sources.is_a?(Hash)&&sources.length==2&&sources.all?{|k,v|NAME.match?(k)&&v.is_a?(Integer)&&v.between?(-1_000_000,1_000_000)}
      raise ArgumentError,'Unknown operation or source' unless %w[add subtract multiply].include?(data['operation'])&&%w[left right].all?{|k|data[k].is_a?(String)&&sources.key?(data[k])}
      data
    rescue JSON::ParserError
      raise ArgumentError,'Invalid or duplicate calculation JSON fields'
    end
    def self.evaluate(data)
      # Revalidate at every boundary, including journal replay.
      d=parse('/calculate '+JSON.generate(data));a=d['sources'].fetch(d['left']);b=d['sources'].fetch(d['right'])
      result=case d['operation'];when 'add';a+b;when 'subtract';a-b;when 'multiply';a*b;end
      {'operation'=>d['operation'],'sources'=>d['sources'],'left'=>d['left'],'right'=>d['right'],'operands'=>[a,b],'result'=>result,'source_policy'=>'explicit_user_invocation_only'}
    end
  end
end
