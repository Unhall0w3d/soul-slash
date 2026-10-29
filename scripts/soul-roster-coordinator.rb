#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "support/roster_service_driver"
require_relative "../lib/soul_core/roster_service_backend"
require_relative "../lib/soul_core/roster_tool_proposal_v5_archive"
require_relative "../lib/soul_core/roster_service_application"

module SoulRosterCoordinator
  ROOT=File.expand_path("..",__dir__)
  STATE=File.join(ROOT,"Soul/private/roster_service")
  KEY="/home/bhones/.config/soul/continuity-a24.key"

  Application = SoulCore::RosterServiceApplication

  def self.run
    raise "ordinary-user coordinator required" if Process.uid.zero?
    File.umask(0077)
    Dir.mkdir(STATE,0700) unless File.exist?(STATE)
    directory=SoulCore::RosterConversationGateway::Directory.new(STATE)
    lock=File.open(File.join(STATE,"coordinator.lock"),File::RDWR|File::CREAT|File::NOFOLLOW,0600)
    raise "coordinator already active" unless lock.flock(File::LOCK_EX|File::LOCK_NB)
    output=Dir.mktmpdir("session-",STATE)
    driver=RosterServiceDriver.new(output:output)
    owner=SoulCore::RosterServiceSession.new(leases:driver.runtime_lease_store,
      driver:RosterWarmLibreChatTrial::WarmDriver.new(driver),isolated_models:driver.isolated_models)
    path=File.join(STATE,"journal-tool-proposals-v13")
    raise "explicit journal archive import required" if !File.exist?(path) && %w[journal journal-memory-v2 journal-archive-v3 journal-read-only-v4 journal-navigation-v5 journal-source-navigation-v6 journal-symbol-pages-v7 journal-source-excerpts-v8 journal-tool-proposals-v9 journal-tool-proposals-v10 journal-tool-proposals-v11 journal-tool-proposals-v12].any? { |n| File.exist?(File.join(STATE,n)) }
    mode=File.exist?(path) || File.symlink?(path) ? :resume : :create
    memory=SoulCore::RosterMemoryContext.new(store:SoulCore::ConversationMemoryStore.new(root:ROOT,create:false))
    backend=SoulCore::RosterServiceBackend.new(owner:owner,path:path,journal_mode:mode,
      gateway_class:SoulCore::RosterToolProposalV5Archive,memory:memory)
    token=SoulCore::ContinuityLab::ChatCLI.read_key(KEY)
    app=Application.new(backend:backend,bearer_token:token,isolated_models:driver.isolated_models)
    token.clear
    server=SoulCore::RosterChatServer.new(host:"127.0.0.1",port:8096,application:app)
    backend.run do
      supervisor=Thread.new do
        sleep 0.5 until backend.finished?
        server.stop
      end
      begin
        server.run
      ensure
        supervisor.kill
        supervisor.join
      end
    end
    true
  ensure
    token&.clear
    server&.stop
    directory&.close
    lock&.close
  end
end

if $PROGRAM_NAME==__FILE__
  abort "Expected --serve" unless ARGV==["--serve"]
  begin
    SoulRosterCoordinator.run
  rescue StandardError => error
    warn JSON.generate(state:"failed",error_class:error.class.name)
    exit 1
  end
end
