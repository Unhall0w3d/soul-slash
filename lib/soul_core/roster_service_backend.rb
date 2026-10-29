# frozen_string_literal: true
require_relative "roster_warm_backend"
require_relative "roster_service_session"
require_relative "roster_request_control"

module SoulCore
  class RosterServiceBackend < RosterWarmBackend
    def initialize(**args)
      raise ArgumentError, "service owner required" unless args[:owner].instance_of?(RosterServiceSession)
      super(**args)
      @request_control = RosterRequestControl.new
    end

    def complete(**args)
      @request_control.run(conversation_id: args.fetch(:conversation_id), request_id: args.fetch(:request_id),
        cancel: args.fetch(:cancel, -> { false }),
        released: -> { status.values_at("state", "available") == ["unloaded", true] }) do |signal|
        super(**args.merge(cancel: signal))
      end
    end

    def cancel_request(**identity) = @request_control.cancel(**identity)
    def request_status(**identity) = @request_control.status(**identity)

    def compute_status
      @mutex.synchronize { @owner.compute_status.merge("available"=>@ready && !@closing && !@finished) }
    end

    def compute_preview(policy:)
      raise ArgumentError,"unknown compute policy" unless %w[available reserved].include?(policy)
      value=compute_status
      record=value.slice("version","revision","policy","handoff")
      value.merge("target_policy"=>policy,"expected_digest"=>Digest::SHA256.hexdigest(JSON.generate([record,policy])),"confirmation_phrase"=>"SET_COMPUTE_POLICY")
    end

    def compute_execute(**args)
      control { @owner.compute_control(**args) }
      compute_status
    end

    def prepare_handoff(**args) = control { @owner.prepare_handoff(**args) }
    def finish_handoff(**args) = control { @owner.finish_handoff(**args) }
    def recover_prepared_handoff(**args) = control { @owner.recover_prepared_handoff(**args) }
    def creative_telemetry(**args) = control { @owner.creative_telemetry(**args) }

    def control(&operation)
      job={args:{},control:operation}
      @mutex.synchronize do
        raise RosterRuntimeOwner::Unavailable,"coordinator unavailable" unless @ready && !@closing && !@finished
        raise RosterRuntimeOwner::Unavailable,"work active; finish or explicitly stop it first" if @job
        @job=job; @changed.broadcast
        @changed.wait(@mutex) until job[:done] || @finished
        raise RosterRuntimeOwner::Unavailable,"control interrupted; inspect policy" unless job[:done]
        raise job[:error] if job[:error]
        job[:value]
      end
    end

    def run
      super(seconds: nil) { yield self }
    end

    def status
      @mutex.synchronize do
        @owner.status.merge("available" => @ready && !@closing && !@finished,
          "read_only_skills" => (@gateway_class.respond_to?(:read_only_skills?) && @gateway_class.read_only_skills?),
          "memory_policy" => (@memory ? "approved_shared_and_member_scoped_v1" : "none"),
          "journal_record_limit" => RosterConversationGateway::LIMIT,
          "journal_conversation_limit" => (@memory ? nil : 16),
          "journal_record_limit_scope" => (@gateway_class.respond_to?(:capacity_policy) ? "conversation" : "journal"),
          "journal_capacity_policy" => (@gateway_class.respond_to?(:capacity_policy) ? @gateway_class.capacity_policy : (@memory ? "shared_record_budget" : "legacy_conversation_and_record_limits")))
      end
    end

    private
    # The immutable journal still enforces its durable quotas. There is no
    # arbitrary six-request lifetime for an explicitly installed coordinator.
    def consume_request! = nil
  end
end
