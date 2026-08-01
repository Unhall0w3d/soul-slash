# frozen_string_literal: true

require "json"
require "optparse"
require "pathname"
require "tmpdir"
require_relative "dev_worker_service"

module SoulCore
  class DevWorkerCommand
    MAX_REQUEST_BYTES = 320 * 1024

    def initialize(argv:, root: Dir.pwd, env: ENV, output: $stdout, service: nil)
      @argv = argv.dup
      @root = File.expand_path(root)
      @env = env
      @output = output
      @service = service || DevWorkerService.new(root: @root, env: @env)
    end

    def run
      action = @argv.shift.to_s
      options = parse_options(@argv)
      request = read_request(options.fetch(:request_file))
      envelope = case action
                 when "preview" then @service.preview(request: request)
                 when "execute"
                   @service.execute(
                     request: request,
                     confirmation: options[:confirmation],
                     expected_digest: options[:expected_digest]
                   )
                 else
                   failure("usage: soul dev-worker <preview|execute> --request-file PATH [--confirmation PHRASE --expected-digest SHA256]")
                 end
      @output.puts(JSON.pretty_generate(envelope))
      envelope["ok"] ? 0 : 2
    rescue OptionParser::ParseError, KeyError, JSON::ParserError, ArgumentError => error
      @output.puts(JSON.pretty_generate(failure("Soul Dev Worker request failed safely: #{error.message}")))
      2
    rescue Interrupt
      @output.puts(JSON.pretty_generate(failure("Soul Dev Worker was canceled.", lifecycle: "canceled")))
      130
    end

    private

    def parse_options(argv)
      options = {}
      OptionParser.new do |parser|
        parser.on("--request-file PATH") { |value| options[:request_file] = value }
        parser.on("--confirmation PHRASE") { |value| options[:confirmation] = value }
        parser.on("--expected-digest SHA256") { |value| options[:expected_digest] = value }
      end.parse!(argv)
      raise OptionParser::InvalidOption, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?
      options
    end

    def read_request(value)
      raise ArgumentError, "request file is required" if value.to_s.empty?
      expanded = File.expand_path(value.to_s)
      resolved = File.realpath(expanded)
      roots = [@root, File.expand_path(Dir.tmpdir)]
      allowed = roots.any? { |root| resolved.start_with?(root + File::SEPARATOR) }
      raise ArgumentError, "request file must remain below the repository or temporary directory" unless allowed

      File.open(expanded, File::RDONLY | File::NOFOLLOW) do |io|
        stat = io.stat
        raise ArgumentError, "request file must be a regular non-symlink file" unless stat.file?
        raise ArgumentError, "request file must be owned by the invoking user" unless stat.uid == Process.uid
        raise ArgumentError, "request file exceeds #{MAX_REQUEST_BYTES} bytes" if stat.size > MAX_REQUEST_BYTES
        JSON.parse(io.read(MAX_REQUEST_BYTES + 1))
      end
    rescue Errno::ELOOP
      raise ArgumentError, "request file must be a regular non-symlink file"
    rescue Errno::ENOENT
      raise ArgumentError, "request file does not exist"
    end

    def failure(message, lifecycle: "blocked_for_human_review")
      {
        "schema_version" => DevWorkerService::RESULT_SCHEMA,
        "ok" => false,
        "lifecycle_state" => lifecycle,
        "message" => message,
        "data" => {},
        "mutation" => "none"
      }
    end
  end
end
