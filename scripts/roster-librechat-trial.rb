#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "run-roster-journal-trial"
require_relative "continuity-lab-chat"
require_relative "../lib/soul_core/roster_chat_application"
require_relative "../lib/soul_core/roster_chat_server"

# Explicit foreground UI qualification only. No daemon, autostart or model
# residency; each accepted request owns and releases its runtime independently.
class RosterLibreChatTrial < RosterJournalTrial
  HTTP_PORT = 8095
  HTTP_REQUEST_LIMIT = 32

  def create_output = Dir.mktmpdir("roster-librechat-trial-", QUALIFICATION)

  def roster_binding
    super.transform_values do |binding|
      binding.merge("launch_sha256"=>Digest::SHA256.hexdigest(JSON.generate({"base"=>binding["launch_sha256"],
        "foreground_driver"=>Digest::SHA256.file(__FILE__).hexdigest})))
    end
  end

  def roster_start(**args)
    start_cancel_watcher(args.fetch(:cancel))
    super
  end

  def start_cancel_watcher(cancel)
    request_thread=Thread.current
    @cancel_watcher=Thread.new do
      loop do
        if cancel.call
          request_thread.raise(SoulCore::RosterChatExchange::Stopped,"client canceled")
          break
        end
        sleep 0.1
      end
    end
  end

  def roster_stop(**args)
    # Join before teardown so a late disconnect cannot interrupt GPU release.
    stop_cancel_watcher
    super
  end

  def stop_cancel_watcher
    @cancel_watcher&.kill
    @cancel_watcher&.join
    @cancel_watcher=nil
  end

  class Backend
    def initialize(gateway) = @gateway=gateway
    def complete(**args)
      @gateway.complete(**args)
    rescue ChatReplacementTrial::Abort
      # Resource failures leave an uncertain journal blocked, never retryable.
      raise SoulCore::ContinuityLab::Error,"trial guard stopped request; retained state requires review"
    end
  end

  def serve(key_file:)
    File.umask(0o077)
    @root_output=create_output
    @output=@root_output
    started=now
    state,error="failed",nil
    gateway=server=supervisor=nil
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
      owner=SoulCore::RosterRuntimeOwner.new(leases:runtime_lease_store,driver:Driver.new(self))
      journal=File.join(@root_output,"journal")
      SoulCore::RosterConversationGateway.create(path:journal,owner:owner)
      gateway=SoulCore::RosterConversationGateway.new(path:journal,owner:owner)
      app=SoulCore::RosterChatApplication.new(backend:Backend.new(gateway),bearer_token:token)
      token.clear
      save("preflight.json",{"protected"=>@before,"binding"=>roster_binding,
        "seconds"=>self.class::BUDGET_SECONDS,"http_requests"=>HTTP_REQUEST_LIMIT,"port"=>HTTP_PORT,
        "compositor_limit_bytes"=>self.class.compositor_limit_bytes,
        "scope"=>"foreground LibreChat acceptance; fresh conversations only; unload each request"})
      server=SoulCore::RosterChatServer.new(host:"127.0.0.1",port:HTTP_PORT,application:app,max_requests:HTTP_REQUEST_LIMIT)
      supervisor=Thread.new do
        sleep 0.1 while now-started < self.class::BUDGET_SECONDS
        server.stop
      end
      puts JSON.generate(state:"ready_to_listen",output:@root_output,seconds:self.class::BUDGET_SECONDS)
      server.run
      state="completed_pending_client_review"
    rescue Abort,StandardError => problem
      error="#{problem.class}: #{problem.message}".slice(0,1024)
    ensure
      token&.clear
      server&.stop
      supervisor&.kill
      supervisor&.join
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
        raise Abort,"cleanup or protected-state verification failed" if @before!=@after || !port_closed?
      rescue Abort,StandardError => problem
        state,error="failed",[error,"cleanup: #{problem.class}: #{problem.message}".slice(0,1024)].compact.join("; ")
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
  abort "Expected --approved-roster-librechat-trial --key-file OWNER_PRIVATE_KEY" unless ARGV.length==3 && ARGV.first(2)==%w[--approved-roster-librechat-trial --key-file]
  exit(RosterLibreChatTrial.new.serve(key_file:ARGV.last) ? 0 : 1)
end
