#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative '../lib/soul_core/cpu_member_operations'
require_relative '../lib/soul_core/dotenv_reader'
require_relative '../lib/soul_core/conversation_security_status_service'
require_relative '../lib/soul_core/conversation_fleet_observability_service'
require_relative '../lib/soul_core/wazuh_security_status_service'
require_relative '../lib/soul_core/wazuh_alert_evidence_service'
require_relative '../lib/soul_core/wazuh_compliance_posture_service'
require_relative '../lib/soul_core/fleet_observability_summary_service'
module SoulCore
  module CpuOperationalPaths
    def self.verify!(path)
      expanded=File.expand_path(path.to_s)
      raise ArgumentError,'Downloads paths prohibited' if expanded=='/home/bhones/Downloads'||expanded.start_with?('/home/bhones/Downloads/')
      current=expanded
      loop do
        begin
          resolved=File.realpath(current)
          raise ArgumentError,'Downloads alias prohibited' if resolved=='/home/bhones/Downloads'||resolved.start_with?('/home/bhones/Downloads/')
          break
        rescue Errno::ENOENT
          parent=File.dirname(current);raise if parent==current;current=parent
        end
      end
      path
    end
    # Guard before the existing validators or readers inspect configuration,
    # credential and certificate files; caller text cannot supply these paths.
    private
    def read_private_json(path,*args)
      CpuOperationalPaths.verify!(path);super
    end
    def validate_file_path(path,**args)
      CpuOperationalPaths.verify!(path);super
    end
  end
end
SoulCore::WazuhSecurityStatusService.prepend(SoulCore::CpuOperationalPaths)
SoulCore::WazuhAlertEvidenceService.prepend(SoulCore::CpuOperationalPaths)
SoulCore::WazuhCompliancePostureService.prepend(SoulCore::CpuOperationalPaths)
if $PROGRAM_NAME==__FILE__
  raise 'ordinary user required' if Process.uid.zero?
  root=File.expand_path('..',__dir__)
  raise 'canonical project required' unless File.realpath(root)==root
  raise 'one fixed operation required' unless ARGV.length==1
  query=STDIN.read(513).force_encoding(Encoding::UTF_8);operation=ARGV.first
  raise 'explicit operation required' unless query.valid_encoding?&&SoulCore::CpuMemberOperations.resolve(query)==operation
  if operation=='invocations.list'
    catalog=SoulCore::InvocationCatalogService.new(root:root)
    wording=case query.strip.downcase.sub(/[.!?]\z/,'')
    when /\A(?:please )?(?:show|list) commands\z/ then 'List Commands invocations'
    when /\A(?:please )?(?:show|list) supported requests\z/ then 'List Supported requests invocations'
    else query
    end
    outcome={'state'=>'complete','content'=>catalog.respond(wording),'report'=>{'scope'=>'curated invocation documentation','read_only'=>true,'examples_are_authority'=>false},'mutation'=>'none'}
  else
    dotenv=SoulCore::DotenvReader.new(root:root).read;raise 'configuration unavailable' unless dotenv.ok?
    keys=%w[SOUL_WAZUH_INTEGRATION_FILE SOUL_WAZUH_ALERTS_INTEGRATION_FILE SOUL_WAZUH_POSTURE_FILE SOUL_OBSERVABILITY_SSH_ALIAS SOUL_OBSERVABILITY_SSH_CONFIG SOUL_OBSERVABILITY_GRAFANA_URL]
    env=dotenv.values.slice(*keys).merge(ENV.to_h.slice(*keys))
    env.each{|k,v|SoulCore::CpuOperationalPaths.verify!(v) if k.end_with?('_FILE','_CONFIG')&&!v.empty?}
    report=if operation=='security.status'
      SoulCore::ConversationSecurityStatusService.new(
        wazuh_status_service:SoulCore::WazuhSecurityStatusService.new(root:root,process_env:env),
        alert_evidence_service:SoulCore::WazuhAlertEvidenceService.new(root:root,process_env:env),
        posture_service:SoulCore::WazuhCompliancePostureService.new(root:root,process_env:env)).report
    elsif operation=='fleet.observability'
      SoulCore::ConversationFleetObservabilityService.new(summary_service:SoulCore::FleetObservabilitySummaryService.new(process_env:env)).report
    else
      raise 'unsupported operation'
    end
    outcome={'state'=>report.fetch('lifecycle_state'),'content'=>report.fetch('content'),'report'=>report.fetch('report'),'mutation'=>report.fetch('mutation')}
  end
  puts JSON.generate(SoulCore::CpuMemberOperations.validate!(outcome))
end
