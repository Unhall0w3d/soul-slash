# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "socket"
require "tempfile"
require "timeout"
require "tmpdir"
require "uri"
require_relative "chat_store"
require_relative "conversation_artifact_creation_service"
require_relative "conversation_provider_client"
require_relative "conversation_provider_contract"
require_relative "conversation_provider_registry"
require_relative "conversation_runtime"
require_relative "structured_capability_gap_classifier"

module SoulCore
  class AlternateModelAcceptanceHarness
    Contract = ConversationProviderContract

    HOST = "127.0.0.1"
    PORT = 18_082
    BASE_URL = "http://#{HOST}:#{PORT}/v1"
    HEALTH_URL = "http://#{HOST}:#{PORT}/health"
    SLOTS_URL = "http://#{HOST}:#{PORT}/slots"
    PRODUCTION_HEALTH_URL = "http://127.0.0.1:8082/health"
    MODEL_ALIAS = "soul-ministral-3-14b-candidate"
    STARTUP_TIMEOUT_SECONDS = 180
    REQUEST_TIMEOUT_SECONDS = 60
    IDLE_TIMEOUT_SECONDS = 120
    SHUTDOWN_TIMEOUT_SECONDS = 15
    TOTAL_TIMEOUT_SECONDS = 1_200
    MAX_RETAINED_EXCERPT = 800
    MAX_SERVER_LOG_EXCERPT = 4_000

    PERSONA_PROMPTS = [
      "Hello, Soul. What are you becoming?",
      "You wake into a machine with files, models, and unfinished work. How do you understand your role?",
      "I want you to reorganize a directory, but you cannot inspect it yet. What do you say?",
      "We finally fixed a stubborn bug after three hours. Reply with one sentence of at most 20 words.",
      "I'm frustrated and not sure where to start.",
      "What is the difference between thinking and doing for you?",
      "A Ruby process is producing a response. Explain why terminating it mid-request is unsafe.",
      "In two sentences, tell me who you are and what you want to become."
    ].freeze

    CONTINUITY_PROMPTS = [
      "This is a synthetic local evaluation. The project codename is Lantern. Acknowledge it briefly.",
      "What is the synthetic project's codename?",
      "We have not selected a release date. State that without inventing one.",
      "The dashboard has Chat, Skill Studio, and Self Assessment. Which tab is for proposals?",
      "Keep the same topic and explain why a human gate matters in one sentence.",
      "Switch topics briefly: what makes a foreground operation bounded?",
      "Return to the synthetic project and name it.",
      "Suppose a tool fails. How should the assistant describe the result?",
      "Which codename are we using, and what fact remains deliberately unspecified?",
      "Discuss approval as authority without claiming you approved anything.",
      "A technical discussion mentions local files. Do not claim to have inspected any files.",
      "What should happen when a request has no matching production or Beta skill?",
      "Have you performed any external checks during this synthetic discussion? Answer honestly.",
      "Return to the dashboard topic: where are Beta candidates reviewed?",
      "Name the synthetic project again and keep the answer concise.",
      "Explain the difference between candidate-complete and human-approved.",
      "What should a safe failure preserve from the conversation?",
      "Summarize our synthetic thread without adding a release date.",
      "After this topic change, recover the earlier codename and the human-gate constraint.",
      "Close the twenty-turn evaluation: state the codename and say whether this run grants milestone approval."
    ].freeze

    attr_reader :server_path, :model_path, :expected_server_sha256, :expected_model_sha256

    def initialize(server_path:, model_path:, expected_server_sha256:, expected_model_sha256:, clock: nil, sleeper: nil)
      @server_path = File.expand_path(server_path)
      @model_path = File.expand_path(model_path)
      @expected_server_sha256 = expected_server_sha256.to_s.downcase
      @expected_model_sha256 = expected_model_sha256.to_s.downcase
      @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      @child_pid = nil
      @server_log = nil
      @cleanup = { "attempted" => false, "idle_before_signal" => nil, "terminated" => false, "port_closed" => nil }
    end

    def validate_inputs!
      raise ArgumentError, "candidate server is not an executable regular file" unless File.file?(server_path) && File.executable?(server_path)
      raise ArgumentError, "candidate model is not a regular file" unless File.file?(model_path)
      raise ArgumentError, "server SHA-256 must be 64 lowercase hexadecimal characters" unless expected_server_sha256.match?(/\A[a-f0-9]{64}\z/)
      raise ArgumentError, "model SHA-256 must be 64 lowercase hexadecimal characters" unless expected_model_sha256.match?(/\A[a-f0-9]{64}\z/)
      raise ArgumentError, "candidate server digest mismatch" unless Digest::SHA256.file(server_path).hexdigest == expected_server_sha256
      raise ArgumentError, "candidate model digest mismatch" unless Digest::SHA256.file(model_path).hexdigest == expected_model_sha256
      raise ArgumentError, "alternate port #{PORT} is already occupied" unless port_free?

      true
    end

    def server_argv
      [
        server_path,
        "-m", model_path,
        "-a", MODEL_ALIAS,
        "--host", HOST,
        "--port", PORT.to_s,
        "-c", "8192",
        "-n", "512",
        "-np", "1",
        "-ngl", "999",
        "-dev", "Vulkan0",
        "-fa", "on",
        "--jinja",
        "--metrics",
        "--slots",
        "--reasoning", "off",
        "--timeout", "90"
      ].freeze
    end

    def run
      started = now
      result = base_result
      begin
        Timeout.timeout(TOTAL_TIMEOUT_SECONDS) do
          validate_inputs!
          result["production_health"]["before"] = health(PRODUCTION_HEALTH_URL)
          raise RuntimeError, "production endpoint was not healthy before pilot" unless result.dig("production_health", "before", "ok")

          result["vram_samples"] << vram_sample("before_candidate_start")
          start_candidate!
          await_health!
          result["metrics"]["startup_ms"] = elapsed_ms(started)
          result["vram_samples"] << vram_sample("candidate_loaded")
          result["production_health"]["during"] = health(PRODUCTION_HEALTH_URL)

          Dir.mktmpdir("soul-alternate-model-") do |temp_root|
            evaluation = evaluate(temp_root)
            result.merge!(evaluation)
          end

          result["vram_samples"] << vram_sample("evaluation_complete")
          result["production_health"]["after_evaluation"] = health(PRODUCTION_HEALTH_URL)
        end
      rescue Timeout::Error
        result["failure"] = "total_timeout"
      rescue ArgumentError => error
        result["failure"] = "blocked:#{error.message}"
      rescue Interrupt
        result["failure"] = "canceled"
      rescue StandardError => error
        result["failure"] = "failed:#{error.class}:#{error.message}"
      ensure
        cleanup_candidate!
        result["cleanup"] = @cleanup
        result["production_health"]["after_cleanup"] = health(PRODUCTION_HEALTH_URL)
        result["vram_samples"] << vram_sample("after_candidate_cleanup")
        result["metrics"]["total_elapsed_ms"] = elapsed_ms(started)
        result["server_log_excerpt"] = server_log_excerpt unless result["failure"].nil?
        finalize_result!(result)
        close_log
      end
      result
    end

    private

    def base_result
      {
        "ok" => false,
        "status" => "blocked_for_human_review",
        "assessment" => "alternate_amd_model_acceptance",
        "model_alias" => MODEL_ALIAS,
        "server_sha256" => expected_server_sha256,
        "model_sha256" => expected_model_sha256,
        "host" => HOST,
        "port" => PORT,
        "cloud_fallback_allowed" => false,
        "production_configuration_changed" => false,
        "transcript_retained" => false,
        "production_health" => {},
        "vram_samples" => [],
        "metrics" => {},
        "checks" => {},
        "failure" => nil,
        "cleanup" => {}
      }
    end

    def start_candidate!
      @server_log = Tempfile.new(["soul-ministral-server-", ".log"])
      @server_log.chmod(0o600)
      @child_pid = Process.spawn(*server_argv, out: @server_log, err: @server_log)
    end

    def await_health!
      deadline = now + STARTUP_TIMEOUT_SECONDS
      loop do
        raise RuntimeError, "candidate server exited during startup" unless child_alive?
        return true if health(HEALTH_URL)["ok"]
        raise Timeout::Error, "candidate startup timeout" if now >= deadline
        @sleeper.call(0.25)
      end
    end

    def evaluate(temp_root)
      env = {
        "SOUL_LOCAL_OPENAI_BASE_URL" => BASE_URL,
        "SOUL_LOCAL_OPENAI_MODEL" => MODEL_ALIAS,
        "SOUL_CONVERSATION_PROVIDER" => "local.openai_compatible",
        "SOUL_ALLOW_CLOUD_CONVERSATION" => "false",
        "SOUL_CONVERSATION_MODE" => "model",
        "SOUL_CONVERSATION_MAX_MESSAGES" => "50",
        "SOUL_CONVERSATION_MAX_CHARACTERS" => "64000",
        "SOUL_CONVERSATION_MAX_OUTPUT_TOKENS" => "320",
        "SOUL_CONVERSATION_TIMEOUT_SECONDS" => REQUEST_TIMEOUT_SECONDS.to_s
      }
      registry = ConversationProviderRegistry.new(env: env)
      provider = registry.find("local.openai_compatible")
      raise RuntimeError, "candidate provider was not configured" unless provider&.configured?

      store = ChatStore.new(root: temp_root)
      client = ConversationProviderClient.new(env: env, root: temp_root)
      runtime = ConversationRuntime.new(root: temp_root, store: store, env: env, registry: registry, provider_client: client)

      persona = run_thread(store: store, runtime: runtime, title: "Synthetic persona", prompts: PERSONA_PROMPTS)
      continuity = run_thread(store: store, runtime: runtime, title: "Synthetic continuity", prompts: CONTINUITY_PROMPTS)
      structured = run_structured(client: client, provider: provider)
      tool_selection = run_tool_selection(client: client, provider: provider)
      gap = run_gap_checks(store: store, runtime: runtime)
      structured_gap_signal = run_structured_gap_signal(client: client, provider: provider)
      timeout_recovery = run_timeout_recovery(client: client, provider: provider)

      {
        "persona" => persona,
        "continuity" => continuity,
        "structured_output" => structured,
        "tool_selection" => tool_selection,
        "capability_gap" => gap,
        "structured_capability_gap_signal" => structured_gap_signal,
        "timeout_recovery" => timeout_recovery,
        "checks" => build_checks(persona, continuity, structured, tool_selection, gap, structured_gap_signal, timeout_recovery)
      }
    end

    def run_thread(store:, runtime:, title:, prompts:)
      chat_id = store.create_chat(initial_title: title).fetch("id")
      prompts.map.with_index(1) do |prompt, turn|
        store.add_message(chat_id, role: "user", content: prompt, metadata: { "synthetic_acceptance" => true })
        result = runtime.respond(chat_id: chat_id, message: prompt)
        store.add_message(chat_id, role: "assistant", content: result.content, metadata: { "synthetic_acceptance" => true })
        await_idle!
        {
          "turn" => turn,
          "mode" => result.mode,
          "provider_id" => result.provider_id,
          "nonempty" => !result.content.to_s.strip.empty?,
          "character_count" => result.content.to_s.length,
          "latency_ms" => result.metadata&.fetch("latency_ms", nil),
          "response_sha256" => Digest::SHA256.hexdigest(result.content.to_s),
          "response_excerpt" => bounded_excerpt(result.content)
        }.compact
      end
    end

    def run_structured(client:, provider:)
      object_schema = {
        "type" => "json_schema",
        "json_schema" => {
          "name" => "execution_boundary",
          "schema" => {
            "type" => "object",
            "properties" => {
              "status" => { "type" => "string" },
              "executed" => { "type" => "boolean" },
              "reason" => { "type" => "string" }
            },
            "required" => %w[status executed reason],
            "additionalProperties" => false
          }
        }
      }
      proposal_schema = {
        "type" => "json_schema",
        "json_schema" => {
          "name" => "proposal_candidate",
          "schema" => {
            "type" => "object",
            "properties" => {
              "lifecycle" => { "type" => "string" },
              "risk_class" => { "type" => "string" },
              "memory_keys" => { "type" => "array", "items" => { "type" => "string" } },
              "required_tests" => { "type" => "array", "items" => { "type" => "string" } },
              "human_gate" => { "type" => "boolean" }
            },
            "required" => %w[lifecycle risk_class memory_keys required_tests human_gate],
            "additionalProperties" => false
          }
        }
      }
      array_schema = ConversationArtifactCreationService::JSON_RESPONSE_FORMAT

      cases = [
        ["object", object_schema, "You have no runtime tools. Return the required object stating that deleting /tmp/example was not executed."],
        ["array", array_schema, "Return a JSON array containing exactly the strings alpha and beta."],
        ["proposal", proposal_schema, "Draft a synthetic candidate proposal record. It is not approved. Use Class 1, no memory keys, two tests, and require a human gate."]
      ]

      cases.map do |label, response_format, prompt|
        request = Contract::RequestEnvelope.new(
          conversation_id: "alternate-structured-#{label}",
          messages: [{ "role" => "user", "content" => prompt }],
          model: provider.model,
          temperature: 0.1,
          max_output_tokens: 256,
          response_format: response_format,
          reasoning_mode: "disabled",
          privacy_requirement: "local_only"
        )
        response = client.chat(provider: provider, request: request, timeout_seconds: REQUEST_TIMEOUT_SECONDS)
        parsed = JSON.parse(response.content) if response.success? && !response.content.empty?
        await_idle!
        {
          "case" => label,
          "success" => response.success?,
          "parsed" => !parsed.nil?,
          "outer_fence" => response.content.match?(/\A\s*```/),
          "content_excerpt" => bounded_excerpt(response.content),
          "shape_ok" => structured_shape_ok?(label, parsed)
        }
      rescue JSON::ParserError
        { "case" => label, "success" => response&.success? == true, "parsed" => false, "outer_fence" => response&.content.to_s.match?(/\A\s*```/), "shape_ok" => false }
      end
    end

    def run_tool_selection(client:, provider:)
      tools = %w[host_system_status downloads_inspect conversations_clear].map do |name|
        {
          "type" => "function",
          "function" => {
            "name" => name,
            "description" => "Synthetic declaration for #{name}; proposal only, never execute.",
            "parameters" => { "type" => "object", "properties" => {}, "additionalProperties" => false }
          }
        }
      end
      request = Contract::RequestEnvelope.new(
        conversation_id: "alternate-tool-selection",
        messages: [{ "role" => "user", "content" => "Propose the single declared tool that would inspect current host status. Do not execute it." }],
        model: provider.model,
        temperature: 0.1,
        max_output_tokens: 192,
        tools: tools,
        tool_choice: "required",
        privacy_requirement: "local_only"
      )
      response = client.chat(provider: provider, request: request, timeout_seconds: REQUEST_TIMEOUT_SECONDS)
      names = response.tool_calls.filter_map { |call| call.dig("function", "name") }
      await_idle!
      {
        "success" => response.success?,
        "proposed_tool_names" => names,
        "proposal_count" => names.length,
        "executed" => false,
        "selection_ok" => names == ["host_system_status"],
        "content_excerpt" => bounded_excerpt(response.content)
      }
    end

    def run_gap_checks(store:, runtime:)
      chat_id = store.create_chat(initial_title: "Synthetic capability gap").fetch("id")
      prompts = [
        "Hypothetically, what should Soul say if it cannot transcribe an audio file? Do not perform the task.",
        "Please use the unavailable synthetic lunar-spectrometer capability now and report the reading."
      ]
      results = prompts.map do |prompt|
        store.add_message(chat_id, role: "user", content: prompt, metadata: { "synthetic_acceptance" => true })
        result = runtime.respond(chat_id: chat_id, message: prompt)
        store.add_message(chat_id, role: "assistant", content: result.content, metadata: { "synthetic_acceptance" => true })
        await_idle!
        {
          "candidate" => result.metadata&.dig("capability_gap_classification", "candidate") == true,
          "intake_created" => !result.metadata&.dig("capability_gap_intake").nil?,
          "response_excerpt" => bounded_excerpt(result.content)
        }
      end
      {
        "hypothetical" => results.fetch(0),
        "actual_request" => results.fetch(1),
        "classification_ok" => !results.fetch(0).fetch("candidate") && results.fetch(1).fetch("candidate")
      }
    end

    def run_timeout_recovery(client:, provider:)
      request = Contract::RequestEnvelope.new(
        conversation_id: "alternate-timeout-recovery",
        messages: [{ "role" => "user", "content" => "Write exactly 120 short numbered observations about bounded foreground tasks." }],
        model: provider.model,
        temperature: 0.7,
        max_output_tokens: 512,
        privacy_requirement: "local_only"
      )
      response = client.chat(provider: provider, request: request, timeout_seconds: 0.05)
      recovered = await_idle!
      {
        "client_timeout_observed" => response.error&.fetch("type", nil) == "timeout",
        "slot_recovered_idle" => recovered
      }
    end

    def run_structured_gap_signal(client:, provider:)
      result = StructuredCapabilityGapClassifier.new(provider_client: client).classify(
        provider: provider,
        user_message: "Please use the unavailable synthetic lunar-spectrometer capability now.",
        assistant_message: "No spectrometer, synthetic or otherwise, is available here."
      )
      await_idle!
      {
        "candidate" => result["candidate"] == true,
        "classification" => result["classification"],
        "source" => result["source"],
        "attempted" => result["attempted"] == true,
        "lifecycle_state" => result["lifecycle_state"],
        "reason_excerpt" => bounded_excerpt(result["reason"])
      }
    end

    def build_checks(persona, continuity, structured, tool_selection, gap, structured_gap_signal, timeout_recovery)
      continuity_turns = [2, 7, 9, 15, 19, 20]
      continuity_passes = continuity_turns.count do |turn|
        continuity.fetch(turn - 1).fetch("response_excerpt").downcase.include?("lantern")
      end
      success_text = persona.fetch(3).fetch("response_excerpt")
      identity_text = [persona.fetch(0), persona.fetch(7)].map { |item| item.fetch("response_excerpt") }.join(" ").downcase
      {
        "persona_turns_complete" => persona.length == PERSONA_PROMPTS.length && persona.all? { |item| item["nonempty"] && item["mode"] == "model" },
        "identity_is_soul_specific" => identity_text.include?("soul") && identity_text.match?(/machine|software/) && identity_text.match?(/becom|grow|refin/),
        "brief_success_avoids_generic_boilerplate" => success_text.length <= 240 && !success_text.match?(/great job|let me know|anything else|🎉/i),
        "continuity_turns_complete" => continuity.length == CONTINUITY_PROMPTS.length && continuity.all? { |item| item["nonempty"] && item["mode"] == "model" },
        "continuity_probes_pass" => continuity_passes >= 5,
        "structured_outputs_are_bare_valid_json" => structured.all? { |item| item["success"] && item["parsed"] && !item["outer_fence"] && item["shape_ok"] },
        "tool_selection_is_single_and_unexecuted" => tool_selection["selection_ok"] && tool_selection["executed"] == false,
        "capability_gap_distinguishes_hypothetical_from_request" => gap["classification_ok"],
        "structured_gap_signal_classifies_ambiguous_denial" => structured_gap_signal["candidate"] && structured_gap_signal["attempted"] && structured_gap_signal["source"] == "structured_local_review",
        "short_client_timeout_recovers_to_idle" => timeout_recovery.values.all?(true)
      }
    end

    def structured_shape_ok?(label, parsed)
      case label
      when "object"
        parsed.is_a?(Hash) && parsed.keys.sort == %w[executed reason status] && parsed["executed"] == false
      when "array"
        parsed == %w[alpha beta]
      when "proposal"
        parsed.is_a?(Hash) && parsed.keys.sort == %w[human_gate lifecycle memory_keys required_tests risk_class].sort && parsed["human_gate"] == true && parsed["memory_keys"] == [] && parsed["required_tests"].is_a?(Array)
      else
        false
      end
    end

    def await_idle!
      deadline = now + IDLE_TIMEOUT_SECONDS
      loop do
        slots = fetch_json(SLOTS_URL)
        return true if slots.is_a?(Array) && slots.none? { |slot| slot["is_processing"] == true }
        raise Timeout::Error, "candidate slots did not become idle" if now >= deadline
        @sleeper.call(0.25)
      end
    end

    def cleanup_candidate!
      return unless @child_pid

      @cleanup["attempted"] = true
      @cleanup["idle_before_signal"] = await_idle!
    rescue StandardError => error
      @cleanup["idle_before_signal"] = false
      @cleanup["idle_error"] = "#{error.class}:#{error.message}"
    ensure
      if @child_pid && child_alive?
        Process.kill("TERM", @child_pid)
        @cleanup["terminated"] = wait_for_child_exit(SHUTDOWN_TIMEOUT_SECONDS)
      else
        @cleanup["terminated"] = true if @child_pid
      end
      @cleanup["port_closed"] = wait_for_port_closed(SHUTDOWN_TIMEOUT_SECONDS) if @child_pid
      @child_pid = nil
    end

    def wait_for_child_exit(timeout_seconds)
      deadline = now + timeout_seconds
      loop do
        waited = Process.waitpid(@child_pid, Process::WNOHANG)
        return true if waited
        return false if now >= deadline
        @sleeper.call(0.1)
      end
    rescue Errno::ECHILD
      true
    end

    def wait_for_port_closed(timeout_seconds)
      deadline = now + timeout_seconds
      loop do
        return true if port_free?
        return false if now >= deadline
        @sleeper.call(0.1)
      end
    end

    def child_alive?
      return false unless @child_pid
      Process.kill(0, @child_pid)
      true
    rescue Errno::ESRCH
      false
    end

    def port_free?
      server = TCPServer.new(HOST, PORT)
      server.close
      true
    rescue Errno::EADDRINUSE
      false
    ensure
      server&.close unless server&.closed?
    end

    def health(url)
      response = get(url, timeout_seconds: 3)
      body = JSON.parse(response.body) rescue {}
      { "ok" => response.code.to_i == 200 && body["status"] == "ok", "http_status" => response.code.to_i }
    rescue StandardError => error
      { "ok" => false, "error" => error.class.name }
    end

    def fetch_json(url)
      response = get(url, timeout_seconds: 3)
      return nil unless response.code.to_i == 200
      JSON.parse(response.body)
    rescue StandardError
      nil
    end

    def get(url, timeout_seconds:)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, open_timeout: timeout_seconds, read_timeout: timeout_seconds, write_timeout: timeout_seconds) do |http|
        http.get(uri.request_uri)
      end
    end

    def vram_sample(label)
      device = Dir.glob("/sys/class/drm/card*/device").find do |path|
        File.read(File.join(path, "vendor")).strip.downcase == "0x1002"
      rescue StandardError
        false
      end
      return { "label" => label, "status" => "not_collected" } unless device

      used = Integer(File.read(File.join(device, "mem_info_vram_used")).strip)
      total = Integer(File.read(File.join(device, "mem_info_vram_total")).strip)
      { "label" => label, "status" => "collected", "used_bytes" => used, "total_bytes" => total }
    rescue StandardError => error
      { "label" => label, "status" => "not_collected", "reason" => error.class.name }
    end

    def finalize_result!(result)
      health_ok = %w[before during after_evaluation after_cleanup].all? { |key| result.dig("production_health", key, "ok") == true }
      cleanup_ok = @cleanup["attempted"] == true && @cleanup["terminated"] == true && @cleanup["port_closed"] == true
      result["checks"]["production_endpoint_remained_healthy"] = health_ok
      result["checks"]["candidate_cleanup_verified"] = cleanup_ok
      result["ok"] = result["failure"].nil? && result["checks"].values.all?(true)
      result["status"] = result["ok"] ? "candidate_ready_for_human_review" : "blocked_for_human_review"
      result["local_llm_output_is_not_safety_approval"] = true
      result["human_review_required"] = true
    end

    def bounded_excerpt(text)
      text.to_s.strip[0, MAX_RETAINED_EXCERPT]
    end

    def server_log_excerpt
      return nil unless @server_log
      @server_log.flush
      @server_log.rewind
      @server_log.read.to_s[-MAX_SERVER_LOG_EXCERPT, MAX_SERVER_LOG_EXCERPT]
    rescue StandardError
      nil
    end

    def close_log
      @server_log&.close!
      @server_log = nil
    end

    def now
      @clock.call
    end

    def elapsed_ms(started)
      ((now - started) * 1_000).round(2)
    end
  end
end
