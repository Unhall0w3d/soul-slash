#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "compare-continuity-a25"

checks = 0
check = lambda { |label, value| raise "FAIL #{label}" unless value; checks += 1 }
raises = lambda do |&block|
  begin
    block.call
    false
  rescue AmdReviewerPilotM2::Stop, ArgumentError
    true
  end
end
runner = ContinuityComparisonA25
protocol = ContinuityProtocolA25
item = protocol.feasibility_item
entry = protocol.feasibility_plan.first
payload = protocol.payload(item: item, thinking: false, contract: "strict", seed: protocol::SEEDS.first)
body = {
  "choices" => [{ "finish_reason" => "stop", "message" => { "role" => "assistant", "content" => JSON.generate(item.fetch("expected")) } }],
  "usage" => { "prompt_tokens" => 64, "completion_tokens" => 24, "prompt_tokens_details" => { "cached_tokens" => 0 } },
  "__verbose" => { "prompt" => "fixture<|im_start|>assistant\n<think>\n\n</think>\n\n", "generation_settings" => payload.slice("temperature", "top_p", "top_k", "min_p", "presence_penalty", "repeat_penalty", "seed").merge("n_predict" => 768, "lora" => [], "grammar" => "fixture nonempty grammar") }
}
copy = ->(value) { Marshal.load(Marshal.dump(value)) }
check.call("matched native effective settings", runner.validate_effective!(body, payload))
%w[temperature top_p top_k min_p presence_penalty repeat_penalty seed n_predict].each do |key|
  bad = copy.call(body)
  bad["__verbose"]["generation_settings"][key] += 1
  check.call("reject changed #{key}", raises.call { runner.validate_effective!(bad, payload) })
end
[["lora", ["unapproved"]]].each do |key, value|
  bad = copy.call(body); bad["__verbose"]["generation_settings"][key] = value
  check.call("reject adapter", raises.call { runner.validate_effective!(bad, payload) })
end
bad = copy.call(body); bad.delete("__verbose")
check.call("missing readback rejected", raises.call { runner.validate_effective!(bad, payload) })
bad = copy.call(body); bad["__verbose"].delete("prompt")
check.call("actual prompt required", raises.call { runner.validate_effective!(bad, payload) })
bad = copy.call(body); bad["__verbose"]["generation_settings"]["grammar"] = ""
check.call("strict grammar required", raises.call { runner.validate_effective!(bad, payload) })
[["prompt_tokens", 1537], ["completion_tokens", 769], ["completion_tokens", -1]].each do |key, value|
  bad = copy.call(body); bad["usage"][key] = value
  check.call("observed #{key} bound", raises.call { runner.validate_effective!(bad, payload) })
end
bad = copy.call(body); bad["usage"]["prompt_tokens_details"]["cached_tokens"] = 1
check.call("prompt reuse rejected", raises.call { runner.validate_effective!(bad, payload) })
check.call("all protocol cells frozen", runner.frozen_protocol.fetch("plans").values.sum(&:length) == 306)

qwen_on = "fixture<|im_start|>assistant\n"
amd_on = "fixture<|im_start|>assistant\n<think>\n"
off = body.dig("__verbose", "prompt")
check.call("Qwen native thinking-on header accepted", runner.validate_native_branch!("qwen", true, qwen_on) == true)
check.call("AMD native thinking-on marker accepted", runner.validate_native_branch!("amd", true, amd_on) == true)
%w[qwen amd].each do |model|
  check.call("#{model} native thinking-off closure accepted", runner.validate_native_branch!(model, false, off) == true)
end
branch_rejected = lambda do |model, thinking, template|
  runner.validate_native_branch!(model, thinking, template)
  false
rescue AmdReviewerPilotM2::Stop
  true
end
check.call("unknown native model rejected", branch_rejected.call("other", true, qwen_on))
check.call("nonboolean native branch rejected", branch_rejected.call("qwen", "true", qwen_on) &&
  branch_rejected.call("amd", nil, off))
check.call("invalid native template types rejected", branch_rejected.call("qwen", true, nil) &&
  branch_rejected.call("qwen", true, 7) && branch_rejected.call("qwen", true, "") &&
  branch_rejected.call("qwen", true, "\xFF".b.force_encoding(Encoding::UTF_8)))
check.call("oversized native template rejected", branch_rejected.call("qwen", true, "x" * 65_537 + qwen_on))
check.call("cross-family native thinking-on markers rejected", branch_rejected.call("qwen", true, amd_on) &&
  branch_rejected.call("amd", true, qwen_on))
