# frozen_string_literal: true

require_relative "application_facade"
require_relative "configuration_resolver"
require_relative "dashboard_authentication"
require_relative "dashboard_http_application"
require_relative "dashboard_server"
require_relative "voice_transcription_service"
require_relative "voice_synthesis_service"

module SoulCore
  class DashboardCommand
    def initialize(argv:, root:, process_env:, output: $stdout)
      @argv = argv.dup
      @root = root
      @process_env = process_env
      @output = output
    end

    def run
      overrides, max_requests, reset_admin_password = parse_arguments
      if reset_admin_password
        DashboardAuthentication.new(root: @root, reset_to_bootstrap: true)
        @output.puts "Dashboard administrator reset to the bootstrap credential. Password change is required on next login."
        return 0
      end
      resolver = ConfigurationResolver.new(root: @root, process_env: @process_env, overrides: overrides)
      report = resolver.resolve
      unless report.fetch("ok")
        @output.puts "Dashboard error: configuration validation failed. Run `ruby bin/soul config validate`."
        return 1
      end

      settings = report.fetch("settings")
      host = settings.find { |setting| setting.fetch("key") == "dashboard.bind_host" }.fetch("value")
      port = settings.find { |setting| setting.fetch("key") == "dashboard.port" }.fetch("value")
      public_origin = settings.find { |setting| setting.fetch("key") == "dashboard.public_origin" }.fetch("value")
      facade = ApplicationFacade.new(root: @root, process_env: resolver.effective_environment)
      voice_options = { root: @root }
      voice_root = resolver.effective_environment["SOUL_VOICE_TRANSCRIPTION_ROOT"].to_s
      voice_manifest = resolver.effective_environment["SOUL_VOICE_TRANSCRIPTION_MANIFEST"].to_s
      voice_model = resolver.effective_environment["SOUL_VOICE_TRANSCRIPTION_MODEL"].to_s
      voice_options[:music_root] = voice_root unless voice_root.empty?
      voice_options[:manifest_path] = voice_manifest unless voice_manifest.empty?
      voice_options[:model_name] = voice_model unless voice_model.empty?
      voice_transcription = VoiceTranscriptionService.new(**voice_options)
      synthesis_options = { root: @root, process_env: resolver.effective_environment }
      synthesis_root = resolver.effective_environment["SOUL_VOICE_SYNTHESIS_ROOT"].to_s
      synthesis_manifest = resolver.effective_environment["SOUL_VOICE_SYNTHESIS_MANIFEST"].to_s
      synthesis_voice = resolver.effective_environment["SOUL_VOICE_SYNTHESIS_VOICE"].to_s
      synthesis_speed = resolver.effective_environment["SOUL_VOICE_SYNTHESIS_SPEED"].to_s
      expressive_root = resolver.effective_environment["SOUL_VOICE_EXPRESSIVE_ROOT"].to_s
      expressive_manifest = resolver.effective_environment["SOUL_VOICE_EXPRESSIVE_MANIFEST"].to_s
      synthesis_options[:runtime_root] = synthesis_root unless synthesis_root.empty?
      synthesis_options[:manifest_path] = synthesis_manifest unless synthesis_manifest.empty?
      synthesis_options[:voice_name] = synthesis_voice unless synthesis_voice.empty?
      synthesis_options[:speed] = synthesis_speed unless synthesis_speed.empty?
      synthesis_options[:expressive_root] = expressive_root unless expressive_root.empty?
      synthesis_options[:expressive_manifest_path] = expressive_manifest unless expressive_manifest.empty?
      voice_synthesis = VoiceSynthesisService.new(**synthesis_options)
      application = DashboardHttpApplication.new(root: @root, facade: facade, bind_host: host, port: port, public_origin: public_origin, voice_transcription: voice_transcription, voice_synthesis: voice_synthesis)
      lifecycle = DashboardServer.new(host: host, port: port, application: application, max_requests: max_requests, output: @output).run
      @output.puts "Dashboard stopped: #{lifecycle}."
      0
    rescue ArgumentError => error
      @output.puts "Dashboard error: #{error.message}"
      1
    rescue SystemCallError => error
      @output.puts "Dashboard failed to bind: #{error.class}: #{error.message}"
      1
    end

    private

    def parse_arguments
      overrides = []
      max_requests = nil
      reset_admin_password = false
      until @argv.empty?
        argument = @argv.shift
        case argument
        when "--set"
          value = @argv.shift
          raise ArgumentError, "--set requires canonical.key=value" unless value
          overrides << value
        when "--max-requests"
          value = @argv.shift
          raise ArgumentError, "--max-requests requires a positive integer" unless value
          max_requests = Integer(value, 10)
          raise ArgumentError, "--max-requests requires a positive integer" unless max_requests.positive?
        when "--reset-admin-password"
          raise ArgumentError, "--reset-admin-password cannot be combined with listener options" unless overrides.empty? && max_requests.nil? && @argv.empty?
          reset_admin_password = true
        else
          raise ArgumentError, "unknown dashboard argument #{argument}"
        end
      end
      [overrides, max_requests, reset_admin_password]
    rescue ArgumentError => error
      raise error if error.message.start_with?("--", "unknown")

      raise ArgumentError, "--max-requests requires a positive integer"
    end
  end
end
