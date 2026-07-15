# frozen_string_literal: true

require_relative "application_facade"
require_relative "configuration_resolver"
require_relative "dashboard_authentication"
require_relative "dashboard_http_application"
require_relative "dashboard_server"

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
      application = DashboardHttpApplication.new(root: @root, facade: facade, bind_host: host, port: port, public_origin: public_origin)
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