check.call("wrong native branch rejected", branch_rejected.call("qwen", false, qwen_on) &&
  branch_rejected.call("amd", false, amd_on) && branch_rejected.call("qwen", true, off) &&
  branch_rejected.call("amd", true, off))
check.call("trailing native template bytes rejected", branch_rejected.call("qwen", true, qwen_on + " ") &&
  branch_rejected.call("amd", true, amd_on + "\n") && branch_rejected.call("qwen", false, off + "\n") &&
  branch_rejected.call("amd", false, off + "x"))

class A25FixtureRunner < ContinuityComparisonA25
  attr_accessor :reply, :token_count, :branch, :generation_counter, :simulate_timeout
  attr_reader :calls
  def initialize(output:, reply:)
    super(series: "/not-used", seed: Protocol::SEEDS.first)
    @output, @reply, @token_count, @branch, @calls = output, reply, 64, false, []
  end
  def qwen_observe! = true
  def qwen_quiescent! = (@qwen_inflight = false)
  def endpoint_owned! = true
  def owned_drm = { "fixture" => true }
  def amd_cooldown! = 3
  def http(*) = { "model_alias" => "fixture-amd" }
  def native_http(model, path, payload, seconds:)
    @calls << { "model" => model, "path" => path, "payload" => payload, "seconds" => seconds }
    case path
    when "/apply-template"
      thinking = payload.fetch("chat_template_kwargs").fetch("enable_thinking")
      thinking = !thinking if @branch
      suffix = thinking ? (model == "qwen" ? "<|im_start|>assistant\n" : "<|im_start|>assistant\n<think>\n") :
        "<|im_start|>assistant\n<think>\n\n</think>\n\n"
      { "prompt" => "fixture#{suffix}" }
    when "/tokenize" then { "tokens" => [1] * @token_count }
    when "/v1/chat/completions"
      raise Timeout::Error, "synthetic deadline" if @simulate_timeout
      @reply
    else raise "unexpected fixture route"
    end
  end
  def max_calls! = (@generation_count = 110)
end

Dir.mktmpdir("continuity-a25-runner-fixtures-") do |parent|
  fixture = lambda do |name|
    path = File.join(parent, name); Dir.mkdir(path, 0o700)
    A25FixtureRunner.new(output: path, reply: copy.call(body))
  end
  test = fixture.call("complete")
  result = test.infer_entry(entry, item)
  check.call("native route selected once", test.calls.count { |c| c["path"] == "/v1/chat/completions" } == 1)
  check.call("final answer scored", result["status"] == "complete" && result.dig("strict_score", "correct"))
  check.call("resident request settled", !test.instance_variable_get(:@qwen_inflight))
  preview = JSON.parse(File.read(File.join(parent, "complete", "#{entry['call_id']}-preview.json")))
  expected_preview = payload.slice("messages", "chat_template_kwargs", "reasoning_format", "response_format").merge("add_generation_prompt" => true)
  check.call("preview mirrors prompt-affecting native fields only", preview["preview_payload"] == expected_preview &&
    preview["preview_rendered_prompt"] == off && preview["entry"] == entry && preview.key?("protocol_revision"))
  check.call("actual prompt parity recorded", result["preview_matches_actual_prompt"] == true)
  test = fixture.call("overflow"); test.token_count = 1537
  result = test.infer_entry(entry, item)
  check.call("essential overflow never generates", result["status"] == "skipped_prerequisite" && test.calls.none? { |c| c["path"] == "/v1/chat/completions" })
  test = fixture.call("branch"); test.branch = true
  check.call("native thinking mismatch fails before inference", raises.call { test.infer_entry(entry, item) } && test.calls.length == 1)
  failing_preview = JSON.parse(File.read(File.join(parent, "branch", "#{entry['call_id']}-preview.json")))
  check.call("failing preview retained before branch refusal", failing_preview["entry"] == entry &&
    failing_preview["preview_payload"] == expected_preview && failing_preview["preview_rendered_prompt"] == qwen_on &&
    !File.exist?(File.join(parent, "branch", "#{entry['call_id']}-request.json")))
  test = fixture.call("count"); test.max_calls!
  check.call("generation ceiling enforced", raises.call { test.infer_entry(entry, item) } && test.calls.none? { |c| c["path"] == "/v1/chat/completions" })
  test = fixture.call("timeout"); test.simulate_timeout = true
  begin
    test.infer_entry(entry, item)
    raise "timeout swallowed"
  rescue Timeout::Error
    check.call("uncertain inference is not retried", test.calls.count { |c| c["path"] == "/v1/chat/completions" } == 1 && test.instance_variable_get(:@qwen_inflight))
    receipt = JSON.parse(File.read(File.join(parent, "timeout", "#{entry['call_id']}-failure.json")))
    check.call("uncertain attempt retained", receipt["automatic_retry"] == false && receipt["generation_may_have_started"])
  end
  test = fixture.call("raw-before-validation")
  test.reply["__verbose"]["generation_settings"]["seed"] += 1
  check.call("wrong runtime sampler stops", raises.call { test.infer_entry(entry, item) })
  check.call("raw evidence precedes validation failure", File.file?(File.join(parent, "raw-before-validation", "#{entry['call_id']}-response.json")))
