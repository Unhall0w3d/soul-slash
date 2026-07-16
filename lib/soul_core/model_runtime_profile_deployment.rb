# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "tempfile"
require_relative "bounded_command_runner"

module SoulCore
  class ModelRuntimeProfileDeployment
    UNIT_NAME = "soul-model-amd.service"
    MARKER = "# Managed by Soul Model Runtime Profile Deployment"
    CONFIRM_INSTALL = "INSTALL_INACTIVE_AMD_MODEL_UNIT"
    CONFIRM_UNINSTALL = "REMOVE_INACTIVE_AMD_MODEL_UNIT"
    SHA256 = /\A[a-f0-9]{64}\z/
    ALIAS = /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,79}\z/
    COMMAND_TIMEOUT_SECONDS = 12
    MAX_OUTPUT_BYTES = 16 * 1024

    Result = Struct.new(:ok, :lifecycle_state, :message, :details, keyword_init: true) do
      def to_h
        { "ok" => ok, "lifecycle_state" => lifecycle_state, "message" => message, "details" => details }
      end
    end

    def initialize(root:, home: Dir.home, systemctl_path: nil, systemd_analyze_path: nil, runner: BoundedCommandRunner.new)
      @root = File.expand_path(root)
      @home = File.expand_path(home)
      @systemctl_path = systemctl_path || find_executable("systemctl")
      @systemd_analyze_path = systemd_analyze_path || find_executable("systemd-analyze")
      @runner = runner
    end

    def plan(server_path:, model_path:, expected_server_sha256:, expected_model_sha256:, model_alias:, host: "127.0.0.1", port: 8082)
      inputs = validate_inputs(
        server_path: server_path, model_path: model_path,
        expected_server_sha256: expected_server_sha256, expected_model_sha256: expected_model_sha256,
        model_alias: model_alias, host: host, port: port
      )
      return inputs if inputs.is_a?(Result)

      unit = render_unit(inputs)
      Result.new(
        ok: true,
        lifecycle_state: "blocked_for_human_review",
        message: "Inactive AMD unit deployment plan is valid. Review and confirm installation.",
        details: public_plan(inputs, unit).merge(
          "confirmation_phrase" => CONFIRM_INSTALL,
          "commands" => [["systemctl", "--user", "daemon-reload"]],
          "will_start" => false,
          "will_enable" => false,
          "will_stop_nvidia" => false
        )
      )
    end

    def install(**options)
      confirmation = options.delete(:confirmation)
      planned = plan(**options)
      return planned unless planned.ok
      unless confirmation == CONFIRM_INSTALL
        return Result.new(ok: false, lifecycle_state: "awaiting_input", message: "Exact inactive-unit installation confirmation is required.", details: planned.details)
      end

      inputs = validate_inputs(**options)
      return inputs if inputs.is_a?(Result)
      unit = render_unit(inputs)
      existing = existing_unit(unit)
      return existing if existing.is_a?(Result)

      validation = validate_rendered_unit(unit)
      return validation unless validation.ok

      nvidia_before = nvidia_digests
      wrote = existing == :missing
      write_unit(unit) if wrote
      reload = run_systemctl("daemon-reload")
      unless reload.success?
        File.unlink(unit_path) if wrote && safe_managed_unit?
        return failed("systemd user-manager reload failed", "stderr" => bounded(reload.stderr))
      end

      observed = status
      return observed unless observed.ok
      unless observed.details["load_state"] == "loaded" && observed.details["active_state"] == "inactive" && !observed.details["enabled"]
        return Result.new(
          ok: false, lifecycle_state: "blocked_for_human_review",
          message: "AMD unit did not remain loaded, inactive, and unenabled.",
          details: observed.details.merge("unit_path" => unit_path, "written" => wrote)
        )
      end
      return failed("NVIDIA rollback unit changed during AMD installation") unless nvidia_digests == nvidia_before

      Result.new(
        ok: true, lifecycle_state: "complete", message: "AMD model unit installed, loaded, inactive, and unenabled.",
        details: planned.details.merge(observed.details).merge("installed" => true, "written" => wrote, "nvidia_unchanged" => true)
      )
    rescue SystemCallError, IOError => error
      failed("AMD unit installation failed safely: #{error.class}")
    end

    def status
      return failed("systemctl is unavailable") unless executable?(@systemctl_path)
      return Result.new(ok: true, lifecycle_state: "complete", message: "AMD model unit is not installed.", details: { "installed" => false, "unit_path" => unit_path, "load_state" => "not-found", "active_state" => "inactive", "enabled" => false }) unless File.exist?(unit_path) || File.symlink?(unit_path)
      return failed("AMD model unit path is not a regular managed file") unless safe_managed_unit?

      load_state = systemctl_property("LoadState")
      active_state = systemctl_property("ActiveState")
      unit_file_state = systemctl_property("UnitFileState")
      return failed("AMD model unit state could not be read") if [load_state, active_state, unit_file_state].any?(&:nil?)

      Result.new(
        ok: true, lifecycle_state: "complete", message: "AMD model unit status collected.",
        details: {
          "installed" => true,
          "unit_path" => unit_path,
          "load_state" => load_state,
          "active_state" => active_state,
          "unit_file_state" => unit_file_state,
          "enabled" => %w[enabled enabled-runtime linked linked-runtime alias].include?(unit_file_state),
          "unit_sha256" => Digest::SHA256.file(unit_path).hexdigest
        }
      )
    end

    def uninstall(confirmation: nil)
      unless confirmation == CONFIRM_UNINSTALL
        return Result.new(
          ok: false, lifecycle_state: "awaiting_input", message: "Exact inactive-unit removal confirmation is required.",
          details: { "confirmation_phrase" => CONFIRM_UNINSTALL, "unit_path" => unit_path }
        )
      end
      current = status
      return current unless current.ok
      return current unless current.details.fetch("installed")
      if current.details.fetch("active_state") != "inactive"
        return Result.new(ok: false, lifecycle_state: "blocked_for_human_review", message: "AMD unit must be explicitly unloaded before removal.", details: current.details)
      end

      File.unlink(unit_path)
      reload = run_systemctl("daemon-reload")
      return failed("systemd user-manager reload failed after unit removal", "stderr" => bounded(reload.stderr)) unless reload.success?

      Result.new(ok: true, lifecycle_state: "complete", message: "Inactive AMD model unit removed.", details: { "removed" => unit_path, "service_stopped" => false })
    rescue SystemCallError, IOError => error
      failed("AMD unit removal failed safely: #{error.class}")
    end

    private

    def validate_inputs(server_path:, model_path:, expected_server_sha256:, expected_model_sha256:, model_alias:, host:, port:)
      errors = []
      server = safe_regular_file(server_path, executable: true)
      model = safe_regular_file(model_path, executable: false)
      server_sha = expected_server_sha256.to_s
      model_sha = expected_model_sha256.to_s
      numeric_port = Integer(port.to_s, 10) rescue nil
      errors << "Vulkan llama-server must be an executable regular non-symlink file." unless server
      errors << "Ministral model must be a regular non-symlink file." unless model
      errors << "Server SHA-256 must be lowercase hexadecimal." unless server_sha.match?(SHA256)
      errors << "Model SHA-256 must be lowercase hexadecimal." unless model_sha.match?(SHA256)
      errors << "Model alias is invalid." unless model_alias.to_s.match?(ALIAS)
      errors << "AMD model service must bind exact loopback host 127.0.0.1." unless host.to_s == "127.0.0.1"
      errors << "AMD model service port must be unprivileged." unless numeric_port&.between?(1024, 65_535)
      errors << "systemctl is unavailable." unless executable?(@systemctl_path)
      errors << "systemd-analyze is unavailable." unless executable?(@systemd_analyze_path)
      if server && server_sha.match?(SHA256)
        errors << "Server SHA-256 digest mismatch." unless Digest::SHA256.file(server).hexdigest == server_sha
      end
      if model && model_sha.match?(SHA256)
        errors << "Model SHA-256 digest mismatch." unless Digest::SHA256.file(model).hexdigest == model_sha
      end
      return failed(errors.first, "errors" => errors) unless errors.empty?

      {
        "server_path" => server,
        "model_path" => model,
        "server_sha256" => server_sha,
        "model_sha256" => model_sha,
        "model_alias" => model_alias.to_s,
        "host" => host.to_s,
        "port" => numeric_port
      }
    end

    def safe_regular_file(value, executable:)
      path = File.expand_path(value.to_s)
      stat = File.lstat(path)
      return nil unless stat.file? && !stat.symlink?
      return nil if executable && !File.executable?(path)

      path
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end

    def render_unit(inputs)
      argv = [
        inputs.fetch("server_path"), "-m", inputs.fetch("model_path"), "-a", inputs.fetch("model_alias"),
        "--host", inputs.fetch("host"), "--port", inputs.fetch("port").to_s,
        "-c", "8192", "-n", "2048", "-np", "1", "-ngl", "999", "-dev", "Vulkan0", "-fa", "on",
        "--jinja", "--metrics", "--slots", "--reasoning", "off", "--timeout", "120"
      ]
      <<~UNIT
        #{MARKER}
        # server-sha256=#{inputs.fetch("server_sha256")}
        # model-sha256=#{inputs.fetch("model_sha256")}
        [Unit]
        Description=Soul AMD Vulkan model runtime
        After=network.target
        StartLimitIntervalSec=60
        StartLimitBurst=3

        [Service]
        Type=simple
        ExecStart=#{argv.map { |value| unit_quote(value) }.join(' ')}
        Restart=on-failure
        RestartSec=3
        TimeoutStopSec=30
        UMask=0077
        NoNewPrivileges=true
        PrivateTmp=true
        ProtectSystem=strict
        ProtectHome=read-only
        ProtectControlGroups=true
        ProtectKernelModules=true
        ProtectKernelTunables=true
        RestrictSUIDSGID=true
        LockPersonality=true
        RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
      UNIT
    end

    def public_plan(inputs, unit)
      {
        "unit_name" => UNIT_NAME,
        "unit_path" => unit_path,
        "server_path" => inputs.fetch("server_path"),
        "model_path" => inputs.fetch("model_path"),
        "server_sha256" => inputs.fetch("server_sha256"),
        "model_sha256" => inputs.fetch("model_sha256"),
        "model_alias" => inputs.fetch("model_alias"),
        "bind" => "#{inputs.fetch('host')}:#{inputs.fetch('port')}",
        "unit_sha256" => Digest::SHA256.hexdigest(unit),
        "argv" => unit.lines.find { |line| line.start_with?("ExecStart=") }.to_s.delete_prefix("ExecStart=").strip.split(" ")
      }
    end

    def existing_unit(rendered)
      return :missing unless File.exist?(unit_path) || File.symlink?(unit_path)
      return failed("refusing symlink or non-regular AMD unit destination") unless safe_managed_unit?
      return :matching if File.binread(unit_path, 128 * 1024) == rendered

      failed("existing AMD unit differs from the reviewed deployment")
    end

    def safe_managed_unit?
      stat = File.lstat(unit_path)
      stat.file? && !stat.symlink? && File.binread(unit_path, 128 * 1024).start_with?(MARKER)
    rescue Errno::ENOENT, Errno::EACCES
      false
    end

    def validate_rendered_unit(content)
      Tempfile.create([UNIT_NAME.delete_suffix(".service"), ".service"]) do |file|
        file.chmod(0o600)
        file.write(content)
        file.flush
        result = @runner.run(@systemd_analyze_path, "--user", "verify", file.path, timeout_seconds: COMMAND_TIMEOUT_SECONDS, max_output_bytes: MAX_OUTPUT_BYTES)
        return failed("systemd rejected the rendered AMD unit", "stderr" => bounded(result.stderr)) unless result.success?
      end
      Result.new(ok: true, lifecycle_state: "complete", message: "Rendered AMD unit is valid.", details: {})
    end

    def write_unit(content)
      directory = File.dirname(unit_path)
      ensure_private_directory(directory)
      raise IOError, "refusing symlink unit destination" if File.symlink?(unit_path)
      temporary = "#{unit_path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      File.rename(temporary, unit_path)
      File.chmod(0o600, unit_path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary)
    end

    def ensure_private_directory(directory)
      relative = directory.delete_prefix("#{@home}#{File::SEPARATOR}")
      raise IOError, "unit directory must remain below home" if relative == directory

      cursor = @home
      relative.split(File::SEPARATOR).each do |component|
        cursor = File.join(cursor, component)
        if File.exist?(cursor) || File.symlink?(cursor)
          stat = File.lstat(cursor)
          raise IOError, "unit directory must not contain symlinks" if stat.symlink?
          raise IOError, "unit path component must be a directory" unless stat.directory?
        else
          Dir.mkdir(cursor, 0o700)
        end
      end
    end

    def systemctl_property(property)
      result = @runner.run(
        @systemctl_path, "--user", "show", UNIT_NAME, "--property=#{property}", "--value", "--no-pager",
        timeout_seconds: COMMAND_TIMEOUT_SECONDS, max_output_bytes: MAX_OUTPUT_BYTES
      )
      result.success? ? result.stdout.to_s.strip : nil
    end

    def run_systemctl(*arguments)
      @runner.run(@systemctl_path, "--user", *arguments, timeout_seconds: COMMAND_TIMEOUT_SECONDS, max_output_bytes: MAX_OUTPUT_BYTES)
    end

    def nvidia_digests
      paths = [
        File.join(@home, ".config/systemd/user/llama-server.service"),
        File.join(@home, ".config/systemd/user/llama-server.service.d/override.conf")
      ]
      paths.to_h { |path| [path, File.file?(path) && !File.symlink?(path) ? Digest::SHA256.file(path).hexdigest : nil] }
    end

    def unit_path
      File.join(@home, ".config/systemd/user", UNIT_NAME)
    end

    def unit_quote(value)
      text = value.to_s
      raise ArgumentError, "unit argument contains a control character" if text.match?(/[\x00-\x1f\x7f]/)

      %Q("#{text.gsub('\\', '\\\\').gsub('"', '\\"')}")
    end

    def find_executable(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
        path = File.join(directory, name)
        return path if File.file?(path) && File.executable?(path)
      end
      nil
    end

    def executable?(path)
      path && File.file?(path) && File.executable?(path)
    end

    def bounded(value)
      value.to_s.byteslice(0, MAX_OUTPUT_BYTES)
    end

    def failed(message, details = {})
      Result.new(ok: false, lifecycle_state: "failed", message: message, details: details)
    end
  end
end
