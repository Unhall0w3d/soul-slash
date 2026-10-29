# frozen_string_literal: true
require "minitest/autorun"
require_relative "run-roster-journal-trial"

class RosterJournalTrialTest < Minitest::Test
  def test_phase_timing_preserves_values_failures_and_checks
    trial=RosterJournalTrial.allocate
    clock=10.0
    records={}
    trial.define_singleton_method(:now) { clock }
    trial.define_singleton_method(:save) { |name,data| records[name]=data }
    result=trial.timed_phase("model_integrity") { clock=12.5; :verified }
    assert_equal :verified,result
    assert_equal 2.5,records["phase-model_integrity.json"]["elapsed_seconds"]
    assert_equal "complete",records["phase-model_integrity.json"]["state"]
    assert_raises(ChatReplacementTrial::Abort) do
      trial.timed_phase("cooldown") { clock=13; raise ChatReplacementTrial::Abort,"fixture" }
    end
    assert_equal "failed",records["phase-cooldown.json"]["state"]
    assert_equal "ChatReplacementTrial::Abort",records["phase-cooldown.json"]["error_class"]
    assert_equal "fixture",records["phase-cooldown.json"]["guard_reason"]
    begin
      raise ChatReplacementTrial::Abort,"outer cancellation"
    rescue ChatReplacementTrial::Abort
      trial.timed_phase("teardown") { :released }
      assert_nil records["phase-teardown.json"]["error_class"]
      assert_nil records["phase-teardown.json"]["guard_reason"]
    end
    trial.define_singleton_method(:save) { |*| raise IOError,"fixture diagnostic failure" }
    error=assert_raises(ChatReplacementTrial::Abort) { trial.timed_phase("teardown") { raise ChatReplacementTrial::Abort,"original" } }
    assert_equal "original",error.message
    assert_raises(IOError) { trial.timed_phase("teardown") { true } }
    assert_raises(ArgumentError) { trial.timed_phase("unknown") { flunk "must not yield" } }
  end

  def test_actual_runner_reports_initial_abort_and_always_tears_down
    Dir.mktmpdir("roster-runner-failure-") do |root|
      trial=RosterJournalTrial.allocate
      records,operations={},[]
      trial.instance_variable_set(:@samples,[])
      trial.define_singleton_method(:create_output) { root }
      trial.define_singleton_method(:protected_state) { {"unit"=>"ActiveState=inactive","amd_units"=>"ActiveState=inactive\nActiveState=inactive"} }
      trial.define_singleton_method(:port_closed?) { true }
      trial.define_singleton_method(:start_telemetry) { raise ChatReplacementTrial::Abort,"fixture initial abort" }
      trial.define_singleton_method(:cleanup_owned_runtime) { operations << :cleanup }
      trial.define_singleton_method(:stop_telemetry) { operations << :telemetry }
      trial.define_singleton_method(:save) { |name,value| records[name]=value }
      capture_io { refute trial.run }
      assert_equal [:cleanup,:telemetry],operations
      assert_equal "failed",records.fetch("receipt.json")["state"]
      assert_includes records.fetch("receipt.json")["error"],"fixture initial abort"
      refute_includes records.fetch("receipt.json")["error"],"NameError"
      operations.clear
      trial.define_singleton_method(:cleanup_owned_runtime) { operations << :cleanup; raise ChatReplacementTrial::Abort,"fixture cleanup abort" }
      capture_io { refute trial.run }
      assert_equal [:cleanup,:telemetry],operations
      assert_includes records.fetch("receipt.json")["error"],"fixture cleanup abort"
      assert_includes records.fetch("receipt.json")["error"],"fixture initial abort"
    end
  end

  def test_binding_and_launch_preserve_qualified_defaults
    trial=RosterJournalTrial.allocate
    binding=trial.roster_binding
    assert_equal SoulCore::RosterChatAdapter::MODELS.sort,binding.keys.sort
    binding.each do |id,identity|
      args=RosterJournalTrial.argv(id,RosterJournalTrial::ASSETS.fetch(id).fetch("path"))
      assert_equal "127.0.0.1",args[args.index("--host")+1]
      assert_equal "4096",args[args.index("--ctx-size")+1]
      assert_equal "2,1",args[args.index("--tensor-split")+1]
      assert_equal RosterJournalTrial::BINARY_SHA,identity["server_sha256"]
      assert_equal id=="gemma-4-26b-a4b",args.include?("--no-mmap")
    end
    assert_equal 600,RosterJournalTrial::BUDGET_SECONDS
    assert_equal DemandLoadedProbes,RosterJournalTrial.instance_method(:validate_resources!).owner
    assert_equal MixedGpuPilot,RosterJournalTrial.instance_method(:http).owner
    assert_equal ChatReplacementTrial,RosterJournalTrial.instance_method(:cleanup_owned_runtime).owner
  end

  def test_actual_runner_abort_after_journal_creation_preserves_original_error
    Dir.mktmpdir("roster-runner-journal-") do |root|
      trial=RosterJournalTrial.allocate
      records,operations={},[]
      trial.instance_variable_set(:@samples,[])
      trial.define_singleton_method(:create_output) { root }
      trial.define_singleton_method(:protected_state) { {"unit"=>"ActiveState=inactive","amd_units"=>"ActiveState=inactive\nActiveState=inactive"} }
      trial.define_singleton_method(:port_closed?) { true }
      trial.define_singleton_method(:start_telemetry) {}
      trial.define_singleton_method(:sample_resources) { {} }
      trial.define_singleton_method(:desktop_baseline) { |_| [] }
      trial.define_singleton_method(:validate_resources!) { |*a,**kw| true }
      trial.define_singleton_method(:runtime_lease_store) { SoulCore::ModelRuntimeLeaseStore.new(root:root) }
      trial.define_singleton_method(:roster_start) { |**kw| raise ChatReplacementTrial::Abort,"fixture load abort" }
      trial.define_singleton_method(:roster_stop) { |**kw| operations << :owned_stop; true }
      trial.define_singleton_method(:cleanup_owned_runtime) { operations << :outer_cleanup }
      trial.define_singleton_method(:stop_telemetry) { operations << :telemetry }
      trial.define_singleton_method(:save) { |name,value| records[name]=value }
      capture_io { refute trial.run }
      assert_equal [:owned_stop,:outer_cleanup,:telemetry],operations
      assert_includes records.fetch("receipt.json")["error"],"fixture load abort"
      assert File.file?(File.join(root,"journal/r-000001.json"))
      assert_empty Dir.children(File.join(root,"Soul/runtime/model_runtime/leases"))
    end
  end

  def test_driver_transport_rejects_arbitrary_routes
    trial=Object.new
    calls=[]
    trial.define_singleton_method(:roster_bounded) { |_,&b| b.call }
    trial.define_singleton_method(:adapter_http) { |*args,**kw| calls << [args,kw]; {} }
    driver=RosterJournalTrial::Driver.new(trial)
    assert_raises(ChatReplacementTrial::Abort) { driver.request("POST","http://foreign",{},deadline:100) }
    assert_raises(ChatReplacementTrial::Abort) { driver.request("GET","/tokenize",{},deadline:100) }
    assert_empty calls
    driver.request("POST","/tokenize",{},deadline:100)
    assert_equal 1,calls.length
  end

  def test_exec_wrapper_identity_and_environment_are_both_enforced
    RosterJournalTrial::IDS.each do |id|
      launch=RosterJournalTrial.argv(id,RosterJournalTrial::ASSETS.fetch(id).fetch("path"))
      argv=launch.drop(6)
      env="VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json\0VK_LOADER_LAYERS_DISABLE=~implicit~\0GGML_VK_VISIBLE_DEVICES=0\0CUDA_VISIBLE_DEVICES=0\0"
      validate=->(a,e,l=launch) { RosterJournalTrial.validate_process_launch!(launch:l,argv:a,environment:e) }
      assert validate.call(argv,env)
      assert_raises(ChatReplacementTrial::Abort) { validate.call(launch,env) }
      assert_raises(ChatReplacementTrial::Abort) { validate.call(argv+["--other"],env) }
      changed=argv.dup; changed[changed.index("--model")+1]="foreign.gguf"
      assert_raises(ChatReplacementTrial::Abort) { validate.call(changed,env) }
      assert_raises(ChatReplacementTrial::Abort) { validate.call(argv,env.sub("CUDA_VISIBLE_DEVICES=0","CUDA_VISIBLE_DEVICES=1")) }
      assert_raises(ChatReplacementTrial::Abort) { validate.call(argv,env+"CUDA_VISIBLE_DEVICES=0\0") }
      assert_raises(ChatReplacementTrial::Abort) { validate.call(argv,env+"VK_ICD_FILENAMES=foreign\0") }
      assert_raises(ChatReplacementTrial::Abort) { validate.call(argv,env,launch.drop(1)) }
    end
  end

  def test_real_env_exec_replaces_wrapper_without_loading_a_model
    source='require "json"; puts JSON.generate({"argv"=>File.binread("/proc/self/cmdline").split("\0"),"vulkan"=>ENV["GGML_VK_VISIBLE_DEVICES"],"removed"=>ENV.key?("VK_ICD_FILENAMES")})'
    launch=["/usr/bin/env","-u","VK_ICD_FILENAMES",
      "VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json",
      "VK_LOADER_LAYERS_DISABLE=~implicit~","GGML_VK_VISIBLE_DEVICES=0",RbConfig.ruby,"-e",source]
    output=Timeout.timeout(5) { IO.popen(launch,"r") { |io| io.read(16384) } }
    assert $?.success?
    observed=JSON.parse(output)
    assert_equal launch.drop(6),observed["argv"]
    assert_equal "0",observed["vulkan"]
    assert_equal false,observed["removed"]
  end
end
