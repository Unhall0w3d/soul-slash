# frozen_string_literal: true
require_relative "test-roster-service-backend"
require_relative "../lib/soul_core/creative_compute_handoff"
require_relative "../lib/soul_core/visual_studio_service"
require_relative "../lib/soul_core/music_resource_coordinator"
require_relative "../lib/soul_core/music_generation_service"

class CreativeComputeHandoffTest < RosterServiceBackendTest
  class Control
    def initialize(backend) = @backend = backend
    def status = {"ok"=>true,"data"=>@backend.compute_status}
    def prepare_handoff(**args) = {"ok"=>true,"data"=>@backend.prepare_handoff(**args)}
    def finish_handoff(**args) = {"ok"=>true,"data"=>@backend.finish_handoff(**args)}
  end

  def bridge
    @driver.define_singleton_method(:creative_release_verified?) { |provider_id:| raise 'wrong provider' unless %w[amd-visual amd-music].include?(provider_id); true }
    SoulCore::CreativeComputeHandoff.new(control: Control.new(@backend))
  end

  def test_visual_native_lease_seam_releases_before_attributed_finish_and_consumes_admission
    handoff = bridge
    service = SoulCore::VisualStudioService.allocate
    service.instance_variable_set(:@compute_handoff, handoff)
    service.instance_variable_set(:@generation_lease_store, @leases)
    @backend.run do
      result = handoff.with_origin(member: "gpt-oss-20b", conversation_id: "chat_original") do
        service.send(:with_amd_generation_lease, project_id: "visual_project", request_id: "candidate", model_id: "fixture", timeout_seconds: 5, input_digest: "a"*64) do
          assert_equal "running", @backend.compute_status.dig("handoff", "state")
          assert_equal "gpt-oss-20b", @backend.compute_status.dig("handoff", "member")
          assert_equal 1, @leases.active_leases.length
          {"ok"=>true,"lifecycle_state"=>"blocked_for_human_review","data"=>{"candidate"=>"candidate"}}
        end
      end
      assert result["ok"]
      assert_empty @leases.active_leases
      assert_nil @backend.compute_status["handoff"]
      record = JSON.parse(File.read(Dir[File.join(@tmp,"Soul/runtime/model_runtime/handoff-*.json")].fetch(0)))
      assert_equal "chat_original", record["origin_conversation_id"]
      assert_equal "visual_project", record["conversation_id"]
      assert_equal Digest::SHA256.hexdigest(JSON.generate(result)), record["result_digest"]
      assert_equal "pending", record["follow_up"]
      assert_empty @driver.starts
    end
  end

  def test_same_candidate_cannot_acquire_twice_even_after_lease_is_removed
    handoff = bridge
    @backend.run do
      assert_raises(SoulCore::SharedComputePolicy::Refused) do
        handoff.run(provider_id: "amd-visual", project_id: "project", request_id: "candidate", input_digest: "a"*64) do
          lease = @leases.acquire(provider_id: "amd-visual", conversation_id: "project", request_id: "candidate", model_id: "fixture")
          @leases.release(lease["lease_id"])
          @leases.acquire(provider_id: "amd-visual", conversation_id: "project", request_id: "candidate", model_id: "fixture")
        end
      end
      assert_equal "running", @backend.compute_status.dig("handoff", "state")
      assert_empty Dir[File.join(@tmp,"Soul/runtime/model_runtime/handoff-*.json")]
    end
  end

  def test_music_native_execution_releases_lease_before_handoff_finish
    handoff = bridge
    service = SoulCore::MusicGenerationService.allocate
    store = Object.new
    directory = File.join(@tmp, "music-fixture")
    Dir.mkdir(directory)
    store.define_singleton_method(:read) { |_| {} }
    store.define_singleton_method(:generations_path) { |_| directory }
    store.define_singleton_method(:input_payload) { |_| {"duration"=>10} }
    store.define_singleton_method(:generation_input_digest) { |_| "b"*64 }
    coordinator = Object.new
    leases = @leases
    coordinator.define_singleton_method(:acquire) do |project_id:, candidate_id:, **_|
      leases.acquire(provider_id:"amd-music",conversation_id:project_id,request_id:candidate_id,model_id:"fixture")
    end
    coordinator.define_singleton_method(:release) { |id| leases.release(id) }
    service.instance_variable_set(:@store, store)
    service.instance_variable_set(:@coordinator, coordinator)
    service.instance_variable_set(:@compute_handoff, handoff)
    service.instance_variable_set(:@clock, -> { Time.now.utc })
    service.instance_variable_set(:@monotonic_clock, -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    service.define_singleton_method(:generation_scope) { |*_| {"fixture"=>true} }
    service.define_singleton_method(:environment_blockers) { [] }
    service.define_singleton_method(:verify_checkpoints!) { true }
    service.define_singleton_method(:generation_timeout) { |_| 5 }
    service.define_singleton_method(:resource_lane) { "amd-music" }
    test = self
    service.define_singleton_method(:run_generation) do |*args|
      test.assert_equal 1, leases.active_leases.length
      SoulCore::MusicGenerationService::ProcessResult.new(status:"canceled",stdout:"",stderr:"",exit_status:1,pid:0)
    end
    service.define_singleton_method(:quarantined_outcome) { |*_| {"ok"=>false,"lifecycle_state"=>"canceled"} }
    @backend.run do
      result = service.generation_execute(project_id:"project",candidate_id:"candidate_#{'a'*16}",confirmation:SoulCore::MusicGenerationService::CONFIRMATION,expected_digest:Digest::SHA256.hexdigest(JSON.generate({"fixture"=>true})))
      assert_equal "canceled", result["lifecycle_state"]
      assert_empty leases.active_leases
      assert_nil @backend.compute_status["handoff"]
      record = JSON.parse(File.read(Dir[File.join(@tmp,"Soul/runtime/model_runtime/handoff-*.json")].fetch(0)))
      assert_equal "canceled", record["outcome"]
      assert_equal "amd-music", record["provider_id"]
    end
  end

  def test_interruption_retains_hold_and_origin_scope_does_not_leak
    handoff = bridge
    @backend.run do
      assert_raises(Interrupt) do
        handoff.with_origin(member: "gpt-oss-20b", conversation_id: "chat_original") do
          handoff.run(provider_id: "amd-visual", project_id: "project", request_id: "candidate", input_digest: "a"*64) { raise Interrupt }
        end
      end
      assert_equal "released", @backend.compute_status.dig("handoff", "state")
      assert_empty @driver.starts
    end
  end

  def test_direct_studio_is_not_attributed_to_a_model
    handoff = bridge
    @backend.run do
      handoff.run(provider_id: "amd-music", project_id: "project", request_id: "candidate", input_digest: "a"*64) do
        assert_equal "studio", @backend.compute_status.dig("handoff", "member")
        {"ok"=>false,"lifecycle_state"=>"canceled"}
      end
      record=JSON.parse(File.read(Dir[File.join(@tmp,"Soul/runtime/model_runtime/handoff-*.json")].fetch(0)))
      assert_equal "canceled", record["outcome"]
      assert_equal "studio", record["member"]
    end
  end

  def test_unverified_admission_retains_prepared_hold_without_starting_work
    handoff=bridge
    @driver.define_singleton_method(:creative_release_verified?) { |provider_id:| false }
    @backend.run do
      assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) do
        handoff.run(provider_id:"amd-visual",request_id:"candidate",project_id:"project",input_digest:"a"*64) { flunk "work must not start" }
      end
      assert_equal "prepared",@backend.compute_status.dig("handoff","state")
      assert_empty @driver.starts
    end
  end

  def test_http_handoff_requires_authentication_and_exact_shape
    app=SoulRosterCoordinator::Application.new(backend:@backend,bearer_token:"a"*64)
    body=JSON.generate(provider_id:"amd-visual",conversation_id:"project",origin_conversation_id:"project",request_id:"candidate",member:"studio",input_digest:"a"*64)
    @backend.run do
      assert_equal 401,app.call(method:"POST",target:"/v1/soul/compute/handoff/prepare",headers:{},body:body).status
      headers={"Authorization"=>"Bearer #{'a'*64}"}
      assert_equal 403,app.call(method:"POST",target:"/v1/soul/compute/handoff/prepare",headers:headers.merge("Origin"=>"https://foreign.invalid"),body:body).status
      assert_equal 422,app.call(method:"POST",target:"/v1/soul/compute/handoff/prepare",headers:headers,body:'{}').status
      assert_nil @backend.compute_status["handoff"]
    end
  end

  def prepared_recovery_args
    handoff=bridge
    @driver.define_singleton_method(:creative_release_verified?) { |provider_id:| false }
    assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) do
      handoff.run(provider_id:"amd-visual",request_id:"candidate",project_id:"project",input_digest:"a"*64) { flunk "must not launch" }
    end
    state=@leases.with_control_lock { @leases.compute_policy_unlocked.read }
    {handoff_id:state.fetch("handoff").fetch("handoff_id"),expected_digest:Digest::SHA256.hexdigest(JSON.generate(state)),confirmation:"RECOVER_PREPARED_HANDOFF",result_digest:"b"*64}
  end

  def test_explicit_recovery_records_failure_and_rejects_replay
    @backend.run do
      args=prepared_recovery_args
      @driver.define_singleton_method(:creative_release_verified?) { |provider_id:| true }
      assert_nil @backend.recover_prepared_handoff(**args)["handoff"]
      record=JSON.parse(File.read(Dir[File.join(@tmp,"Soul/runtime/model_runtime/handoff-*.json")].fetch(0)))
      assert_equal "failed",record["outcome"]
      assert_equal "explicit_prepared_handoff",record["recovery"]
      assert_equal args[:result_digest],record["result_digest"]
      assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) { @backend.recover_prepared_handoff(**args) }
      assert_empty @driver.starts
    end
  end

  def test_recovery_refuses_unverified_release_stale_state_and_wrong_confirmation
    @backend.run do
      args=prepared_recovery_args
      assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) { @backend.recover_prepared_handoff(**args) }
      @driver.define_singleton_method(:creative_release_verified?) { |provider_id:| true }
      [args.merge(expected_digest:"0"*64),args.merge(handoff_id:"0"*32)].each do |bad|
        assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) { @backend.recover_prepared_handoff(**bad) }
      end
      [args.merge(confirmation:"yes"),args.merge(result_digest:"invalid")].each do |bad|
        assert_raises(ArgumentError) { @backend.recover_prepared_handoff(**bad) }
      end
      assert_equal "prepared",@backend.compute_status.dig("handoff","state")
      assert_empty Dir[File.join(@tmp,"Soul/runtime/model_runtime/handoff-*.json")]
    end
  end

  def test_recovery_http_keeps_auth_origin_and_exact_shape_guards
    app=SoulRosterCoordinator::Application.new(backend:@backend,bearer_token:"a"*64)
    @backend.run do
      args=prepared_recovery_args
      body=JSON.generate(args)
      target="/v1/soul/compute/handoff/recover"
      headers={"Authorization"=>"Bearer #{'a'*64}"}
      assert_equal 401,app.call(method:"POST",target:target,headers:{},body:body).status
      assert_equal 403,app.call(method:"POST",target:target,headers:headers.merge("Origin"=>"https://foreign.invalid"),body:body).status
      assert_equal 422,app.call(method:"POST",target:target,headers:headers,body:JSON.generate(args.merge(extra:true))).status
      assert_equal "prepared",@backend.compute_status.dig("handoff","state")
    end
  end

  def test_recovery_cannot_clear_a_remaining_lease_or_overwrite_an_audit_record
    @backend.run do
      args=prepared_recovery_args
      @driver.define_singleton_method(:creative_release_verified?) { |provider_id:| true }
      original=@leases.method(:leases_for_quiescent_admission_unlocked)
      @leases.define_singleton_method(:leases_for_quiescent_admission_unlocked) { [{"lease_id"=>"foreign"}] }
      assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) { @backend.recover_prepared_handoff(**args) }
      @leases.define_singleton_method(:leases_for_quiescent_admission_unlocked,original)
      @leases.with_control_lock do
        store=@leases.compute_policy_unlocked
        store.record_handoff(store.read.fetch("handoff").merge("outcome"=>"failed"))
      end
      assert_raises(Errno::EEXIST) { @backend.recover_prepared_handoff(**args) }
      assert_equal "prepared",@backend.compute_status.dig("handoff","state")
    end
  end

  def test_music_shared_admission_has_no_fallback_dependency_and_honors_reservation
    coordinator = SoulCore::MusicResourceCoordinator.new(root: @tmp, lane: "amd-music", shared_compute: true, model_lease_store: @leases)
    hardware = {"active_core_id"=>nil,"fallback_state"=>"inactive","gemma_state"=>"inactive","amd_vulkan_state"=>"available"}
    assert_empty coordinator.send(:amd_blockers, hardware, nil)
    assert_includes coordinator.send(:amd_blockers, hardware.merge("fallback_state"=>"active"), nil), "Legacy NVIDIA runtime must be stopped"
    @leases.with_control_lock do
      store=@leases.compute_policy_unlocked
      store.write(store.read.merge("policy"=>"reserved","revision"=>1))
    end
    assert_includes coordinator.send(:amd_blockers, hardware, nil), "Compute reserved for the user"
  end

  def test_lost_finish_response_never_retries_or_relabels_result
    control=Object.new
    calls=[]
    control.define_singleton_method(:prepare_handoff) { |**args| calls << :prepare; {"ok"=>true,"data"=>{"handoff"=>{"handoff_id"=>"a"*32}}} }
    control.define_singleton_method(:finish_handoff) { |**args| calls << :finish; {"ok"=>false} }
    handoff=SoulCore::CreativeComputeHandoff.new(control:control)
    assert_raises(SoulCore::CreativeComputeHandoff::Unavailable) do
      handoff.run(provider_id:"amd-visual",request_id:"candidate",project_id:"project",input_digest:"a"*64) { calls << :work; {"ok"=>true} }
    end
    assert_equal [:prepare,:work,:finish],calls
  end
end
