#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "rbconfig"
require_relative "../lib/soul_core/continuity_lab/chat_gateway"
require_relative "../lib/soul_core/continuity_lab/chat_executor"
require_relative "../lib/soul_core/continuity_lab/chat_application"
require_relative "../lib/soul_core/dashboard_server"

module SoulCore
  module ContinuityLab
    class ForegroundChatServer < DashboardServer
      def initialize(executor:, **options)
        @executor = executor
        super(**options)
      end

      def stop
        @executor.cancel!
        super
      end

      private

      def install_signal_handlers
        @previous_handlers = {}
        %w[INT TERM].each do |signal|
          @previous_handlers[signal] = Signal.trap(signal) { @executor.cancel!; raise Interrupt }
        end
      end
    end

    module ChatCLI
      RUBY = "/home/bhones/.rbenv/versions/4.0.7/bin/ruby"
      PORT = 8094

      def self.run(argv)
        raise ValidationError, "use repository-pinned Ruby 4.0.7" unless RbConfig.ruby == RUBY
        options = { seconds: 1800, max_requests: 32 }
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: ruby scripts/continuity-lab-chat.rb (--init|--check|--serve) PRIVATE_ROOT [options]"
          opts.on("--init PATH", "Create an empty experimental adapter root; no listener/model call") { |path| select(options, :init, path) }
          opts.on("--check PATH", "Check retained root/config; no listener/model call") { |path| select(options, :check, path) }
          opts.on("--serve PATH", "Explicit bounded foreground loopback activation") { |path| select(options, :serve, path) }
          opts.on("--corpus PATH", "Explicit JSON array of id/content records; init only") { |path| options[:corpus] = path }
          opts.on("--key-file PATH", "Owner-private 0600 token file; serve only; never printed") { |path| options[:key_file] = path }
          opts.on("--approved-quiet-window", "Confirm sole local-model client during this foreground session") { options[:quiet] = true }
          opts.on("--seconds N", Integer, "Bound session to 30..3600 seconds (default 1800)") { |n| options[:seconds] = n }
          opts.on("--max-requests N", Integer, "HTTP request ceiling 1..128 (default 32)") { |n| options[:max_requests] = n }
          opts.on("--help") { puts opts; return 0 }
        end
        parser.parse!(argv)
        raise ValidationError, "one exact operation/root required" unless argv.empty? && options[:mode]
        raise ValidationError, "invalid session bounds" unless options[:seconds].between?(30, 3600) && options[:max_requests].between?(1, 128)
        raise ValidationError, "corpus is immutable after initialization" if options[:corpus] && options[:mode] != :init
        if options[:mode] != :serve && (options[:quiet] || options[:key_file])
          raise ValidationError, "activation options require serve"
        end
        File.umask(0o077)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + options[:seconds]
        executor = ChatExecutor.new(deadline: deadline, max_generations: options[:max_requests])
        if options[:mode] == :init
          corpus = options[:corpus] ? read_corpus(options[:corpus]) : []
          ChatGateway.create(path: options[:path], executor: executor, corpus: corpus)
          puts ContinuityLab.encode("state" => "complete", "operation" => "init", "listener_started" => false)
          return 0
        end
        gateway = ChatGateway.new(path: options[:path], executor: executor)
        if options[:mode] == :check
          puts ContinuityLab.encode("state" => "complete", "operation" => "check", "backend_health_checked" => false, "listener_started" => false)
          return 0
        end
        raise ValidationError, "serve requires key file and explicit quiet window" unless options[:quiet] && options[:key_file]
        token = read_key(options[:key_file])
        application = ChatApplication.new(backend: gateway, bearer_token: token)
        token.clear
        executor.prepare!
        server = ForegroundChatServer.new(executor: executor, host: "127.0.0.1", port: PORT,
          application: application, max_requests: options[:max_requests])
        # Bounded session supervision, not a daemon or later continuation. The
        # supervisor is joined before return; stop cancels/reaps the worker.
        supervisor = Thread.new do
          loop do
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            break if remaining <= 0
            sleep [remaining, 0.25].min
          end
          server.stop
        end
        state = server.run
        puts ContinuityLab.encode("state" => state, "operation" => "serve", "listener_stopped" => true)
        0
      rescue OptionParser::ParseError, Error, SystemCallError, JSON::ParserError => error
        warn ContinuityLab.encode("state" => "failed", "class" => error.class.name,
          "reason" => error.is_a?(Error) || error.is_a?(OptionParser::ParseError) ? error.message : "local operation unavailable")
        2
      ensure
        executor&.cancel!
        server&.stop
        supervisor&.kill
        supervisor&.join
        gateway&.close
      end

      def self.select(options, mode, path)
        raise ValidationError, "select only one operation" if options[:mode]
        options[:mode], options[:path] = mode, path
      end

      def self.read_corpus(path)
        stat = File.lstat(path)
        raise ValidationError, "bounded regular corpus file required" unless stat.file? && !stat.symlink? && stat.size <= 16_384
        File.open(path, File::RDONLY | File::NOFOLLOW) { |file| ContinuityLab.parse(file.read(16_385)) }
      end

      def self.read_key(path)
        raise ValidationError, "canonical key file required" unless File.realpath(path) == path
        stat = File.lstat(path)
        unless stat.file? && !stat.symlink? && stat.uid == Process.uid && stat.nlink == 1 && (stat.mode & 0o777) == 0o600 && stat.size.between?(32, 257)
          raise ValidationError, "key must be an owner-private 0600 regular file"
        end
        File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
          raise ValidationError, "key file changed" unless [file.stat.dev, file.stat.ino] == [stat.dev, stat.ino]
          file.read(258).delete_suffix("\n")
        end
      end
    end
  end
end

exit SoulCore::ContinuityLab::ChatCLI.run(ARGV) if $PROGRAM_NAME == __FILE__
