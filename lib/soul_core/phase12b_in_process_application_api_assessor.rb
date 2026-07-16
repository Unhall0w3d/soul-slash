# frozen_string_literal: true

require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require_relative "application_facade"
require_relative "application_request_receipt_store"
require_relative "chat_command"

module SoulCore
  class Phase12bInProcessApplicationApiAssessor
    Result = Struct.new(:content, :mode, :provider_id, :fallback_reason, :metadata, keyword_init: true) do
      def to_h
        {
          "content" => content,
          "mode" => mode,
          "provider_id" => provider_id,
          "fallback_reason" => fallback_reason,
          "metadata" => metadata || {}
        }.compact
      end
    end

    class FakeRuntime
      attr_reader :calls

      def initialize
        @calls = []
      end

      def respond(chat_id:, message:)
        @calls << { "chat_id" => chat_id, "message" => message }
        Result.new(
          content: "Application reply to: #{message}",
          mode: "model",
          provider_id: "local.phase12b",
          metadata: { "bounded" => true }
        )
      end
    end

    class FakeStatusCollector
      attr_reader :calls

      def initialize(fail: false)
        @calls = 0
        @fail = fail
      end

      def collect
        @calls += 1
        raise IOError, "/home/private/status failed" if @fail

        {
          "ok" => true,
          "assessment" => "host_system_status",
          "scope" => "bounded fixture",
          "collected_at" => "2026-07-14T20:00:00-04:00",
          "collected" => { "host" => { "hostname" => "fixture-host" } },
          "claims" => ["fixture claim"],
          "not_collected" => ["everything else"]
        }
      end
    end

    class FakeSkillRegistry
      def list
        {
          "system.status" => {
            "description" => "Read-only status",
            "risk" => "read_only",
            "requires_approval" => false,
            "writes_files" => false,
            "path" => "Soul/skills/system/status.rb"
          }
        }
      end
    end

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      checks = {}
      details = {}

      Dir.mktmpdir("soul-phase12b-") do |temp_root|
        store = ChatStore.new(root: temp_root)
        runtime = FakeRuntime.new
        status = FakeStatusCollector.new
        approval_store = ApprovalTokenStore.new(root: temp_root)
        activity_store = ChatExecutionHistory.new(root: temp_root)
        facade = ApplicationFacade.new(
          root: temp_root,
          process_env: {
            "SOUL_LOCAL_OPENAI_MODEL" => "fixture-model",
            "SOUL_CLOUD_OPENAI_API_KEY" => "phase12b-secret-sentinel"
          },
          chat_store: store,
          conversation_runtime: runtime,
          status_collector: status,
          approval_store: approval_store,
          activity_store: activity_store,
          skill_registry: FakeSkillRegistry.new
        )

        bootstrap = call(facade, "request:bootstrap", "application.bootstrap")
        checks["bootstrap_is_bounded_read_only_and_does_not_collect_status"] =
          terminal_envelope?(bootstrap, "complete") &&
          bootstrap.dig("data", "system_status", "collected") == false &&
          bootstrap.dig("data", "product_tabs").first(3) == ["Chat", "Skill Studio", "Self Assessment"] &&
          status.calls.zero? && runtime.calls.empty? &&
          !JSON.generate(bootstrap).include?("phase12b-secret-sentinel")

        invalid_operation = call(facade, "request:unknown", "unknown.operation")
        invalid_parameter = call(facade, "request:params", "chats.list", { "surprise" => true })
        invalid_id = call(facade, "request:badid", "chats.get", { "chat_id" => "../../etc" })
        invalid_type = call(facade, "request:type", "chats.send", { "chat_id" => "chat_valid", "message" => ["not", "text"] })
        checks["unknown_operations_parameters_identities_and_types_fail_closed"] =
          [invalid_operation, invalid_parameter, invalid_id, invalid_type].all? { |response| terminal_envelope?(response, "failed") } &&
          runtime.calls.empty?

        oversized = call(facade, "request:oversized", "chats.send", { "chat_id" => "chat_valid", "message" => "x" * (ApplicationContract::MAX_STRING_BYTES + 1) })
        deep = { "schema_version" => ApplicationContract::SCHEMA_VERSION, "request_id" => "request:deep", "operation" => "activities.recent", "parameters" => { "filters" => nested_hash(10) }, "context" => {} }
        deep_result = facade.call(deep)
        invalid_utf8 = "bad".dup.force_encoding(Encoding::UTF_8)
        invalid_utf8 << "\xFF".b
        utf8_result = call(facade, "request:utf8", "chats.send", { "chat_id" => "chat_valid", "message" => invalid_utf8 })
        checks["request_size_depth_and_encoding_are_bounded"] =
          [oversized, deep_result, utf8_result].all? { |response| terminal_envelope?(response, "failed") }

        empty = call(facade, "request:empty", "chats.list", { "limit" => 50 })
        checks["empty_lists_complete_without_provider_calls"] =
          terminal_envelope?(empty, "complete") && empty.dig("data", "count").zero? && runtime.calls.empty?

        created = call(facade, "request:create", "chats.create", { "title" => "Phase 12B" })
        chat_id = created.dig("data", "record", "id")
        checks["chat_creation_uses_canonical_store_identity"] =
          terminal_envelope?(created, "complete") && chat_id.match?(ApplicationContract::CHAT_ID) &&
          store.messages(chat_id).empty? && created.dig("meta", "mutation") == "chat_created" &&
          terminal_envelope?(call(facade, "request:getchat", "chats.get", { "chat_id" => chat_id }), "complete") &&
          terminal_envelope?(call(facade, "request:messages", "chats.messages", { "chat_id" => chat_id, "limit" => 20 }), "complete")

        sent = call(facade, "request:send001", "chats.send", { "chat_id" => chat_id, "message" => "Hello facade" })
        checks["chat_send_appends_exactly_one_exchange_through_existing_runtime"] =
          terminal_envelope?(sent, "complete") && runtime.calls.length == 1 &&
          store.messages(chat_id).map { |record| record["role"] } == %w[user assistant] &&
          sent.dig("data", "assistant_message", "content").include?("Hello facade")

        replay = call(facade, "request:send001", "chats.send", { "chat_id" => chat_id, "message" => "Hello facade" })
        checks["same_chat_request_and_message_replay_idempotently"] =
          terminal_envelope?(replay, "complete") && replay.dig("meta", "idempotent_replay") == true &&
          runtime.calls.length == 1 && store.messages(chat_id).length == 2

        conflict = call(facade, "request:send001", "chats.send", { "chat_id" => chat_id, "message" => "Changed content" })
        checks["request_id_scope_conflict_blocks_without_mutation"] =
          terminal_envelope?(conflict, "blocked_for_human_review") &&
          runtime.calls.length == 1 && store.messages(chat_id).length == 2

        receipts = File.read(File.join(temp_root, ApplicationRequestReceiptStore::DEFAULT_PATH))
        checks["idempotency_receipts_are_private_bounded_and_content_free"] =
          ["Hello facade", "Changed content"].none? { |content| receipts.include?(content) } &&
          (File.stat(File.join(temp_root, ApplicationRequestReceiptStore::DEFAULT_PATH)).mode & 0o777) == 0o600 &&
          receipts.lines.length <= ApplicationRequestReceiptStore::MAX_EVENTS

        awaiting = call(facade, "request:await", "chats.send", { "message" => "missing chat" })
        canceled = call(facade, "request:cancel", "application.cancel")
        checks["awaiting_input_and_cancellation_are_terminal_without_mutation"] =
          terminal_envelope?(awaiting, "awaiting_input") && terminal_envelope?(canceled, "canceled") &&
          runtime.calls.length == 1

        54.times { |index| store.create_chat(initial_title: "Bulk #{index}") }
        bounded_chats = call(facade, "request:chatcap", "chats.list", { "limit" => 500 })
        checks["chat_and_message_outputs_are_capped"] =
          bounded_chats.dig("data", "count") == ApplicationFacade::CHAT_LIMIT &&
          bounded_chats.dig("meta", "limits", "messages") == ApplicationFacade::MESSAGE_LIMIT

        workspace = call(facade, "request:workspace", "workspace.list", { "limit" => 500 })
        inbox = call(facade, "request:inbox", "inbox.list", { "chat_id" => chat_id, "limit" => 500 })
        checks["workspace_and_inbox_delegate_to_phase11d_contract"] =
          terminal_envelope?(workspace, "complete") && terminal_envelope?(inbox, "complete") &&
          workspace.dig("data", "limit") == ConversationWorkspaceService::MAX_RECORDS &&
          workspace.dig("data", "metadata_only") == true

        refreshed = call(facade, "request:status", "system_status.refresh")
        checks["system_status_is_manual_and_invoked_once"] =
          terminal_envelope?(refreshed, "complete") && status.calls == 1 &&
          refreshed.dig("data", "collected", "host", "hostname") == "fixture-host"

        configuration = call(facade, "request:config", "configuration.show")
        checks["configuration_projection_is_redacted_and_read_only"] =
          terminal_envelope?(configuration, "complete") &&
          configuration.dig("data", "mutation") == "none" &&
          !JSON.generate(configuration).include?("phase12b-secret-sentinel")

        approval = approval_store.issue(
          skill_id: "downloads.move_to_trash",
          scope: { "private_path" => "/home/private/file", "count" => 1 },
          ttl_seconds: 900
        )
        approvals = call(facade, "request:approvals", "approvals.pending", { "limit" => 100 })
        checks["approval_projection_is_bounded_and_non_authorizing"] =
          terminal_envelope?(approvals, "complete") && approvals.dig("data", "count") == 1 &&
          [approval.fetch("token_id"), "/home/private/file"].none? { |content| JSON.generate(approvals).include?(content) } &&
          approvals.dig("data", "records", 0, "authorization_value_exposed") == false

        activity_result = Struct.new(:skill_id, :status, :ok, :executed, :risk, :confirmation_required, :exit_status, :blocked_by).new(
          "system.status", "executed", true, true, "read_only", false, 0, []
        )
        activity_store.record(activity_result, message: "private activity message", source: "chat")
        activities = call(facade, "request:activity", "activities.recent", { "limit" => 100 })
        skills = call(facade, "request:skills", "skills.list", { "limit" => 100 })
        checks["skills_and_activities_are_bounded_read_only_projections"] =
          terminal_envelope?(activities, "complete") && terminal_envelope?(skills, "complete") &&
          !JSON.generate(activities).include?("private activity message") &&
          skills.dig("data", "records", 0, "skill_id") == "system.status"

        failing_facade = ApplicationFacade.new(root: temp_root, process_env: {}, status_collector: FakeStatusCollector.new(fail: true))
        dependency_failure = call(failing_facade, "request:failure", "system_status.refresh")
        checks["dependency_exceptions_are_bounded_without_paths_or_backtraces"] =
          terminal_envelope?(dependency_failure, "failed") &&
          ["/home/private", "backtrace"].none? { |content| JSON.generate(dependency_failure).include?(content) }

        cli_store = ChatStore.new(root: File.join(temp_root, "cli-project"))
        cli_chat_service = ApplicationChatService.new(root: File.join(temp_root, "cli-project"), store: cli_store, runtime: runtime)
        cli_output = StringIO.new
        cli = ChatCommand.new(
          argv: ["CLI shared path"],
          root: File.join(temp_root, "cli-project"),
          output: cli_output,
          runtime: runtime,
          chat_service: cli_chat_service
        )
        cli_status = cli.run
        checks["cli_chat_uses_shared_application_exchange_service"] =
          cli_status.zero? && cli_output.string.include?("Application reply") &&
          File.read(File.join(@root, "lib/soul_core/chat_command.rb")).include?("@chat_service.send")

        lifecycle_set = [bootstrap, invalid_operation, awaiting, canceled, conflict].map { |response| response["lifecycle_state"] }.uniq
        checks["all_required_lifecycle_states_are_represented"] =
          %w[complete failed awaiting_input canceled blocked_for_human_review].all? { |state| lifecycle_set.include?(state) }

        source = application_source
        forbidden = %w[TCPServer HTTPServer WEBrick Rack::Handler Sinatra Thread.new systemctl inotify cron polling]
        checks["no_transport_listener_or_background_primitive_is_added"] = forbidden.none? { |needle| source.include?(needle) }

        details["operation_count"] = ApplicationContract::OPERATIONS.length
        details["runtime_call_count"] = runtime.calls.length
        details["receipt_event_count"] = receipts.lines.length
      end

      blockers = checks.filter_map { |name, passed| name unless passed }
      {
        "ok" => blockers.empty?,
        "assessment" => "phase12b_in_process_application_api",
        "milestone" => "conversational_soul",
        "phase" => "12B",
        "status" => blockers.empty? ? "candidate_ready" : "blocked",
        "blockers" => blockers,
        "verification" => checks,
        "details" => details,
        "memory_keys" => [],
        "lifecycle_states" => %w[complete failed awaiting_input canceled blocked_for_human_review],
        "risk_class" => "Class 2: Local state write, non-destructive",
        "human_review_required" => true
      }
    end

    def render(report)
      lines = ["Soul Phase 12B In-Process Application API Assessment", "Status: #{report['status']}", "", "Verification"]
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |item| lines << "- #{item}" }
      lines.join("\n")
    end

    private

    def call(facade, request_id, operation, parameters = {}, context = { "interface" => "internal" })
      facade.call(
        {
          "schema_version" => ApplicationContract::SCHEMA_VERSION,
          "request_id" => request_id,
          "operation" => operation,
          "parameters" => parameters,
          "context" => context
        }
      )
    end

    def terminal_envelope?(response, lifecycle)
      response["schema_version"] == ApplicationContract::SCHEMA_VERSION &&
        response["lifecycle_state"] == lifecycle && response.key?("data") &&
        response.key?("errors") && response.key?("meta")
    end

    def nested_hash(depth)
      value = "leaf"
      depth.times { |index| value = { "level_#{index}" => value } }
      value
    end

    def application_source
      %w[
        lib/soul_core/application_contract.rb
        lib/soul_core/application_request_receipt_store.rb
        lib/soul_core/application_chat_service.rb
        lib/soul_core/application_facade.rb
      ].map { |path| File.read(File.join(@root, path)) }.join("\n")
    end
  end
end
