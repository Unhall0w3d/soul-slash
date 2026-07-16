# frozen_string_literal: true

require "digest"
require "fileutils"
require "rbconfig"
require "tempfile"
require_relative "bounded_command_runner"

module SoulCore
  class ModelRuntimeStartupDeployment
    UNIT_NAME = "soul-model-runtime-selected.service"
    LEGACY_UNIT = "llama-server.service"
    MARKER = "# Managed by Soul Model Runtime Selected Startup"
    CONFIRM_INSTALL = "INSTALL_SELECTED_MODEL_STARTUP"
    CONFIRM_UNINSTALL = "REMOVE_SELECTED_MODEL_STARTUP"
    COMMAND_TIMEOUT_SECONDS = 12
    MAX_OUTPUT_BYTES = 16 * 1024

    Result = Struct.new(:ok, :lifecycle_state, :message, :details, keyword_init: true) do
      def to_h
        { "ok" => ok, "lifecycle_state" => lifecycle_state, "message" => message, "details" => details }
      end
    end

    def initialize(root:, home: Dir.home, ruby_path: RbConfig.ruby, script_path: nil, systemctl_path: nil, systemd_analyze_path: nil, runner: BoundedCommandRunner.new)
      @root = File.expand_path(root)
      @home = File.expand_path(home)
      @ruby_path = File.expand_path(ruby_path)
      @script_path = File.expand_path(script_path || File.join(@root, "scripts/soul-model-runtime-start-selected"))
      @runner = runner
      @systemctl_path = systemctl_path || @runner.which("systemctl")
      @systemd_analyze_path = systemd_analyze_path || @runner.which("systemd-analyze")
    end

    def plan
      validation = validate_inputs
      return validation if validation

      unit = render_unit
      Result.new(ok: true, lifecycle_state: "blocked_for_human_review", message: "Selected-profile startup plan is valid. Review and confirm installation.", details: {
        "unit_name" => UNIT_NAME,
        "unit_path" => unit_path,
        "unit_sha256" => Digest::SHA256.hexdigest(unit),
        "ruby_path" => @ruby_path,
        "script_path" => @script_path,
        "project_root" => @root,
        "shared_runtime_directory" => runtime_path,
        "confirmation_phrase" => CONFIRM_INSTALL,
        "commands" => [
          ["systemctl", "--user", "daemon-reload"],
          ["systemctl", "--user", "enable", UNIT_NAME],
          ["systemctl", "--user", "disable", LEGACY_UNIT]
        ],
        "will_restart_active_runtime" => false,
        "will_require_reboot" => false,
        "automatic_stop" => false
      })
    end

    def install(confirmation: nil)
      planned = plan
      return planned unless planned.ok
      return awaiting("Exact selected-profile startup installation confirmation is required.", planned.details) unless confirmation == CONFIRM_INSTALL

      unit = render_unit
      existing = existing_unit(unit)
      return existing if existing.is_a?(Result)
      rendered = validate_rendered_unit(unit)
      return rendered unless rendered.ok

      current = status
      return current if existing == :matching && current.ok && current.details["selector_enabled"] && !current.details["legacy_enabled"]

      selector_before = enabled_state(UNIT_NAME)
      legacy_before = enabled_state(LEGACY_UNIT)
      wrote = existing == :missing
      ensure_runtime_directory
      write_unit(unit) if wrote

      reload = run_systemctl("daemon-reload")
      return rollback_failure("systemd user-manager reload failed", wrote, selector_before, legacy_before, reload) unless reload.success?

      enabled = run_systemctl("enable", UNIT_NAME)
      return rollback_failure("selected startup enable failed", wrote, selector_before, legacy_before, enabled) unless enabled.success?

      disabled = run_systemctl("disable", LEGACY_UNIT)
      return rollback_failure("legacy NVIDIA startup disable failed", wrote, selector_before, legacy_before, disabled) unless disabled.success?

      observed = status
      return rollback_failure("selected startup enablement could not be verified", wrote, selector_before, legacy_before, nil) unless observed.ok && observed.details["selector_enabled"] && !observed.details["legacy_enabled"]

      Result.new(ok: true, lifecycle_state: "complete", message: "Selected-profile startup installed and enabled without restarting the active runtime.", details: planned.details.merge(observed.details).merge(
        "installed" => true, "written" => wrote, "active_runtime_restarted" => false, "reboot_required" => false
      ))
    rescue SystemCallError, IOError => error
      failed("selected-profile startup installation failed safely: #{error.class}")
    end

    def status
      unless File.exist?(unit_path) || File.symlink?(unit_path)
        return Result.new(ok: true, lifecycle_state: "complete", message: "Selected-profile startup is not installed.", details: {
          "installed" => false, "unit_path" => unit_path, "selector_enabled" => false, "legacy_enabled" => enabled_state(LEGACY_UNIT) == "enabled"
        })
      end
      return failed("selected startup unit path is not a regular managed file") unless safe_managed_unit?

      selector = enabled_state(UNIT_NAME)
      legacy = enabled_state(LEGACY_UNIT)
      return failed("selected startup enablement state is unknown") if selector == "unknown" || legacy == "unknown"

      Result.new(ok: true, lifecycle_state: "complete", message: "Selected-profile startup status collected.", details: {
        "installed" => true,
        "unit_path" => unit_path,
        "unit_sha256" => Digest::SHA256.file(unit_path).hexdigest,
        "selector_unit_state" => selector,
        "selector_enabled" => selector == "enabled",
        "legacy_unit_state" => legacy,
        "legacy_enabled" => legacy == "enabled",
        "reboot_required" => false
      })
    end

    def uninstall(confirmation: nil)
      return awaiting("Exact selected-profile startup removal confirmation is required.", { "confirmation_phrase" => CONFIRM_UNINSTALL, "unit_path" => unit_path }) unless confirmation == CONFIRM_UNINSTALL
      return failed("selected startup unit path is not a regular managed file") if (File.exist?(unit_path) || File.symlink?(unit_path)) && !safe_managed_unit?

      disabled = run_systemctl("disable", UNIT_NAME)
      return failed("selected startup disable failed", "command_exit_status" => disabled.exit_status) unless disabled.success?
      legacy = run_systemctl("enable", LEGACY_UNIT)
      return failed("legacy NVIDIA startup restore failed", "command_exit_status" => legacy.exit_status) unless legacy.success?

      File.unlink(unit_path) if File.exist?(unit_path)
      reload = run_systemctl("daemon-reload")
      return failed("systemd user-manager reload failed after removal") unless reload.success?

      Result.new(ok: true, lifecycle_state: "complete", message: "Selected-profile startup removed; legacy NVIDIA startup restored without changing the active runtime.", details: {
        "removed" => unit_path, "active_runtime_restarted" => false, "reboot_required" => false
      })
    rescue SystemCallError, IOError => error
      failed("selected-profile startup removal failed safely: #{error.class}")
    end

    private

    def validate_inputs
      errors = []
      errors << "project root must be a real non-symlink directory" unless safe_directory?(@root)
      errors << "Ruby executable must be a regular non-symlink executable" unless safe_executable?(@ruby_path)
      errors << "selected-profile startup script must be a regular non-symlink file inside the project root" unless safe_script?
      errors << "systemctl is unavailable" unless safe_executable?(@systemctl_path)
      errors << "systemd-analyze is unavailable" unless safe_executable?(@systemd_analyze_path)
      errors.empty? ? nil : failed(errors.first, "errors" => errors)
    end

    def safe_directory?(path)
      stat = File.lstat(path)
      stat.directory? && !stat.symlink? && File.realpath(path) == path
    rescue Errno::ENOENT, Errno::EACCES
      false
    end

    def safe_executable?(path)
      return false if path.to_s.empty?
      stat = File.lstat(path)
      stat.file? && !stat.symlink? && File.executable?(path)
    rescue Errno::ENOENT, Errno::EACCES
      false
    end

    def safe_script?
      prefix = @root.end_with?(File::SEPARATOR) ? @root : "#{@root}#{File::SEPARATOR}"
      return false unless @script_path.start_with?(prefix)
      stat = File.lstat(@script_path)
      stat.file? && !stat.symlink? && File.realpath(@script_path) == @script_path
    rescue Errno::ENOENT, Errno::EACCES
      false
    end

    def render_unit
      runtime_path = File.join(@root, "Soul/runtime/model_runtime")
      <<~UNIT
        #{MARKER}
        [Unit]
        Description=Start Soul's human-selected model runtime
        After=network.target

        [Service]
        Type=oneshot
        ExecStart=#{unit_quote(@ruby_path)} #{unit_quote(@script_path)} --root #{unit_quote(@root)}
        UMask=0077
        NoNewPrivileges=true
        PrivateTmp=true
        ProtectSystem=strict
        ProtectHome=read-only
        ReadWritePaths=-#{unit_quote(runtime_path)}
        ProtectControlGroups=true
        ProtectKernelModules=true
        ProtectKernelTunables=true
        RestrictSUIDSGID=true
        LockPersonality=true
        RestrictAddressFamilies=AF_UNIX

        [Install]
        WantedBy=default.target
      UNIT
    end

    def validate_rendered_unit(content)
      Tempfile.create([UNIT_NAME.delete_suffix(".service"), ".service"]) do |file|
        file.chmod(0o600)
        file.write(content)
        file.flush
        result = @runner.run(@systemd_analyze_path, "--user", "verify", file.path, timeout_seconds: COMMAND_TIMEOUT_SECONDS, max_output_bytes: MAX_OUTPUT_BYTES)
        return failed("systemd rejected the selected startup unit", "stderr" => bounded(result.stderr)) unless result.success?
      end
      Result.new(ok: true, lifecycle_state: "complete", message: "Rendered selected startup unit is valid.", details: {})
    end

    def existing_unit(rendered)
      return :missing unless File.exist?(unit_path) || File.symlink?(unit_path)
      return failed("refusing symlink or non-regular selected startup unit destination") unless safe_managed_unit?
      return :matching if File.binread(unit_path, 128 * 1024) == rendered

      failed("existing selected startup unit differs from the reviewed deployment")
    end

    def safe_managed_unit?
      stat = File.lstat(unit_path)
      stat.file? && !stat.symlink? && File.binread(unit_path, 128 * 1024).start_with?(MARKER)
    rescue Errno::ENOENT, Errno::EACCES
      false
    end

    def write_unit(content)
      directory = File.dirname(unit_path)
      FileUtils.mkdir_p(directory, mode: 0o700)
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

    def ensure_runtime_directory
      relative = runtime_path.delete_prefix("#{@root}#{File::SEPARATOR}")
      raise IOError, "runtime directory must remain below project root" if relative == runtime_path

      cursor = @root
      relative.split(File::SEPARATOR).each do |component|
        cursor = File.join(cursor, component)
        if File.exist?(cursor) || File.symlink?(cursor)
          stat = File.lstat(cursor)
          raise IOError, "runtime directory must not contain symlinks" if stat.symlink?
          raise IOError, "runtime path component must be a directory" unless stat.directory?
        else
          Dir.mkdir(cursor, 0o700)
        end
      end
      File.chmod(0o700, runtime_path)
    end

    def enabled_state(unit)
      result = run_systemctl("is-enabled", unit)
      value = result.stdout.to_s.strip
      return "enabled" if %w[enabled enabled-runtime linked linked-runtime alias].include?(value)
      return "disabled" if %w[disabled static indirect generated transient].include?(value)

      "unknown"
    end

    def rollback_failure(message, wrote, selector_before, legacy_before, command)
      restore_enabled_state(UNIT_NAME, selector_before)
      restore_enabled_state(LEGACY_UNIT, legacy_before)
      File.unlink(unit_path) if wrote && safe_managed_unit?
      run_systemctl("daemon-reload")
      failed(message, "command_exit_status" => command&.exit_status, "rollback_attempted" => true)
    end

    def restore_enabled_state(unit, state)
      run_systemctl(state == "enabled" ? "enable" : "disable", unit) if %w[enabled disabled].include?(state)
    end

    def run_systemctl(*arguments)
      @runner.run(@systemctl_path, "--user", *arguments, timeout_seconds: COMMAND_TIMEOUT_SECONDS, max_output_bytes: MAX_OUTPUT_BYTES)
    end

    def unit_path
      File.join(@home, ".config/systemd/user", UNIT_NAME)
    end

    def runtime_path
      File.join(@root, "Soul/runtime/model_runtime")
    end

    def unit_quote(value)
      text = value.to_s
      raise ArgumentError, "unit argument contains a control character" if text.match?(/[\x00-\x1f\x7f]/)

      %Q("#{text.gsub('\\', '\\\\').gsub('"', '\\"')}")
    end

    def awaiting(message, details)
      Result.new(ok: false, lifecycle_state: "awaiting_input", message: message, details: details)
    end

    def failed(message, details = {})
      Result.new(ok: false, lifecycle_state: "failed", message: message, details: details)
    end

    def bounded(value)
      value.to_s.byteslice(0, MAX_OUTPUT_BYTES)
    end
  end
end
