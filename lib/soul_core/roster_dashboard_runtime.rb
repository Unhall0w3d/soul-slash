# frozen_string_literal: true
require "net/http"
require "timeout"
require_relative "roster_conversation_gateway"
require_relative "chat_cancellation"
require_relative "telemetry_diagnostic"
require_relative "roster_admission_busy"
require_relative "roster_tool_proposal_policy"
require_relative "application_request_receipt_store"

module SoulCore
  # Fixed loopback client; credentials never reach browser code. One generation
  # POST only, with independent authenticated cancellation/status connections.
  class RosterDashboardRuntime
    MEMBERS = (RosterChatAdapter::MODELS + RosterChatAdapter::ISOLATED_MODELS + ["gemma-4-e4b-cpu"]).freeze
    KEY = "/home/bhones/.config/soul/continuity-a24.key"
    Result = Struct.new(:content, :mode, :provider_id, :fallback_reason, :metadata, keyword_init: true)

    def initialize(store:, transport: nil, key_reader: nil, maintenance_workflow: nil, receipt_store: nil)
      @store = store
      @receipt_store = receipt_store || (store && ApplicationRequestReceiptStore.new(root: store.project_root))
      @transport = transport || method(:post)
      @key_reader = key_reader || method(:read_key)
      @maintenance_workflow = maintenance_workflow
    end

    def supports_chat_cancellation? = true

    def respond(chat_id:, message:, cancel:, progress: nil, **)
      member = @store.chat(chat_id)&.dig("metadata", "roster_member")
      raise ArgumentError, "explicit roster member required" unless self.class::MEMBERS.include?(member)
      if member == "gemma-4-e4b-cpu" && instance_of?(RosterDashboardRuntime)
        return CpuMemberDashboardRuntime.new(store: @store, key_reader: @key_reader, receipt_store: @receipt_store).respond(chat_id: chat_id, message: message, cancel: cancel, progress: progress)
      end
      raise ChatCancellation::Confirmed if cancel.call
      if @maintenance_workflow&.candidate_message?(chat_id: chat_id, message: message)
        workflow = @maintenance_workflow.plan(chat_id: chat_id, message: message, progress: progress)
        if workflow
          return Result.new(content: workflow.fetch("content"), mode: workflow.fetch("mode"),
            provider_id: "deterministic.maintenance", metadata: workflow.fetch("metadata").merge(
              "deterministic_workflow" => "maintenance", "selected_member" => member))
        end
      end
      rows = @store.messages(chat_id, scan_limit: 63)
      raise ArgumentError, "accepted user message missing" unless rows.last&.values_at("role", "content") == ["user", message]
      # These exchanges belong to the harness, not the model journal. Remove
      # only complete, request-linked pairs; never relabel them as model output.
      rows = without_unadmitted_busy_messages(rows, chat_id)
      rows = without_maintenance_exchanges(rows)
      unless rows.all? { |r| r["role"] != "assistant" || r.dig("metadata", "runtime", "model") == member }
        raise RuntimeError, "foreign member history refused"
      end
      messages = rows.map { |r| r.slice("role", "content") }
      adapter = member_adapter(member)
      identity = {"conversation_id" => "dashboard_#{chat_id}",
        "request_id" => RosterConversationGateway.digest({"conversation" => "dashboard_#{chat_id}", "adapter" => adapter.binding, "messages" => messages})}
      raise ChatCancellation::Confirmed if cancel.call
      token = @key_reader.call
      mutex, changed, done = Mutex.new, ConditionVariable.new, false
      watcher = Thread.new do
        loop do
          break if mutex.synchronize { changed.wait(mutex, 0.1) unless done; done }
          next unless cancel.call
          # Unknown may be the brief interval before backend admission. Repeat
          # only the idempotent Stop signal, never a generation request.
          begin
            Timeout.timeout(3) { @transport.call("/v1/soul/requests/cancel", identity, token, 3, {}) }
          rescue StandardError
            # The caller must obtain positive cleanup evidence below.
          end
        end
      end
      progress&.call("state" => "synthesizing", "summary" => "Waiting for the selected roster member; Stop is request-specific.")
      response = @transport.call("/v1/chat/completions", {"model" => member, "messages" => messages, "stream" => false}, token, 215,
        {"X-Soul-Conversation-Id" => identity.fetch("conversation_id")})
      if cancel.call
        confirm_cancellation!(identity, token)
      end
      soul = response.fetch("soul")
      unless response["model"] == member && soul["model"] == member &&
          soul["conversation_id"] == identity["conversation_id"] && soul["request_id"] == identity["request_id"] && soul["adapter"] == adapter.binding
        raise RuntimeError, "coordinator attribution mismatch"
      end
      choice = response.fetch("choices").first
      content = choice&.dig("message", "content")
      unless choice&.dig("message", "role") == "assistant" && choice["finish_reason"] == "stop" && content.is_a?(String) && content.valid_encoding? && content.bytesize.between?(1, 65_536)
        raise RuntimeError, "invalid coordinator answer"
      end
      execution=soul["execution"]
      if execution
        validate_execution!(execution, identity, adapter, messages, content, member)
      end
      Result.new(content: content, mode: execution ? "roster_read_only" : "roster_text_only",
        provider_id: execution ? execution.fetch("provider") : "local.roster", metadata: soul)
    rescue RosterAdmissionBusy
      raise
    rescue ChatCancellation::Confirmed
      raise
    rescue StandardError
      confirm_cancellation!(identity, token) if identity && token && cancel.call
      raise RuntimeError, "roster request failed; retained state requires review, no automatic retry"
    ensure
      mutex&.synchronize { done = true; changed.broadcast }
      raise RuntimeError, "cancellation watcher did not terminate" if watcher && !watcher.join(5)
      token&.clear
    end

    private

    def coordinator_port = 8096
    def member_adapter(member) = RosterChatAdapter.new(model: member, isolated: RosterChatAdapter::ISOLATED_MODELS.include?(member))
    def validate_execution!(execution, identity, adapter, messages, content, member)
      raise RuntimeError, "invalid deterministic attribution" unless execution["provider"]=="deterministic.read_only" && execution["selected_member"]==member && valid_execution_origin?(execution, identity, adapter, messages) && execution["result_sha256"]==Digest::SHA256.hexdigest(content)
    end

    # The old deterministic-only receipt stays valid. Model-proposed reads need
    # their typed scope and current input binding; a model_invoked flag is not proof.
    def valid_execution_origin?(execution,identity,adapter,messages)
      return true if execution['model_invoked']==false
      return false unless execution.keys.sort==%w[input_sha256 model_invoked operation proposal proposal_sha256 provider result_sha256 selected_member state tool_executed] &&
        execution['model_invoked']==true && %w[complete failed awaiting_input blocked_for_human_review].include?(execution['state']) &&
        /\A[a-f0-9]{64}\z/.match?(execution['proposal_sha256'].to_s) &&
        execution['input_sha256']==RosterConversationGateway.digest(identity.merge('adapter'=>adapter.binding,'messages'=>messages))
      if execution['tool_executed']==false
        return execution['operation']=='proposal.invalid' && execution['state']=='awaiting_input' && execution['proposal'].nil?
      end
      decision=RosterToolProposalPolicy.resolve(JSON.generate({'soul_tool_proposal'=>execution['proposal']}))
      execution['tool_executed']==true && decision['kind']=='tool' && decision['operation']==execution['operation']
    end

    # Preserve audit rows; omit only exact, proven unadmitted sends from model history.
    def without_unadmitted_busy_messages(rows, chat_id)
      rows.reject do |row|
        id = row.dig("metadata", "application_request_id")
        receipt = id && @receipt_store&.find(id)
        next false unless receipt && receipt["status"] == "failed" && receipt["failure_category"] == "roster_busy_not_admitted"
        digest = Digest::SHA256.hexdigest(JSON.generate({"chat_id"=>chat_id.to_s,"message"=>row["content"]}))
        unless row["role"] == "user" && receipt.values_at("operation","identity","input_digest") == ["chats.send",chat_id,digest] &&
            rows.count{|r|r.dig("metadata","application_request_id")==id} == 1
          raise RuntimeError, "busy audit identity changed"
        end
        true
      end
    end

    def without_maintenance_exchanges(rows)
      excluded = []
      rows.each_with_index do |row, index|
        next unless row["role"] == "assistant" && row.dig("metadata", "runtime", "deterministic_workflow") == "maintenance"
        prior = index.positive? && rows[index - 1]
        request_id = row.dig("metadata", "application_request_id")
        unless row.dig("metadata", "provider_id") == "deterministic.maintenance" &&
            request_id.is_a?(String) && !request_id.empty? && prior && prior["role"] == "user" &&
            prior.dig("metadata", "application_request_id") == request_id
          raise RuntimeError, "incomplete maintenance exchange; retained history requires review"
        end
        excluded.concat([index - 1, index])
      end
      rows.each_with_index.filter_map { |row, index| row unless excluded.include?(index) }
    end

    def confirm_cancellation!(identity, token)
      receipt = @transport.call("/v1/soul/requests/status", identity, token, 3, {})
      unless receipt.values_at("conversation_id", "request_id") == identity.values_at("conversation_id", "request_id") &&
          receipt["state"] == "canceled_released" && receipt["cleanup_confirmed"] == true
        raise RuntimeError, "cancellation cleanup unconfirmed"
      end
      raise ChatCancellation::Confirmed
    end

    def post(path, body, token, seconds, headers)
      payload = JSON.generate(body)
      raise ArgumentError, "bounded request required" if payload.bytesize > 131_072
      Timeout.timeout(seconds) do
        http = Net::HTTP.new("127.0.0.1", coordinator_port, nil)
        http.open_timeout = 2
        http.read_timeout = seconds
        http.write_timeout = 2
        http.max_retries = 0
        request = Net::HTTP::Post.new(path, headers.merge("Authorization" => "Bearer #{token}", "Content-Type" => "application/json", "Accept-Encoding" => "identity"))
        request.body = payload
        bytes = +""
        code = nil
        http.start do |connection|
          connection.request(request) do |response|
            code = response.code
            response.read_body do |chunk|
              bytes << chunk
              raise RuntimeError, "oversized coordinator response" if bytes.bytesize > 262_144
            end
          end
        end
        refuse_response!(path, code, bytes) unless code == "200"
        ContinuityLab.parse(bytes)
      end
    end

    def refuse_response!(path, code, bytes)
      detail = JSON.parse(bytes) rescue {}
      if path == "/v1/soul/compute/telemetry"
        raise TelemetryDiagnostic::Refused.new(detail.is_a?(Hash) ? detail.dig("error", "code") : nil)
      end
      error = detail.is_a?(Hash) && detail["error"]
      if path == "/v1/chat/completions" && code == "409" && error.is_a?(Hash) && error["code"] == "roster_busy" && error["request_admitted"] == false
        raise RosterAdmissionBusy, RosterAdmissionBusy::MESSAGE
      end
      raise RuntimeError, "coordinator request refused"
    end

    def read_key
      raise RuntimeError, "canonical credential required" unless File.realpath(KEY) == KEY
      stat = File.lstat(KEY)
      unless stat.file? && stat.uid == Process.uid && stat.nlink == 1 && (stat.mode & 0o777) == 0o600 && stat.size.between?(32, 257)
        raise RuntimeError, "private credential required"
      end
      File.open(KEY, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
        raise RuntimeError, "credential changed" unless [stat.dev, stat.ino] == [file.stat.dev, file.stat.ino]
        value = file.read(258).delete_suffix("\n")
        raise RuntimeError, "invalid credential" unless value.match?(/\A[!-~]{32,256}\z/)
        value
      end
    end
  end
end

require_relative "cpu_member_dashboard_runtime"