end

sample = { "temperatures" => { "edge" => 50, "junction" => 70, "mem" => 60 },
  "vram_total" => 16 * runner::GIB, "vram_used" => 9 * runner::GIB,
  "memory" => { "MemAvailable" => 20 * runner::GIB }, "paging_pages" => { "pswpout" => 0 } }
runner::THERMAL_ABORT.each do |sensor, limit|
  bad = copy.call(sample); bad["temperatures"][sensor] = limit
  check.call("thermal abort #{sensor}", raises.call { runner.check_resources!(bad, sample) })
end
bad = copy.call(sample); bad["memory"]["MemAvailable"] = 7 * runner::GIB
check.call("RAM guard retained", raises.call { runner.check_resources!(bad, sample) })
bad = copy.call(sample); bad["vram_used"] = 15 * runner::GIB
check.call("VRAM guard retained", raises.call { runner.check_resources!(bad, sample) })
bad = copy.call(sample); bad["paging_pages"]["pswpout"] = 65_537
check.call("swap guard retained", raises.call { runner.check_resources!(bad, sample) })
test = runner.new(series: "/not-used", seed: protocol::SEEDS.first)
check.call("unknown GPU command refused before monitor", raises.call { test.run("unknown", timeout_seconds: 3600) })
check.call("unknown native route refused before socket", raises.call { test.native_http("qwen", "/unknown", {}, seconds: 8) })
check.call("unregistered sample refused", raises.call { runner.new(series: "/not-used", seed: 1) })

# Exercise the new window wrapper with fake leases/processes, not live services.
class A25WindowFixture < ContinuityComparisonA25
  attr_accessor :failure
  attr_reader :events
  def initialize(output:)
    super(series: "/not-used", seed: Protocol::SEEDS.first)
    @output, @events = output, []
  end
  def self.allowed_window!(*args) = true
  def qwen_observe! = @events << "observe"
  def qwen_quiescent!
    @events << "settle"
    @qwen_inflight = false
  end
  def start_server(*)
    @events << "start"
    @child = :fake
  end
  def stop_server
    @events << "stop" if @child
    @child = nil
  end
  def wait_release(*) = @events << "release"
  def compare_cases
    @events << "compare"
    if @failure
      @qwen_inflight = true
      raise @failure
    end
  end
end
lease_class = SoulCore::ModelRuntimeLeaseStore
original_new = lease_class.method(:new)
fake_store = Object.new
def fake_store.with_control_lock = yield
def fake_store.leases_for_quiescent_admission_unlocked = []
lease_class.define_singleton_method(:new) { |**| fake_store }
begin
  Dir.mktmpdir("continuity-a25-lifecycle-fixtures-") do |parent|
    [nil, RuntimeError.new("synthetic failure"), Interrupt.new("synthetic cancel")].each_with_index do |error, index|
      output = File.join(parent, index.to_s); Dir.mkdir(output, 0o700)
      test = A25WindowFixture.new(output: output); test.failure = error
      begin
        result = test.run("fixed-continuity-a25", timeout_seconds: 3600)
        check.call("normal lifecycle returns success", error.nil? && result.success?)
      rescue RuntimeError, Interrupt => caught
        check.call("failure or cancellation propagates", caught.equal?(error))
        check.call("uncertain resident settled on exit", test.events.include?("settle") && !test.instance_variable_get(:@qwen_inflight))
      end
      check.call("owned child reaped before return", test.events.include?("stop") && !test.owned_child?)
      check.call("resource evidence retained on every exit", File.file?(File.join(output, "resource-samples.json")))
    end
  end
ensure
  lease_class.singleton_class.remove_method(:new)
  lease_class.define_singleton_method(:new, original_new)
end
puts "#{checks} A25 runner checks passed; no model, network, GPU, lease, or service actions"
