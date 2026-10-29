# frozen_string_literal: true
require_relative "test-roster-service-backend"

class SharedComputeTest < RosterServiceBackendTest
  %w[amd-visual amd-music].each do |provider|
  define_method("test_telemetry_requires_authenticated_exact_running_#{provider}_handoff") do
    calls=[]
    @driver.define_singleton_method(:creative_release_verified?) { |**_| true }
    @driver.define_singleton_method(:creative_telemetry) { calls << true; {"fixture"=>true} }
    app=SoulRosterCoordinator::Application.new(backend:@backend,bearer_token:"a"*64)
    headers={"Authorization"=>"Bearer #{"a"*64}"}
    route="/v1/soul/compute/telemetry"
    @backend.run do
      assert_equal 401,app.call(method:"POST",target:route,headers:{},body:'{}').status
      assert_equal 403,app.call(method:"POST",target:route,headers:headers.merge("Origin"=>"foreign"),body:'{}').status
      assert_equal 422,app.call(method:"POST",target:route,headers:headers,body:'{}').status
      assert_equal 405,app.call(method:"GET",target:route,headers:headers,body:'{}').status
      assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) { @backend.creative_telemetry(handoff_id:"a"*32) }
      h=@backend.prepare_handoff(provider_id:provider,request_id:"probe",conversation_id:"project",member:"studio",input_digest:"a"*64).fetch("handoff")
      assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) { @backend.creative_telemetry(handoff_id:h["handoff_id"]) }
      lease=@leases.acquire_exclusive(provider_id:provider,request_id:"probe",conversation_id:"project",model_id:"fixture",resource_group:"amd-vulkan-generation")
      assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) { @backend.creative_telemetry(handoff_id:"b"*32) }
      before=@backend.compute_status
      response=app.call(method:"POST",target:route,headers:headers,body:JSON.generate(handoff_id:h["handoff_id"]))
      assert_equal 200,response.status
      assert_equal({"fixture"=>true},JSON.parse(response.body))
      assert_equal before,@backend.compute_status
      assert_equal 1,calls.size
      @leases.release(lease["lease_id"])
      @backend.finish_handoff(handoff_id:h["handoff_id"],outcome:"failed",result_digest:"b"*64)
      assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) { @backend.creative_telemetry(handoff_id:h["handoff_id"]) }
    end
  end
  end
  def request(id)
    {conversation_id:id,request_id:id,adapter:SoulCore::RosterChatAdapter.new(model:"gpt-oss-20b"),messages:[{"role"=>"user","content"=>"Hi"}],deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+30}
  end
  def change(policy)
    preview=@backend.compute_preview(policy:policy)
    @backend.compute_execute(policy:policy,expected_digest:preview.fetch("expected_digest"),confirmation:preview.fetch("confirmation_phrase"))
  end
  def test_reservation_unloads_and_survives_reconstruction_and_blocks_all_admission
    @backend.run do
      @backend.complete(**request("first"))
      result=change("reserved")
      assert_equal "unloaded",result["state"]
      assert_equal "reserved",result["policy"]
      assert_equal 1,@driver.stops.size
      fresh=SoulCore::ModelRuntimeLeaseStore.new(root:@tmp)
      assert_equal "reserved",fresh.with_control_lock { fresh.compute_policy_unlocked.read["policy"] }
      assert_raises(SoulCore::SharedComputePolicy::Refused) { fresh.acquire(provider_id:"image",model_id:"fixture",request_id:"x") }
      assert_raises(SoulCore::SharedComputePolicy::Refused) { @backend.complete(**request("second")) }
      assert_equal 1,@driver.starts.size
      change("available")
      assert_equal 1,@driver.starts.size, "availability must not eagerly load"
      assert_equal "Hello",@backend.complete(**request("third"))["content"]
    end
  end
  def test_preview_binds_revision_target_and_confirmation
    @backend.run do
      p=@backend.compute_preview(policy:"reserved")
      assert_raises(ArgumentError) { @backend.compute_execute(policy:"reserved",expected_digest:p["expected_digest"],confirmation:"wrong") }
      assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) { @backend.compute_execute(policy:"available",expected_digest:p["expected_digest"],confirmation:p["confirmation_phrase"]) }
      change("reserved")
      assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) { @backend.compute_execute(policy:"reserved",expected_digest:p["expected_digest"],confirmation:p["confirmation_phrase"]) }
    end
  end
  def test_authentication_origin_and_exact_compute_shape
    app=SoulRosterCoordinator::Application.new(backend:@backend,bearer_token:"a"*64)
    @backend.run do
      assert_equal 401,app.call(method:"POST",target:"/v1/soul/compute/status",headers:{},body:"{}").status
      headers={"Authorization"=>"Bearer #{"a"*64}"}
      assert_equal 403,app.call(method:"POST",target:"/v1/soul/compute/status",headers:headers.merge("Origin"=>"http://foreign"),body:"{}").status
      assert_equal 422,app.call(method:"POST",target:"/v1/soul/compute/status",headers:headers,body:'{"policy":"reserved"}').status
      assert_equal 200,app.call(method:"POST",target:"/v1/soul/compute/status",headers:headers,body:'{}').status
      assert_empty @driver.starts
    end
  end

  def test_handoff_matches_exact_workload_and_retains_attributed_result
    @driver.define_singleton_method(:creative_release_verified?) { |**_| true }
    @backend.run do
      @backend.complete(**request("origin"))
      h=@backend.prepare_handoff(provider_id:"amd-visual",request_id:"candidate",conversation_id:"project",member:"gpt-oss-20b",input_digest:"a"*64).fetch("handoff")
      assert_equal "released",h["state"]
      assert_equal 1,@driver.stops.size
      assert_raises(SoulCore::SharedComputePolicy::Refused) { @backend.complete(**request("interloper")) }
      lease=@leases.acquire_exclusive(provider_id:"amd-visual",request_id:"candidate",conversation_id:"project",model_id:"fixture",resource_group:"amd-vulkan-generation")
      assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) { @backend.finish_handoff(handoff_id:h["handoff_id"],outcome:"complete",result_digest:"b"*64) }
      @leases.release(lease["lease_id"])
      @backend.finish_handoff(handoff_id:h["handoff_id"],outcome:"complete",result_digest:"b"*64)
      assert_nil @backend.compute_status["handoff"]
      result=JSON.parse(File.read(File.join(@tmp,"Soul/runtime/model_runtime/handoff-#{h['handoff_id']}.json")))
      assert_equal "gpt-oss-20b",result["member"]
      assert_equal "pending",result["follow_up"]
      assert_equal "b"*64,result["result_digest"]
      assert_equal 1,@driver.starts.size,"handoff completion must not fabricate a follow-up or eager load"
    end
  end

  def test_failed_handoff_release_retains_hold_across_reconstruction
    @driver.define_singleton_method(:creative_release_verified?) { |**_| true }
    @backend.run do
      h=@backend.prepare_handoff(provider_id:"amd-music",request_id:"candidate",conversation_id:"project",member:"gpt-oss-20b",input_digest:"a"*64)["handoff"]
      @driver.define_singleton_method(:creative_release_verified?) { |**_| false }
      assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) { @backend.finish_handoff(handoff_id:h["handoff_id"],outcome:"failed",result_digest:"b"*64) }
      fresh=SoulCore::ModelRuntimeLeaseStore.new(root:@tmp)
      assert_equal "prepared",fresh.with_control_lock { fresh.compute_policy_unlocked.read.dig("handoff","state") }
      assert_raises(SoulCore::SharedComputePolicy::Refused) { fresh.acquire(provider_id:"amd-music",request_id:"candidate",conversation_id:"project",model_id:"fixture") }
      assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) { change("available") }
    end
  end
end
