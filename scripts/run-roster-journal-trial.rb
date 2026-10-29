#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "run-roster-adapter-trial"
require_relative "../lib/soul_core/roster_conversation_gateway"

# Opt-in synthetic acceptance harness, not a service or a production selector.
# Reuses the already-qualified process, socket ownership, telemetry and guards.
class RosterJournalTrial < RosterAdapterTrial
  BUDGET_SECONDS = 600
  # Explicit workday trial allowance; production and sibling trials stay unchanged.
  def self.compositor_limit_bytes = 1536 * 1024**2
  def create_output = Dir.mktmpdir("roster-journal-trial-", QUALIFICATION)
  def roster_ids = IDS
  def roster_assets = ASSETS
  def isolated_models = []
  def roster_adapter(id) = SoulCore::RosterChatAdapter.new(model:id,isolated:isolated_models.include?(id))

  class Driver
    def initialize(trial) = @trial = trial
    def binding = @trial.roster_binding
    def start(**args) = @trial.roster_start(**args)
    def observe(**args) = @trial.roster_observe(**args)
    def stop_and_verify(**args) = @trial.roster_stop(**args)
    def request(method, path, payload, deadline:)
      raise ChatReplacementTrial::Abort, "unexpected route" unless method == "POST" && %w[/apply-template /tokenize /v1/chat/completions].include?(path)
      @trial.roster_bounded(deadline) { @trial.adapter_http(path, payload, deadline: deadline) }
    end
  end

  def roster_binding
    roster_ids.to_h do |id|
      asset = roster_assets.fetch(id)
      [id, {"artifact_sha256"=>asset.fetch("sha256"), "server_sha256"=>BINARY_SHA,
        "launch_sha256"=>Digest::SHA256.hexdigest(JSON.generate({"argv"=>self.class.argv(id,asset.fetch("path")),
          "driver_source_sha256"=>Digest::SHA256.file(__FILE__).hexdigest,
          "artifact_verifier_sha256"=>Digest::SHA256.file(File.join(__dir__,"run-chat-replacement-trial.rb")).hexdigest}))}]
    end
  end

  def roster_bounded(deadline)
    remaining = deadline - now
    raise Abort, "runtime deadline exhausted" unless remaining.positive?
    Timeout.timeout(remaining, Abort, "runtime operation deadline") { yield }
  end

  # /usr/bin/env execs the server in place: its options are not part of the
  # server's /proc cmdline. Keep the complete launcher in the immutable binding,
  # but attest the resulting executable arguments AND selected environment.
  def self.validate_process_launch!(launch:, argv:, environment:)
    prefix = ["/usr/bin/env", "-u", "VK_ICD_FILENAMES",
      "VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json",
      "VK_LOADER_LAYERS_DISABLE=~implicit~", "GGML_VK_VISIBLE_DEVICES=0"]
    raise Abort, "unrecognized launch wrapper" unless launch.first(prefix.length) == prefix && launch[prefix.length] == BINARY
    raise Abort, "owned launch changed" unless argv == launch.drop(prefix.length)
    required = {"VK_DRIVER_FILES"=>"/usr/share/vulkan/icd.d/radeon_icd.json",
      "VK_LOADER_LAYERS_DISABLE"=>"~implicit~", "GGML_VK_VISIBLE_DEVICES"=>"0", "CUDA_VISIBLE_DEVICES"=>"0"}
    entries = environment.split("\0").map { |entry| entry.split("=",2) }
    required.each do |key,value|
      raise Abort, "owned launch environment changed" unless entries.select { |k,_| k==key } == [[key,value]]
    end
    raise Abort, "forbidden Vulkan override" if entries.any? { |key,_| key=="VK_ICD_FILENAMES" }
    true
  end

  def roster_start(adapter:, ownership_id:, deadline:, cancel:)
    raise Abort, "qualified conversation defaults only" unless adapter.binding == roster_adapter(adapter.model).binding
    @ownership = ownership_id
    @candidate, @model = adapter.model, roster_assets.fetch(adapter.model).fetch("path")
    @output = File.join(@root_output, ownership_id)
    Dir.mkdir(@output,0700)
    roster_bounded(deadline) do
      raise Abort, "canceled before load" if cancel.call
      timed_phase("preflight") do
        raise Abort, "protected state changed" unless protected_state == @before
        raise Abort, "endpoint occupied" unless port_closed?
      end
      asset=roster_assets.fetch(@candidate)
      timed_phase("model_integrity") { verify_file!(@model,asset.fetch("size_bytes"),asset.fetch("sha256")) }
      timed_phase("server_integrity") { raise Abort, "server changed" unless Digest::SHA256.file(BINARY).hexdigest==BINARY_SHA }
      timed_phase("cooldown") { cool_down }
      timed_phase("resource_admission") { validate_resources!(sample_resources,admission:true) }
      @reaped_pid=nil
      timed_phase("spawn_to_ready") { start }
      start_monitor
    end
  end

  # Measurements only: retain integrity/resource checks and their order. A phase
  # spans wall-clock monotonic time, not CPU/GPU execution time alone.
  def timed_phase(name)
    raise ArgumentError, "unknown phase" unless %w[preflight model_integrity server_integrity cooldown resource_admission spawn_to_ready teardown release_observation].include?(name)
    started=now
    phase_error=nil
    state="failed"
    value=yield
    state="complete"
    value
  rescue ChatReplacementTrial::Abort, StandardError => error
    phase_error=error
    raise
  ensure
    if started
      original=$!
      begin
        save("phase-#{name}.json",{"phase"=>name,"state"=>state,"elapsed_seconds"=>now-started,
          "model"=>@candidate,"error_class"=>phase_error&.class&.name,
          "guard_reason"=>(phase_error.message.gsub(/[[:cntrl:]]/," ").slice(0,512) if phase_error.is_a?(ChatReplacementTrial::Abort))})
      rescue StandardError
        raise unless original
        # Do not mask an existing abort with a secondary diagnostic-write error.
      end
    end
  end

  def roster_observe(ownership_id:, deadline:)
    roster_bounded(deadline) do
      raise Abort, "foreign runtime ownership" unless @ownership == ownership_id && @pid
      validate_resources!(sample_resources)
      raise Abort, "owned executable changed" unless File.realpath("/proc/#{@pid}/exe") == File.realpath(BINARY)
      environment=File.binread("/proc/#{@pid}/environ",1_048_577)
      raise Abort, "oversized owned environment" if environment.bytesize > 1_048_576
      self.class.validate_process_launch!(launch:self.class.argv(@candidate,@model),
        argv:File.binread("/proc/#{@pid}/cmdline",65_537).split("\0"),environment:environment)
      ticks=File.read("/proc/#{@pid}/stat").split(") ",2).last.split.fetch(19)
      {"ownership_id"=>ownership_id,"model"=>@candidate,"identity"=>roster_binding.fetch(@candidate),
        "pid"=>@pid,"process_start"=>ticks,"captured_at"=>now,"admitted"=>true}
    end
  end

  def roster_stop(ownership_id:, deadline:)
    raise Abort, "foreign cleanup refused" unless @ownership==ownership_id
    roster_bounded(deadline) do
      stopped=@pid
      timed_phase("teardown") { cleanup_owned_runtime }
      raise Abort, "endpoint survived cleanup" unless port_closed?
      timed_phase("release_observation") { wait_for_release(stopped) } if stopped
      raise Abort, "protected state changed" unless @before==protected_state
      @ownership=nil
      true
    end
  end

  def run
    File.umask(0077)
    @root_output=create_output
    @output=@root_output
    started=now
    state,error="failed",nil
    gateway=nil
    @canceled=false
    signals=%w[INT TERM].to_h { |s| [s,Signal.trap(s) { @canceled=true; raise Abort,"Canceled" }] }
    begin
      Timeout.timeout(BUDGET_SECONDS,Abort,"journal trial deadline") do
        @before=protected_state
        raise Abort,"production runtime active" unless @before.fetch("unit").include?("ActiveState=inactive") &&
          @before.fetch("amd_units").scan(/^ActiveState=(.*)$/).flatten==["inactive","inactive"]
        raise Abort,"endpoint occupied" unless port_closed?
        start_telemetry
        sample=sample_resources
        @desktop_baseline=desktop_baseline(sample)
        validate_resources!(sample,admission:true)
        owner=SoulCore::RosterRuntimeOwner.new(leases:runtime_lease_store,driver:Driver.new(self),isolated_models:isolated_models)
        journal=File.join(@root_output,"journal")
        SoulCore::RosterConversationGateway.create(path:journal,owner:owner)
        gateway=SoulCore::RosterConversationGateway.new(path:journal,owner:owner)
        save("preflight.json",{"protected"=>@before,"binding"=>roster_binding,
          "journal_binding"=>SoulCore::RosterConversationGateway.manifest(owner),
          "max_replies"=>2*roster_ids.length,"seconds"=>BUDGET_SECONDS,"swap_out_limit_pages"=>MixedGpuPilot::SWAP_OUT_LIMIT_PAGES,
          "task"=>"Fictional shelf location Pine corrected to Birch; location recalled on second turn",
          "limitations"=>"synthetic journal/switch acceptance only; no LibreChat activation or idle residency"})
        histories=roster_ids.to_h { |id| [id,[]] }
        2.times do |turn|
          roster_ids.each_with_index do |id,index|
            history=histories.fetch(id)
            history << {"role"=>"user","content"=>turn.zero? ? "Fictional shelf: Pine. Correction: it is Birch. Confirm the corrected shelf in one short sentence." : "Which shelf did I correct it to? Answer briefly."}
            args={conversation_id:"synthetic#{index}",request_id:"r#{index}-#{turn}",adapter:roster_adapter(id),messages:history,deadline:now+180,cancel:-> { @canceled }}
            puts JSON.generate(state:"starting",model:id,turn:turn,output:@root_output); $stdout.flush
            result=gateway.complete(**args)
            replay=gateway.complete(**args.merge(deadline:now+180))
            raise Abort,"durable replay mismatch" unless replay["replayed"] && replay["content"]==result["content"]
            history << {"role"=>"assistant","content"=>result.fetch("content")}
          end
        end
        state="completed_pending_answer_review"
      end
    rescue Abort,StandardError => problem
      error="#{problem.class}: #{problem.message}".slice(0,1024)
    ensure
      begin
        begin
          gateway&.close
        ensure
          begin
            cleanup_owned_runtime
          ensure
            stop_telemetry
          end
        end
        @after=protected_state
        raise Abort,"protected state changed" unless @before==@after
        raise Abort,"endpoint survived cleanup" unless port_closed?
      rescue Abort,StandardError => problem
        state,error="failed",[error,"cleanup: #{problem.class}: #{problem.message}".slice(0,1024)].compact.join("; ")
      end
      @output=@root_output
      save("resource-samples.json",@samples)
      save("receipt.json",{"state"=>state,"error"=>error,"elapsed_seconds"=>now-started,
        "protected_before"=>@before,"protected_after"=>@after,"owned_pid_if_unreaped"=>@pid})
      signals.each { |s,h| Signal.trap(s,h) }
    end
    puts JSON.generate(state:state,error:error,output:@root_output)
    state=="completed_pending_answer_review"
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Expected explicit journal trial flag" unless ARGV==["--approved-roster-journal-trial"]
  exit(RosterJournalTrial.new.run ? 0 : 1)
end
