#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "roster-desktop-librechat-trial"
require_relative "../lib/soul_core/roster_warm_backend"

# Explicit bounded qualification, not an installed or unattended service.
class RosterWarmLibreChatTrial < RosterLibreChatTrial
  BUDGET_SECONDS=600
  IDLE_SECONDS=240
  def create_output = Dir.mktmpdir("roster-warm-librechat-",QUALIFICATION)
  def self.validate_amd!(sample,previous:,owned_pid:)
    DesktopCoexistenceTrial.validate_amd!(sample,previous:previous,owned_pid:owned_pid)
  end
  def self.argv(candidate,model)
    args=super
    args[args.index("--tensor-split")+1]="1,1" if candidate=="gemma-4-26b-a4b"
    args
  end
  def validate_resources!(sample,admission:false)
    super
    raise Abort,"NVIDIA runtime reserve below 1024 MiB" if sample.fetch("free_mib")<1024
  end
  def roster_binding
    sources=[__FILE__,File.join(__dir__,"run-desktop-coexistence-trial.rb"),
      File.join(ROOT,"lib/soul_core/roster_warm_session.rb"),File.join(ROOT,"lib/soul_core/roster_warm_backend.rb")]
    super.transform_values { |b| b.merge("launch_sha256"=>Digest::SHA256.hexdigest(JSON.generate(
      base:b["launch_sha256"],sources:sources.to_h { |p| [p,Digest::SHA256.file(p).hexdigest] },
      idle_seconds:IDLE_SECONDS,session_seconds:BUDGET_SECONDS,baseline:DesktopCoexistenceTrial::BASELINE_SHA))) }
  end
  class WarmDriver < Driver
    def creative_release_verified?(**args) = @trial.creative_release_verified?(**args)
    def creative_telemetry = @trial.creative_telemetry
    def activate_request(deadline:,cancel:)
      @trial.stop_cancel_watcher
      @trial.start_cancel_watcher(cancel)
      true
    end
    def park(deadline:)
      @trial.stop_cancel_watcher
      # The existing resource monitor remains active, owned by the dispatcher.
      raise ChatReplacementTrial::Abort,"idle monitor absent" unless @trial.instance_variable_get(:@monitor)&.alive?
      true
    end
  end
  def serve(key_file:)
    File.umask(0077)
    @root_output=create_output
    @output=@root_output
    started=now
    state,error="failed",nil
    server=supervisor=nil
    begin
      @before=protected_state
      raise Abort,"production runtime active" unless @before.fetch("unit").include?("ActiveState=inactive") &&
        @before.fetch("amd_units").scan(/^ActiveState=(.*)$/).flatten==["inactive","inactive"]
      raise Abort,"model endpoint occupied" unless port_closed?
      token=SoulCore::ContinuityLab::ChatCLI.read_key(key_file)
      start_telemetry
      sample=sample_resources
      @desktop_baseline=desktop_baseline(sample)
      validate_resources!(sample,admission:true)
      owner=SoulCore::RosterWarmSession.new(leases:runtime_lease_store,driver:WarmDriver.new(self),idle_seconds:IDLE_SECONDS,isolated_models:isolated_models)
      backend=SoulCore::RosterWarmBackend.new(owner:owner,path:File.join(@root_output,"journal"))
      app=SoulCore::RosterChatApplication.new(backend:backend,bearer_token:token,isolated_models:isolated_models)
      token.clear
      server=SoulCore::RosterChatServer.new(host:"127.0.0.1",port:HTTP_PORT,application:app,max_requests:HTTP_REQUEST_LIMIT)
      save("preflight.json",{"binding"=>roster_binding,"seconds"=>BUDGET_SECONDS,"idle_seconds"=>IDLE_SECONDS,
        "scope"=>"foreground single-resident warm conversation; explicit presets; no tools or peer automation"})
      backend.run(seconds:BUDGET_SECONDS) do
        supervisor=Thread.new do
          sleep 0.1 until backend.finished? || now-started>=BUDGET_SECONDS-2
          server.stop
        end
        puts JSON.generate(state:"ready_to_listen",output:@root_output,seconds:BUDGET_SECONDS,idle_seconds:IDLE_SECONDS)
        server.run
      end
      state="completed_pending_client_review"
    rescue Abort,StandardError => problem
      error="#{problem.class}: #{problem.message}".slice(0,1024)
    ensure
      token&.clear
      server&.stop
      supervisor&.kill
      supervisor&.join
      begin
        # Warm owner exclusively owns cleanup; never retry an uncertain release.
        stop_telemetry
        @after=protected_state
        raise Abort,"cleanup verification failed" unless @before==@after && port_closed? && !@pid
      rescue Abort,StandardError => problem
        state,error="failed","cleanup: #{problem.class}: #{problem.message}".slice(0,1024)
      end
      @output=@root_output
      save("resource-samples.json",@samples)
      save("receipt.json",{"state"=>state,"error"=>error,"elapsed_seconds"=>now-started,
        "protected_before"=>@before,"protected_after"=>@after,"owned_pid_if_unreaped"=>@pid})
    end
    puts JSON.generate(state:state,error:error,output:@root_output)
    state=="completed_pending_client_review"
  end
end
if $PROGRAM_NAME==__FILE__
  abort "Expected --approved-warm-librechat --key-file OWNER_PRIVATE_KEY" unless ARGV.length==3 && ARGV.first(2)==%w[--approved-warm-librechat --key-file]
  exit(RosterWarmLibreChatTrial.new.serve(key_file:ARGV.last) ? 0 : 1)
end
