# frozen_string_literal: true
module SoulCore
  # Presentation only: never rebind an endpoint, model, prompt or stored chat.
  module RosterLibreChatPresentation
    DESCRIPTIONS={
      'soul-member-gpt-oss'=>'Active member. Approved shared and member-scoped memory; archived conversation history and replay protection. Four-minute idle unload, native low reasoning; Explicit read-only commands; no autonomous tools.',
      'soul-member-gemma'=>'Active member. Approved shared and member-scoped memory; archived conversation history and replay protection. Four-minute idle unload, thinking off; Explicit read-only commands; no autonomous tools.',
      'soul-member-qwen38'=>'Optional active member. Approved shared and member-scoped memory; archived history and replay protection. Four-minute idle unload, thinking off; Explicit read-only commands; no autonomous tools. Verify source claims.'
    }.freeze
    TRIALS=%w[soul-continuity-a22 soul-roster-gpt-oss-trial soul-roster-gemma-trial soul-roster-qwen38-trial].freeze
    def self.without_trial_presets(config)
      # Validate active identities, but preserve every retained entry byte-for-value.
      update(config)
      copy=Marshal.load(Marshal.dump(config))
      copy.fetch('modelSpecs').fetch('list').reject!{|row|TRIALS.include?(row.fetch('name'))}
      copy
    end
    def self.update(config)
      copy=Marshal.load(Marshal.dump(config));list=copy.fetch('modelSpecs').fetch('list')
      raise ArgumentError,'duplicate preset identity' unless list.map{|r|r.fetch('name')}.uniq.length==list.length
      DESCRIPTIONS.each do |name,description|
        row=list.find{|r|r['name']==name};raise ArgumentError,'active preset missing or rebound' unless row && row.dig('preset','endpoint')=='SoulRoster'
        row['description']=description
      end
      list.each do |row|
        next unless TRIALS.include?(row['name'])
        row['label']='Manual trial — '+row.fetch('label') unless row.fetch('label').start_with?('Manual trial — ')
        row['description']='Inactive unless a separate bounded trial is started. For normal use choose an active Soul member. Existing trial conversations remain preserved.'
      end
      copy['modelSpecs']['list']=list.select{|r|DESCRIPTIONS.key?(r['name'])}+list.reject{|r|DESCRIPTIONS.key?(r['name'])}
      copy
    end
  end
end
