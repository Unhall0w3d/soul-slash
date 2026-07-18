# frozen_string_literal: true

require "digest"
require "fileutils"
require "tempfile"
require_relative "bounded_command_runner"

module SoulCore
  class OllamaModelRuntimeDeployment
    UNIT_NAME = "soul-model-gemma.service"
    MARKER = "# Managed by Soul Ollama Model Runtime Deployment"
    CONFIRM_INSTALL = "INSTALL_INACTIVE_GEMMA_OLLAMA_UNIT"
    CONFIRM_UNINSTALL = "REMOVE_INACTIVE_GEMMA_OLLAMA_UNIT"
    SHA256 = /\A[a-f0-9]{64}\z/
    MODEL = /\A[A-Za-z0-9][A-Za-z0-9_.:\/-]{0,119}\z/
    COMMAND_TIMEOUT_SECONDS = 12
    MAX_OUTPUT_BYTES = 16 * 1024

    Result = Struct.new(:ok, :lifecycle_state, :message, :details, keyword_init: true) do
      def to_h = { "ok" => ok, "lifecycle_state" => lifecycle_state, "message" => message, "details" => details }
    end

    def initialize(home: Dir.home, ollama_path: nil, systemctl_path: nil, systemd_analyze_path: nil, runner: BoundedCommandRunner.new)
      @home = File.expand_path(home)
      @ollama_path = ollama_path || find_executable("ollama")
      @systemctl_path = systemctl_path || find_executable("systemctl")
      @systemd_analyze_path = systemd_analyze_path || find_executable("systemd-analyze")
      @runner = runner
    end

    def plan(expected_ollama_sha256:, source_model:, api_model:, expected_model_digest:, host: "127.0.0.1", port: 8082, device: "0")
      inputs = validate_inputs(expected_ollama_sha256:, source_model:, api_model:, expected_model_digest:, host:, port:, device:)
      return inputs if inputs.is_a?(Result)

      unit = render_unit(inputs)
      Result.new(ok: true, lifecycle_state: "blocked_for_human_review", message: "Inactive Gemma Ollama unit plan is ready for exact review.", details: {
        "unit_name" => UNIT_NAME, "unit_path" => unit_path, "bind" => "#{inputs.fetch('host')}:#{inputs.fetch('port')}",
        "source_model" => inputs.fetch("source_model"), "api_model" => inputs.fetch("api_model"),
        "expected_model_digest" => inputs.fetch("expected_model_digest"), "ollama_sha256" => inputs.fetch("ollama_sha256"),
        "unit_sha256" => Digest::SHA256.hexdigest(unit), "confirmation_phrase" => CONFIRM_INSTALL,
        "will_start" => false, "will_enable" => false, "will_select" => false,
        "commands" => [["systemctl", "--user", "daemon-reload"]]
      })
    end

    def install(expected_ollama_sha256:, source_model:, api_model:, expected_model_digest:, host: "127.0.0.1", port: 8082, device: "0", confirmation: nil)
      options = { expected_ollama_sha256:, source_model:, api_model:, expected_model_digest:, host:, port:, device: }
      planned = plan(**options)
      return planned unless planned.ok
      return awaiting("Exact inactive-unit installation confirmation is required.", planned.details) unless confirmation == CONFIRM_INSTALL

      inputs = validate_inputs(**options)
      return inputs if inputs.is_a?(Result)
      unit = render_unit(inputs)
      existing = existing_unit(unit)
      return existing if existing.is_a?(Result)
      validation = validate_rendered_unit(unit)
      return validation unless validation.ok

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
        return blocked("Gemma Ollama unit did not remain loaded, inactive, and unenabled.", observed.details)
      end

      Result.new(ok: true, lifecycle_state: "complete", message: "Gemma Ollama unit installed inactive and unenabled.", details: planned.details.merge(observed.details).merge("written" => wrote))
    rescue SystemCallError, IOError => error
      failed("Gemma Ollama unit installation failed safely: #{error.class}")
    end

    def status
      return failed("systemctl is unavailable") unless executable?(@systemctl_path)
      return Result.new(ok: true, lifecycle_state: "complete", message: "Gemma Ollama unit is not installed.", details: { "installed" => false, "unit_path" => unit_path, "load_state" => "not-found", "active_state" => "inactive", "enabled" => false }) unless File.exist?(unit_path) || File.symlink?(unit_path)
      return failed("Gemma Ollama unit path is not a regular managed file") unless safe_managed_unit?

      load_state = property("LoadState")
      active_state = property("ActiveState")
      unit_file_state = property("UnitFileState")
      return failed("Gemma Ollama unit state could not be read") if [load_state, active_state, unit_file_state].any?(&:nil?)

      Result.new(ok: true, lifecycle_state: "complete", message: "Gemma Ollama unit status collected.", details: {
        "installed" => true, "unit_path" => unit_path, "load_state" => load_state, "active_state" => active_state,
        "unit_file_state" => unit_file_state, "enabled" => %w[enabled enabled-runtime linked linked-runtime alias].include?(unit_file_state),
        "unit_sha256" => Digest::SHA256.file(unit_path).hexdigest
      })
    end

    def uninstall(confirmation: nil)
      return awaiting("Exact inactive-unit removal confirmation is required.", "confirmation_phrase" => CONFIRM_UNINSTALL, "unit_path" => unit_path) unless confirmation == CONFIRM_UNINSTALL
      current = status
      return current unless current.ok && current.details.fetch("installed")
      return blocked("Gemma Ollama unit must be explicitly unloaded before removal.", current.details) unless current.details.fetch("active_state") == "inactive"

      File.unlink(unit_path)
      reload = run_systemctl("daemon-reload")
      return failed("systemd user-manager reload failed after removal", "stderr" => bounded(reload.stderr)) unless reload.success?

      Result.new(ok: true, lifecycle_state: "complete", message: "Inactive Gemma Ollama unit removed.", details: { "removed" => unit_path, "service_stopped" => false })
    rescue SystemCallError, IOError => error
      failed("Gemma Ollama unit removal failed safely: #{error.class}")
    end

    private

    def validate_inputs(expected_ollama_sha256:, source_model:, api_model:, expected_model_digest:, host:, port:, device:)
      errors = []
      ollama = safe_executable(@ollama_path)
      digest = expected_ollama_sha256.to_s
      numeric_port = Integer(port.to_s, 10) rescue nil
      errors << "Ollama must be an executable regular non-symlink file." unless ollama
      errors << "Ollama SHA-256 must be lowercase hexadecimal." unless digest.match?(SHA256)
      errors << "Ollama SHA-256 digest mismatch." if ollama && digest.match?(SHA256) && Digest::SHA256.file(ollama).hexdigest != digest
      errors << "Source model tag is invalid." unless source_model.to_s.match?(MODEL)
      errors << "API model alias is invalid." unless api_model.to_s.match?(MODEL)
      errors << "Expected model digest must be lowercase hexadecimal." unless expected_model_digest.to_s.match?(SHA256)
      errors << "Gemma Ollama service must bind exact loopback host 127.0.0.1." unless host.to_s == "127.0.0.1"
      errors << "Gemma Ollama service port must be unprivileged." unless numeric_port&.between?(1024, 65_535)
      errors << "Vulkan device must be one decimal identifier." unless device.to_s.match?(/\A\d\z/)
      errors << "systemctl is unavailable." unless executable?(@systemctl_path)
      errors << "systemd-analyze is unavailable." unless executable?(@systemd_analyze_path)
      return failed(errors.first, "errors" => errors) unless errors.empty?

      { "ollama_path" => ollama, "ollama_sha256" => digest, "source_model" => source_model.to_s,
        "api_model" => api_model.to_s, "expected_model_digest" => expected_model_digest.to_s,
        "host" => host.to_s, "port" => numeric_port, "device" => device.to_s }
    end

    def render_unit(inputs)
      env = {
        "OLLAMA_HOST" => "#{inputs.fetch('host')}:#{inputs.fetch('port')}", "OLLAMA_VULKAN" => "1",
        "GGML_VK_VISIBLE_DEVICES" => inputs.fetch("device"), "OLLAMA_NO_CLOUD" => "1", "OLLAMA_NOHISTORY" => "1",
        "OLLAMA_MAX_LOADED_MODELS" => "1", "OLLAMA_NUM_PARALLEL" => "1", "OLLAMA_CONTEXT_LENGTH" => "16384",
        "OLLAMA_KEEP_ALIVE" => "5m"
      }
      <<~UNIT
        #{MARKER}
        # ollama-sha256=#{inputs.fetch("ollama_sha256")}
        # source-model=#{inputs.fetch("source_model")}
        # api-model=#{inputs.fetch("api_model")}
        # expected-model-digest=#{inputs.fetch("expected_model_digest")}
        [Unit]
        Description=Soul Gemma AMD Vulkan Ollama runtime
        After=network.target
        StartLimitIntervalSec=60
        StartLimitBurst=3

        [Service]
        Type=simple
        #{env.map { |key, value| "Environment=#{key}=#{value}" }.join("\n")}
        ExecStart=#{unit_quote(inputs.fetch("ollama_path"))} serve
        Restart=on-failure
        RestartSec=3
        TimeoutStopSec=30
        UMask=0077
        NoNewPrivileges=true
        PrivateTmp=true
        ProtectSystem=strict
        ProtectHome=read-only
        ReadWritePaths=%h/.ollama
        ProtectControlGroups=true
        ProtectKernelModules=true
        ProtectKernelTunables=true
        RestrictSUIDSGID=true
        LockPersonality=true
        RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
      UNIT
    end

    def validate_rendered_unit(content)
      Tempfile.create(["soul-model-gemma", ".service"]) do |file|
        file.write(content); file.flush
        result = @runner.run(@systemd_analyze_path, "--user", "verify", file.path, timeout_seconds: COMMAND_TIMEOUT_SECONDS, max_output_bytes: MAX_OUTPUT_BYTES)
        return failed("systemd rejected the rendered Gemma Ollama unit", "stderr" => bounded(result.stderr)) unless result.success?
      end
      Result.new(ok: true, lifecycle_state: "complete", message: "Rendered unit is valid.", details: {})
    end

    def existing_unit(rendered)
      return :missing unless File.exist?(unit_path) || File.symlink?(unit_path)
      return failed("refusing symlink or non-regular Gemma Ollama unit destination") unless safe_managed_unit?
      return :matching if File.binread(unit_path, 128 * 1024) == rendered

      failed("existing Gemma Ollama unit differs from the reviewed deployment")
    end

    def write_unit(content)
      directory = File.dirname(unit_path)
      FileUtils.mkdir_p(directory, mode: 0o700)
      raise IOError, "refusing symlink unit destination" if File.symlink?(unit_path)
      temporary = "#{unit_path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(content); file.flush; file.fsync }
      File.rename(temporary, unit_path)
      File.chmod(0o600, unit_path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary)
    end

    def safe_managed_unit?
      stat = File.lstat(unit_path)
      stat.file? && !stat.symlink? && File.binread(unit_path, 128 * 1024).start_with?(MARKER)
    rescue Errno::ENOENT, Errno::EACCES
      false
    end

    def safe_executable(path)
      stat = File.lstat(path.to_s)
      stat.file? && !stat.symlink? && File.executable?(path) ? File.expand_path(path) : nil
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end

    def executable?(path) = !path.to_s.empty? && File.file?(path) && File.executable?(path)
    def unit_path = File.join(@home, ".config/systemd/user", UNIT_NAME)
    def property(name)
      result = @runner.run(@systemctl_path, "--user", "show", UNIT_NAME, "--property=#{name}", "--value", "--no-pager", timeout_seconds: COMMAND_TIMEOUT_SECONDS, max_output_bytes: MAX_OUTPUT_BYTES)
      result.success? ? result.stdout.to_s.strip : nil
    end
    def run_systemctl(*args) = @runner.run(@systemctl_path, "--user", *args, timeout_seconds: COMMAND_TIMEOUT_SECONDS, max_output_bytes: MAX_OUTPUT_BYTES)
    def unit_quote(value) = %Q("#{value.to_s.gsub('\\', '\\\\').gsub('"', '\\"')}")
    def bounded(value) = value.to_s.byteslice(0, MAX_OUTPUT_BYTES)
    def find_executable(name) = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }.find { |path| File.file?(path) && File.executable?(path) }
    def awaiting(message, details) = Result.new(ok: false, lifecycle_state: "awaiting_input", message:, details:)
    def blocked(message, details = {}) = Result.new(ok: false, lifecycle_state: "blocked_for_human_review", message:, details:)
    def failed(message, details = {}) = Result.new(ok: false, lifecycle_state: "failed", message:, details:)
  end
end
