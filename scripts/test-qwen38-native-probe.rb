# frozen_string_literal: true
require "minitest/autorun"
require_relative "run-qwen38-native-probe"

class Qwen38NativeProbeTest < Minitest::Test
  def test_isolated_assets_and_unchanged_core_roster
    trial=Qwen38NativeProbe.allocate
    assert_equal ["qwen3.8-27b"], trial.candidate_assets.keys
    refute DemandLoadedProbes::ASSETS.key?("qwen3.8-27b")
    assert_equal %w[gpt-oss-20b gemma-4-26b-a4b], SoulCore::RosterChatAdapter::MODELS
    assert_equal DemandLoadedProbes::ASSETS, DemandLoadedProbes.allocate.candidate_assets
    assert_equal DemandLoadedProbes::MANIFEST, DemandLoadedProbes.allocate.candidate_manifest
  end
  def test_launch_bounds
    args=Qwen38NativeProbe.argv("qwen3.8-27b","/fixture.gguf")
    {"--host"=>"127.0.0.1","--tensor-split"=>"2,1","--batch-size"=>"32",
     "--ubatch-size"=>"32","--ctx-size"=>"4096","--predict"=>"2048"}.each{|k,v|assert_equal v,args[args.index(k)+1]}
    assert_includes args,"--no-mmap"
    assert_includes args,"--no-context-shift"
    assert_raises(ArgumentError){Qwen38NativeProbe.argv("other","/fixture")}
    t=Qwen38NativeProbe.allocate
    assert_equal 900,Qwen38NativeProbe::BUDGET_SECONDS
    assert_equal 600,t.candidate_seconds
    assert_equal 120,t.request_seconds
    assert_equal 5,t.max_generations
  end
  def test_native_controls_and_no_prompt_mutation
    t=Qwen38NativeProbe.allocate
    input={"messages"=>[{"role"=>"user","content"=>"fixture"}],"model"=>"qwen3.8-27b","max_tokens"=>2048}
    [false,true].each do |on|
      t.instance_variable_set(:@thinking,on)
      p=t.prepare_payload(input)
      assert_equal on,p.dig("chat_template_kwargs","enable_thinking")
      assert_equal false,p.dig("chat_template_kwargs","preserve_thinking")
      assert_equal "low",p.dig("chat_template_kwargs","reasoning_effort")
      assert_equal(on ? 1.0 : 0.7,p["temperature"])
      assert_equal input["messages"],p["messages"]
    end
    refute input.key?("chat_template_kwargs")
  end
  def test_resource_checks_remain_inherited_and_reserve_enforced
    t=Qwen38NativeProbe.allocate
    assert_equal DemandLoadedProbes,Qwen38NativeProbe.instance_method(:run).owner
    # The subclass delegates through existing telemetry/headroom/thermal checks.
    assert_equal DemandLoadedProbes,Qwen38NativeProbe.instance_method(:validate_resources!).super_method.owner
    assert_equal 131_072,MixedGpuPilot::SWAP_OUT_LIMIT_PAGES
  end
  def test_probe_uses_only_literal_tool_result_and_five_calls
    Dir.mktmpdir do |dir|
      File.write(File.join(dir,"props.json"),JSON.generate("chat_template"=>"enable_thinking preserve_thinking reasoning_effort"))
      t=Qwen38NativeProbe.allocate
      t.instance_variable_set(:@output,dir)
      calls=[]
      t.define_singleton_method(:save){|*|}
      t.define_singleton_method(:probe_request) do |messages,tools:nil|
        calls << {messages:Marshal.load(Marshal.dump(messages)),thinking:@thinking,tools:tools}
        if tools && messages.size==1
          {"message"=>{"role"=>"assistant","tool_calls"=>[{"id"=>"fixture-call","function"=>{"name"=>"lookup_parcel","arguments"=>'{"code":"PROBE-17"}'}}]}}
        else
          {"message"=>{"role"=>"assistant","content"=>"fixture"}}
        end
      end
      t.probe
      assert_equal 5,calls.size
      assert_equal [false,false,true,false,false],calls.map{|c|c[:thinking]}
      assert_equal '{"status":"awaiting violet seal"}',calls.last[:messages].last["content"]
      assert_equal "fixture-call",calls.last[:messages].last["tool_call_id"]
    end
  end
end
