# frozen_string_literal: true
require_relative "../roster-qwen38-librechat-trial"
require_relative "../../lib/soul_core/gpu_accounting_snapshot"
require_relative "../../lib/soul_core/creative_render_guard"
require_relative "../../lib/soul_core/desktop_gpu_allowances"
require_relative "../../lib/soul_core/creative_workload_admission"
require_relative "../../lib/soul_core/chat_workload_admission"

# Reuse qualified native launch/identity/thermal/memory/release checks. This
# separate entry point replaces only privileged collection and residency scope.
class RosterServiceDriver < RosterQwen38LibreChatTrial
  def self.validate_amd!(sample, previous:, owned_pid:)
    SoulCore::ChatWorkloadAdmission.amd!(sample, owned_pid: owned_pid)
  rescue ArgumentError, KeyError => error
    raise Abort, error.message
  end

  def self.validate_sample!(sample, expected_pid:, admission:, desktop_baseline: [], cutoff_c: 80)
    SoulCore::ChatWorkloadAdmission.nvidia!(sample, expected_pid: expected_pid, admission: admission, cutoff_c: cutoff_c)
  rescue ArgumentError, KeyError => error
    raise Abort, error.message
  end

  # Music has not qualified the independent resource policy; retain its exact
  # previous release gate instead of inheriting chat's new desktop admission.
  def self.validate_music_amd!(sample, previous:, owned_pid:)
    allowed = DesktopCoexistenceTrial.baseline_holders + SoulCore::DesktopGpuAllowances.holders
    DesktopCoexistenceTrial.validate_desktop_amd!(sample, owned_pid: owned_pid, allowed: allowed)
  end

  def initialize(output:)
    super()
    @root_output=@output=output
  end

  # Owner chose host-wide paging as diagnostic evidence, not an abort signal.
  # It cannot attribute pressure to this request; physical headroom still gates.
  def validate_swap_out!(sample)
    pages=sample.fetch('swap_delta_pages')
    raise Abort, 'invalid paging telemetry' unless pages.is_a?(Integer) && pages >= 0
  end

  def roster_binding
    super.transform_values do |binding|
      binding.merge("launch_sha256"=>Digest::SHA256.hexdigest(JSON.generate(
        base:binding.fetch("launch_sha256"),service_driver:Digest::SHA256.file(__FILE__).hexdigest,
        creative_admission:Digest::SHA256.file(File.join(ROOT,"lib/soul_core/creative_workload_admission.rb")).hexdigest,
        chat_admission:Digest::SHA256.file(File.join(ROOT,"lib/soul_core/chat_workload_admission.rb")).hexdigest,
        resource_driver:Digest::SHA256.file(File.join(ROOT,"scripts/run-mixed-gpu-pilot.rb")).hexdigest,
        session:Digest::SHA256.file(File.join(ROOT,"lib/soul_core/roster_service_session.rb")).hexdigest)))
    end
  end

  def roster_start(**args)
    @ownership=args.fetch(:ownership_id)
    @output=@root_output
    @before=protected_state
    @initial_swap=nil
    @samples=[]
    raise Abort,"legacy runtime active" unless @before.fetch("unit").include?("ActiveState=inactive") &&
      @before.fetch("amd_units").scan(/^ActiveState=(.*)$/).flatten==["inactive","inactive"]
    raise Abort,"model endpoint occupied" unless port_closed?
    start_telemetry
    sample=sample_resources
    @desktop_baseline=[] # Admission depends on resources, not a frozen app list.
    validate_resources!(sample,admission:true)
    super
  rescue ChatReplacementTrial::Abort => error
    save("startup-guard-refusal.json", {"error_class"=>error.class.name,"reason"=>error.message.slice(0,1024)})
    # The warm owner still verifies release before returning this error. A
    # refused admission must not kill the listener or grant a generation retry.
    raise SoulCore::RosterRuntimeOwner::Unavailable, "startup guard refused; inspect private receipt"
  end

  def roster_stop(**args)
    super
  ensure
    stop_telemetry
  end

  def wait_for_release(stopped_pid)
    # Teardown already reaped the exact owned process group. Fresh release
    # evidence must not reuse its pre-teardown allocation, or demand that an
    # unrelated application's memory usage fits a *new launch* budget.
    stop_telemetry
    barrier=now
    deadline=barrier+10
    client=SoulCore::GpuAccountingSnapshot.new
    observations=[]
    loop do
      amd=client.sample
      nvidia=creative_nvidia_sample
      raise Abort,'unexpected NVIDIA release device' unless nvidia.fetch('name')=='NVIDIA GeForce GTX 1070'
      raise Abort,'release observation deadline' if now>=deadline
      released=self.class.released_sample?(amd,stopped_pid:stopped_pid,after:barrier) &&
        !nvidia.fetch('compute_pids').include?(stopped_pid)
      observations = released ? observations + [{'amd'=>amd,'nvidia'=>nvidia}] : []
      if observations.length==2
        raise Abort,'release samples did not advance' unless observations.last['amd']['monotonic']>observations.first['amd']['monotonic']
        save('release-observed.json',{'stopped_pid'=>stopped_pid,'after'=>barrier,'observations'=>observations,
          'scope'=>'owned runtime released; not admission for another workload'})
        return
      end
      raise Abort,'previous model release not observed' if now>=deadline
      sleep 0.1
    end
  end

  # A lease disappearing is not GPU release evidence. Reuse the qualified
  # holder allowlist with no owned PID exemption. Only AMD visual work may
  # coexist with unrelated NVIDIA clients; model and music rules stay strict.
  def creative_release_verified?(provider_id: nil)
    return false unless [nil, 'amd-visual', 'amd-music'].include?(provider_id)
    return false if @pid || !port_closed?
    client = SoulCore::GpuAccountingSnapshot.new
    first = client.sample
    if provider_id == 'amd-visual'
      SoulCore::CreativeWorkloadAdmission.amd_visual!(first)
    else
      self.class.validate_music_amd!(first, previous: nil, owned_pid: nil)
    end
    second = client.sample
    if provider_id == 'amd-visual'
      SoulCore::CreativeWorkloadAdmission.amd_visual!(second)
    else
      self.class.validate_music_amd!(second, previous: first, owned_pid: nil)
    end
    runner = SoulCore::BoundedCommandRunner.new
    units = runner.run("systemctl", "--user", "show", "llama-server.service", "soul-model-gemma.service", "soul-model-dev.service", "--property=ActiveState", timeout_seconds: 5, max_output_bytes: 8192)
    nvidia_ok = if provider_id == 'amd-visual'
      sample = creative_nvidia_sample
      compositor = sample.fetch('processes').select { |p| p['comm'] == 'kwin_wayland' }
      baseline = desktop_baseline(sample.merge('processes'=>compositor))
      SoulCore::CreativeWorkloadAdmission.nvidia_environment!(sample,
        runtime_paths: [MixedGpuPilot::BINARY, ChatReplacementTrial::SERVER],
        desktop_pids: baseline.map { |p| p.fetch('pid') })
    else
      creative_nvidia_released?
    end
    nvidia_ok && units.success? && !units.truncated &&
      units.stdout.scan(/^ActiveState=(.*)$/).flatten == %w[inactive inactive inactive]
  rescue ChatReplacementTrial::Abort, StandardError
    false
  end

  def creative_nvidia_sample
    ChatReplacementTrial.instance_method(:sample_resources).bind_call(self)
  end

  def creative_telemetry
    @creative_snapshot ||= SoulCore::GpuAccountingSnapshot.new
    SoulCore::CreativeRenderGuard.new(root: ROOT).capture(@creative_snapshot)
  end

  def creative_nvidia_released?
    # Keep the already-qualified small, identity-checked Plasma allowance; it
    # is not a model process and must not make every handoff fail on Wayland.
    sample = ChatReplacementTrial.instance_method(:sample_resources).bind_call(self)
    ChatReplacementTrial.validate_sample!(sample, expected_pid: nil, admission: false,
      desktop_baseline: desktop_baseline(sample), cutoff_c: 88)
    true
  end

  def start_telemetry
    raise Abort,"telemetry already active" if @telemetry_thread&.alive?
    @telemetry_stopping=false
    @telemetry=@telemetry_error=nil
    client=SoulCore::GpuAccountingSnapshot.new
    @telemetry_thread=Thread.new do
      previous=nil
      until @telemetry_stopping
        sampled_pid=@pid
        sample=client.sample
        # Collection spans time: a launch/teardown can change ownership while
        # the helper is sampling. Never classify or publish that mixed epoch.
        # Release still requires a fresh sample proving the stopped PID absent.
        if sampled_pid != @pid
          previous=nil
          next
        end
        self.class.validate_amd!(sample,previous:previous,owned_pid:sampled_pid)
        @telemetry_mutex.synchronize { @telemetry=sample } if previous
        previous=sample
        sleep 0.5 unless @telemetry_stopping
      end
    rescue Abort,StandardError => error
      @telemetry_mutex.synchronize { @telemetry_error="#{error.class}: #{error.message}".slice(0,512) } unless @telemetry_stopping
    end
    wait_for_telemetry!(deadline:now+10)
  end

  def stop_telemetry
    return unless @telemetry_thread
    @telemetry_stopping=true
    raise Abort,"snapshot collector shutdown unverified" unless @telemetry_thread.join(9)
    @telemetry_thread=nil
    @telemetry=nil
  end
end
