# frozen_string_literal: true

require "fileutils"
require "ipaddr"
require "json"
require "open3"
require "rbconfig"
require "socket"
require "time"

module SoulCore
  class DashboardDeployment
    CONFIRM_INSTALL = "INSTALL_SOUL_LAN_SERVICES"
    CONFIRM_UNINSTALL = "REMOVE_SOUL_LAN_SERVICES"
    SERVICE_NAMES = %w[soul-dashboard.service soul-dashboard-proxy.service].freeze
    DEFAULT_HTTPS_PORT = 8443
    SOUL_PORT = 4567

    Result = Struct.new(:ok, :lifecycle_state, :message, :details, keyword_init: true) do
      def to_h
        { "ok" => ok, "lifecycle_state" => lifecycle_state, "message" => message, "details" => details }
      end
    end

    def initialize(root:, home: Dir.home, ruby_path: RbConfig.ruby, caddy_path: nil, systemctl_path: nil,
                   assigned_addresses: nil, command_runner: nil, clock: -> { Time.now.utc })
      @root = File.expand_path(root)
      @home = File.expand_path(home)
      @ruby_path = File.expand_path(ruby_path)
      @caddy_path = caddy_path || find_executable("caddy")
      @systemctl_path = systemctl_path || find_executable("systemctl")
      @assigned_addresses = assigned_addresses || local_ipv4_addresses
      @command_runner = command_runner || method(:capture_command)
      @clock = clock
    end

    def plan(lan_host:, https_port: DEFAULT_HTTPS_PORT)
      validation = validate(lan_host, https_port)
      return validation unless validation.ok

      host = validation.details.fetch("lan_host")
      port = validation.details.fetch("https_port")
      origin = "https://#{host}:#{port}"
      Result.new(
        ok: true,
        lifecycle_state: "blocked_for_human_review",
        message: "Deployment plan is valid. Review exact paths and confirm installation.",
        details: validation.details.merge(
          "public_origin" => origin,
          "confirmation_phrase" => CONFIRM_INSTALL,
          "files" => rendered_paths,
          "services" => SERVICE_NAMES,
          "root_ca_path" => root_ca_path,
          "internet_exposure" => false,
          "soul_bind" => "127.0.0.1:#{SOUL_PORT}"
        )
      )
    end

    def install(lan_host:, https_port: DEFAULT_HTTPS_PORT, confirmation: nil)
      planned = plan(lan_host: lan_host, https_port: https_port)
      return planned unless planned.ok
      unless confirmation == CONFIRM_INSTALL
        return Result.new(ok: false, lifecycle_state: "awaiting_input", message: "Exact installation confirmation is required.", details: planned.details)
      end

      contents = rendered_contents(lan_host: planned.details.fetch("lan_host"), https_port: planned.details.fetch("https_port"))
      validation = validate_caddy(contents.fetch("caddyfile"))
      return validation unless validation.ok

      write_rendered_files(contents)
      commands = [
        [@systemctl_path, "--user", "daemon-reload"],
        [@systemctl_path, "--user", "enable", "--now", "soul-dashboard.service"],
        [@systemctl_path, "--user", "enable", "--now", "soul-dashboard-proxy.service"]
      ]
      commands.each do |command|
        execution = run(command)
        next if execution.fetch("success")

        rollback_services
        return Result.new(
          ok: false,
          lifecycle_state: "failed",
          message: "Service installation failed safely at #{command.drop(1).join(' ')}.",
          details: planned.details.merge("command" => command.drop(1), "stderr" => bounded_output(execution.fetch("stderr")))
        )
      end

      Result.new(
        ok: true,
        lifecycle_state: "complete",
        message: "Soul LAN HTTPS services installed and started.",
        details: planned.details.merge("installed_at" => @clock.call.iso8601)
      )
    rescue SystemCallError, IOError => error
      rollback_services
      Result.new(ok: false, lifecycle_state: "failed", message: "Deployment write failed safely: #{error.class}.", details: { "services" => SERVICE_NAMES })
    end

    def uninstall(confirmation: nil)
      unless confirmation == CONFIRM_UNINSTALL
        return Result.new(
          ok: false,
          lifecycle_state: "awaiting_input",
          message: "Exact uninstall confirmation is required.",
          details: { "confirmation_phrase" => CONFIRM_UNINSTALL, "preserved" => preserved_paths }
        )
      end

      rollback_services
      rendered_paths.values.each { |path| File.delete(path) if safe_rendered_file?(path) }
      run([@systemctl_path, "--user", "daemon-reload"]) if @systemctl_path
      Result.new(
        ok: true,
        lifecycle_state: "complete",
        message: "Soul LAN services removed. Private runtime and Caddy PKI state were preserved.",
        details: { "removed" => rendered_paths.values, "preserved" => preserved_paths }
      )
    rescue SystemCallError, IOError => error
      Result.new(ok: false, lifecycle_state: "failed", message: "Uninstall failed safely: #{error.class}.", details: { "preserved" => preserved_paths })
    end

    def status
      return Result.new(ok: false, lifecycle_state: "failed", message: "systemctl is unavailable.", details: {}) unless @systemctl_path

      services = SERVICE_NAMES.to_h do |service|
        execution = run([@systemctl_path, "--user", "show", service, "--property=ActiveState,SubState,UnitFileState", "--no-pager"])
        [service, { "query_ok" => execution.fetch("success"), "state" => bounded_output(execution.fetch("stdout")) }]
      end
      Result.new(ok: services.values.all? { |value| value.fetch("query_ok") }, lifecycle_state: "complete", message: "Service status collected.", details: { "services" => services })
    end

    def rendered_contents(lan_host:, https_port: DEFAULT_HTTPS_PORT)
      origin = "https://#{lan_host}:#{https_port}"
      {
        "environment" => <<~ENVFILE,
          SOUL_DASHBOARD_BIND_HOST=127.0.0.1
          SOUL_DASHBOARD_PORT=#{SOUL_PORT}
          SOUL_DASHBOARD_PUBLIC_ORIGIN=#{origin}
        ENVFILE
        "caddyfile" => <<~CADDYFILE,
          {
            admin off
            auto_https disable_redirects
            servers {
              protocols h1 h2
            }
          }

          #{origin} {
            bind #{lan_host}
            tls internal
            reverse_proxy 127.0.0.1:#{SOUL_PORT} {
              transport http {
                dial_timeout 3s
                response_header_timeout 180s
              }
            }
            header {
              Strict-Transport-Security "max-age=31536000"
              X-Content-Type-Options "nosniff"
              Referrer-Policy "no-referrer"
            }
          }
        CADDYFILE
        "soul_unit" => <<~UNIT,
          [Unit]
          Description=Soul authenticated dashboard
          After=network.target
          StartLimitIntervalSec=60
          StartLimitBurst=3

          [Service]
          Type=simple
          WorkingDirectory=#{unit_path(@root)}
          EnvironmentFile=-%h/.config/soul/dashboard.env
          ExecStart=#{unit_quote(@ruby_path)} #{unit_quote(File.join(@root, "bin/soul"))} dashboard
          Restart=on-failure
          RestartSec=5
          TimeoutStopSec=15
          UMask=0077
          NoNewPrivileges=true
          PrivateTmp=true
          ProtectSystem=strict
          ReadWritePaths=#{unit_path(@root)}
          ProtectControlGroups=true
          ProtectKernelModules=true
          ProtectKernelTunables=true
          RestrictSUIDSGID=true
          LockPersonality=true
          RestrictAddressFamilies=AF_INET AF_INET6

          [Install]
          WantedBy=default.target
        UNIT
        "proxy_unit" => <<~UNIT
          [Unit]
          Description=Soul LAN HTTPS reverse proxy
          Requires=soul-dashboard.service
          After=network-online.target soul-dashboard.service
          Wants=network-online.target
          StartLimitIntervalSec=60
          StartLimitBurst=3

          [Service]
          Type=simple
          Environment=XDG_DATA_HOME=%h/.local/share
          Environment=XDG_CONFIG_HOME=%h/.config
          ExecStart=#{unit_quote(@caddy_path.to_s)} run --config %h/.config/soul/Caddyfile --adapter caddyfile
          Restart=on-failure
          RestartSec=5
          TimeoutStopSec=15
          UMask=0077
          NoNewPrivileges=true
          PrivateTmp=true
          ProtectSystem=strict
          ReadWritePaths=%h/.local/share/caddy %h/.config/soul
          ProtectControlGroups=true
          ProtectKernelModules=true
          ProtectKernelTunables=true
          RestrictSUIDSGID=true
          LockPersonality=true
          RestrictAddressFamilies=AF_INET AF_INET6

          [Install]
          WantedBy=default.target
        UNIT
      }
    end

    private

    def validate(lan_host, https_port)
      errors = []
      address = begin
        IPAddr.new(lan_host.to_s)
      rescue IPAddr::InvalidAddressError
        nil
      end
      port = Integer(https_port.to_s, 10) rescue nil
      errors << "LAN host must be one exact assigned non-loopback IPv4 address." unless address&.ipv4? && !address.loopback? && !address.to_i.zero? && @assigned_addresses.include?(address.to_s)
      errors << "HTTPS port must be an unprivileged port between 1024 and 65535." unless port&.between?(1024, 65_535)
      errors << "HTTPS port must differ from Soul's loopback port." if port == SOUL_PORT
      errors << "Caddy is not installed in PATH." unless @caddy_path && File.file?(@caddy_path) && File.executable?(@caddy_path)
      errors << "systemctl is unavailable." unless @systemctl_path && File.file?(@systemctl_path) && File.executable?(@systemctl_path)
      errors << "Ruby executable is unavailable." unless File.file?(@ruby_path) && File.executable?(@ruby_path)
      errors << "Soul project entrypoint is unavailable." unless File.file?(File.join(@root, "bin/soul"))
      errors.concat(authentication_errors)

      return Result.new(ok: false, lifecycle_state: "failed", message: errors.first, details: { "errors" => errors }) unless errors.empty?

      Result.new(ok: true, lifecycle_state: "complete", message: "Deployment prerequisites are valid.", details: { "lan_host" => address.to_s, "https_port" => port, "caddy_path" => @caddy_path, "systemctl_path" => @systemctl_path, "ruby_path" => @ruby_path, "project_root" => @root })
    end

    def authentication_errors
      path = File.join(@root, "Soul/runtime/dashboard_auth/credentials.json")
      return ["Dashboard authentication credential is missing; complete first login before deployment."] unless File.file?(path) && !File.symlink?(path)
      return ["Dashboard credential permissions must be owner-only."] unless (File.stat(path).mode & 0o077).zero?

      record = JSON.parse(File.read(path, 16 * 1024))
      return ["Bootstrap password replacement is required before deployment."] if record["password_change_required"] != false

      []
    rescue JSON::ParserError, ArgumentError, Errno::EACCES
      ["Dashboard authentication credential cannot be validated safely."]
    end

    def validate_caddy(content)
      directory = File.join(@root, "Soul/runtime/verification")
      FileUtils.mkdir_p(directory, mode: 0o700)
      path = File.join(directory, "Caddyfile.deploy-#{Process.pid}")
      File.open(path, "w", 0o600) { |file| file.write(content) }
      execution = run([@caddy_path, "validate", "--config", path, "--adapter", "caddyfile"])
      return Result.new(ok: true, lifecycle_state: "complete", message: "Caddy configuration is valid.", details: {}) if execution.fetch("success")

      Result.new(ok: false, lifecycle_state: "failed", message: "Caddy rejected the generated configuration.", details: { "stderr" => bounded_output(execution.fetch("stderr")) })
    ensure
      File.delete(path) if defined?(path) && path && File.exist?(path)
    end

    def write_rendered_files(contents)
      paths = rendered_paths
      ensure_private_directory(File.dirname(paths.fetch("environment")))
      ensure_private_directory(File.dirname(paths.fetch("soul_unit")))
      ensure_private_directory(File.join(@home, ".local/share/caddy"))
      atomic_write(paths.fetch("environment"), contents.fetch("environment"), 0o600)
      atomic_write(paths.fetch("caddyfile"), contents.fetch("caddyfile"), 0o600)
      atomic_write(paths.fetch("soul_unit"), contents.fetch("soul_unit"), 0o600)
      atomic_write(paths.fetch("proxy_unit"), contents.fetch("proxy_unit"), 0o600)
    end

    def atomic_write(path, content, mode)
      raise IOError, "refusing symlink destination" if File.symlink?(path)
      temporary = "#{path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      File.chmod(mode, path)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def ensure_private_directory(directory)
      relative = directory.delete_prefix("#{@home}#{File::SEPARATOR}")
      raise IOError, "rendered directory must remain below home" if relative == directory

      cursor = @home
      relative.split(File::SEPARATOR).each do |component|
        cursor = File.join(cursor, component)
        if File.exist?(cursor) || File.symlink?(cursor)
          stat = File.lstat(cursor)
          raise IOError, "rendered directory must not contain symlinks" if stat.symlink?
          raise IOError, "rendered path component must be a directory" unless stat.directory?
        else
          Dir.mkdir(cursor, 0o700)
        end
      end
      File.chmod(0o700, directory)
    end

    def rendered_paths
      {
        "environment" => File.join(@home, ".config/soul/dashboard.env"),
        "caddyfile" => File.join(@home, ".config/soul/Caddyfile"),
        "soul_unit" => File.join(@home, ".config/systemd/user/soul-dashboard.service"),
        "proxy_unit" => File.join(@home, ".config/systemd/user/soul-dashboard-proxy.service")
      }
    end

    def root_ca_path
      File.join(@home, ".local/share/caddy/pki/authorities/local/root.crt")
    end

    def preserved_paths
      [File.join(@root, "Soul/runtime"), File.join(@home, ".local/share/caddy")]
    end

    def safe_rendered_file?(path)
      rendered_paths.value?(path) && File.file?(path) && !File.symlink?(path)
    end

    def rollback_services
      return unless @systemctl_path

      SERVICE_NAMES.reverse_each { |service| run([@systemctl_path, "--user", "disable", "--now", service]) }
    end

    def local_ipv4_addresses
      Socket.getifaddrs.filter_map do |interface|
        address = interface.addr
        address.ip_address if address&.ipv4? && !address.ipv4_loopback?
      end.uniq
    end

    def find_executable(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
        candidate = File.join(directory, name)
        return File.expand_path(candidate) if File.file?(candidate) && File.executable?(candidate)
      end
      nil
    end

    def unit_quote(value)
      %Q{"#{value.to_s.gsub("\\", "\\\\").gsub('"', '\\"')}"}
    end

    def unit_path(value)
      value.to_s.bytes.map do |byte|
        character = byte.chr
        character.match?(/[A-Za-z0-9_\.\-\/]/) ? character : format("\\x%02x", byte)
      end.join
    end

    def capture_command(command)
      stdout, stderr, status = Open3.capture3(*command)
      { "success" => status.success?, "stdout" => stdout, "stderr" => stderr }
    end

    def run(command)
      @command_runner.call(command)
    rescue SystemCallError => error
      { "success" => false, "stdout" => "", "stderr" => error.class.to_s }
    end

    def bounded_output(value)
      value.to_s.encode("UTF-8", invalid: :replace, undef: :replace).byteslice(0, 4_096).to_s
    end
  end
end
