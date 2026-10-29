# frozen_string_literal: true
require_relative "roster_dashboard_runtime"

module SoulCore
  # Browser never receives the coordinator credential or an arbitrary endpoint.
  class SharedComputeService
    def initialize(client: RosterDashboardRuntime.new(store:nil),key_reader:nil)
      @client=client
      @key_reader=key_reader || -> { @client.send(:read_key) }
    end
    def status = request("status",{})
    def preview(policy:) = request("preview",{"policy"=>policy})
    def execute(policy:,confirmation:,expected_digest:)
      request("execute",{"policy"=>policy,"confirmation"=>confirmation,"expected_digest"=>expected_digest})
    end
    def prepare_handoff(**args) = request("handoff/prepare", args.transform_keys(&:to_s))
    def finish_handoff(**args) = request("handoff/finish", args.transform_keys(&:to_s))
    def recover_prepared_handoff(**args) = request("handoff/recover", args.transform_keys(&:to_s))
    def telemetry(handoff_id:) = request("telemetry", {"handoff_id"=>handoff_id}, timeout: 10)
    private
    def request(action,body,timeout:45)
      token=@key_reader.call
      data=@client.send(:post,"/v1/soul/compute/#{action}",body,token,timeout,{})
      {"ok"=>true,"lifecycle_state"=>"complete","reason"=>"compute #{action} complete","data"=>data,"mutation"=>action=="execute" ? "compute_policy_changed" : "none"}
    rescue StandardError => error
      result={"ok"=>false,"lifecycle_state"=>"blocked_for_human_review","reason"=>"Compute unavailable, busy, or changed; finish active work and refresh. No retry was started.","data"=>{},"mutation"=>"none"}
      result["diagnostic_code"]=TelemetryDiagnostic.code(error) if action=="telemetry"
      result
    ensure
      token&.clear
    end
  end
end
