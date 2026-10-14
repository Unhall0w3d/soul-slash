#!/usr/bin/env ruby
# frozen_string_literal: true

# One-shot, operator-invoked activation. No privileged service or sudo rule.
require "yaml"
require "json"
require "securerandom"
require "digest"
require "etc"
require "fileutils"
require "tmpdir"
require "open3"

module ContinuityLibreChatA24
  ROOT = "/home/bhones/Projects/soul"
  CONFIG = "/etc/librechat/librechat.yaml"
  ENVIRONMENT = "/etc/librechat/librechat.env"
  KEY = "/home/bhones/.config/soul/continuity-a24.key"
  STAGED = File.join(ROOT, "docs/examples/continuity-lab-librechat-a22.yaml")
  BACKUP_PARENT = "/var/backups"
  SECRET_NAME = "SOUL_CONTINUITY_API_KEY"

  def self.merge(original, staged)
    raise ArgumentError unless original.is_a?(Hash) && staged.is_a?(Hash)
    result = Marshal.load(Marshal.dump(original))
    [["endpoints", "custom"], ["modelSpecs", "list"]].each do |parent, field|
      result[parent] ||= {}
      raise ArgumentError unless result[parent].is_a?(Hash)
      result[parent][field] ||= []
      list = result[parent][field]
      raise ArgumentError unless list.is_a?(Array) && list.all? { |row| row.is_a?(Hash) }
      staged.fetch(parent).fetch(field).each do |row|
        existing = list.select { |entry| entry["name"] == row.fetch("name") }
        raise ArgumentError if existing.length > 1 || (existing.one? && existing.first != row)
        list << row if existing.empty?
      end
    end
    result
  end

  def self.environment(original, token)
    raise ArgumentError unless token.match?(/\A[0-9a-f]{64}\z/)
    lines = original.lines.grep(/\A\s*(?:export\s+)?#{SECRET_NAME}\s*=/)
    raise ArgumentError if lines.length > 1
    return original if lines == ["#{SECRET_NAME}=#{token}\n"]
    raise ArgumentError unless lines.empty?
    original + (original.end_with?("\n") ? "" : "\n") + "#{SECRET_NAME}=#{token}\n"
  end

  def self.regular(path, uid:)
    stat = File.lstat(path)
    raise ArgumentError unless File.realpath(path) == path && stat.file? &&
      !stat.symlink? && stat.nlink == 1 && stat.uid == uid && stat.size <= 262_144
    stat
  end

  def self.safe_directory!(path, uid:)
    stat = File.lstat(path)
    raise ArgumentError unless stat.directory? && !stat.symlink? &&
      File.realpath(path) == path && stat.uid == uid && (stat.mode & 0o022).zero?
    stat
  end

  def self.backup_parent(path = BACKUP_PARENT, uid: 0)
    # Arch need not ship /var/backups. Create only the exact child of an already
    # trusted parent; never follow links, recursively create ancestors or chmod
    # an unsafe pre-existing directory into apparent compliance.
    safe_directory!(File.dirname(path), uid: uid)
    begin
      Dir.mkdir(path, 0o700)
    rescue Errno::EEXIST
      # Existing paths must satisfy the same ownership/link/mode checks.
    end
    safe_directory!(path, uid: uid)
    path
  end

  def self.schema_command
    validator = <<~JS
      const {createRequire}=require('node:module');
      const req=createRequire('/usr/lib/librechat/package.json');
      const fs=require('node:fs');
      try { const result=req('librechat-data-provider').configSchema.strict().safeParse(JSON.parse(fs.readFileSync(0,'utf8'))); process.exit(result.success?0:2); }
      catch { process.exit(3); }
    JS
    # The installed application is service-owned. Never load its JavaScript
    # with the helper's root identity; runuser also resets supplementary groups.
    ["/usr/bin/runuser", "-u", "librechat", "--", "/usr/bin/node", "-e", validator]
  end

  def self.replace(path, bytes, stat)
    stage = "#{path}.a24-#{SecureRandom.hex(8)}"
    File.open(stage, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
      file.write(bytes)
      file.flush
      file.fsync
      file.chown(stat.uid, stat.gid)
      file.chmod(stat.mode & 0o777)
    end
    File.rename(stage, path)
    File.open(File.dirname(path), File::RDONLY) { |directory| directory.fsync }
  end

  def self.verify_bytes!(path, expected, stat)
    actual_stat = regular(path, uid: stat.uid)
    # binread returns ASCII-8BIT. Compare bytes, not Ruby's encoding-sensitive
    # text equality, so valid UTF-8 labels do not trigger a false rollback.
    raise RuntimeError unless File.binread(path) == expected.b &&
      actual_stat.gid == stat.gid && (actual_stat.mode & 0o777) == (stat.mode & 0o777)
    true
  end

  def self.restart
    system("/usr/bin/timeout", "30", "/usr/bin/systemctl", "restart", "librechat.service",
      out: File::NULL, err: File::NULL) || raise(RuntimeError)
    system("/usr/bin/systemctl", "is-active", "--quiet", "librechat.service") || raise(RuntimeError)
  end

  def self.run
    stage = "validate_invocation"
    raise ArgumentError unless ARGV == ["--apply"] && Process.uid.zero?
    File.umask(0o077)
    operator = Etc.getpwnam("bhones")
    stage = "read_configuration"
    config_stat, env_stat = [CONFIG, ENVIRONMENT].map { |path| regular(path, uid: 0) }
    originals = [CONFIG, ENVIRONMENT].to_h { |path| [path, File.binread(path)] }
    staged = YAML.safe_load(File.read(STAGED), aliases: false)
    config = merge(YAML.safe_load(originals.fetch(CONFIG), aliases: false), staged)
    # Only serialized configuration, never environment values, enters this validator.
    stage = "validate_schema_as_librechat"
    _, _, status = Open3.capture3({ "PATH" => "/usr/bin:/bin", "LANG" => "C.UTF-8" },
      "/usr/bin/timeout", "--kill-after=5", "20", *schema_command,
      stdin_data: JSON.generate(config), unsetenv_others: true, chdir: "/")
    raise RuntimeError unless status.success?
    stage = "validate_token_parent"
    parent = File.dirname(KEY)
    raise ArgumentError unless File.realpath(parent) == parent && File.stat(parent).uid == operator.uid &&
      File.stat(parent).directory? && (File.stat(parent).mode & 0o777) == 0o700
    if File.exist?(KEY) || File.symlink?(KEY)
      key_stat = regular(KEY, uid: operator.uid)
      raise ArgumentError unless (key_stat.mode & 0o777) == 0o600
      token = File.read(KEY).delete_suffix("\n")
    else
      token = SecureRandom.hex(32)
    end
    env = environment(originals.fetch(ENVIRONMENT), token)
    serialized = YAML.dump(config)
    if YAML.safe_load(originals.fetch(CONFIG), aliases: false) == config && env == originals.fetch(ENVIRONMENT)
      puts JSON.generate(state: "already_configured", secrets_printed: false)
      return 0
    end
    stage = "prepare_backup_parent"
    backup = Dir.mktmpdir("soul-continuity-a24-", backup_parent)
    stage = "write_backups"
    originals.each do |path, bytes|
      File.open(File.join(backup, File.basename(path)), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(bytes); file.flush; file.fsync }
    end
    stage = "enroll_private_token"
    unless File.exist?(KEY)
      File.open(KEY, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
        file.puts(token)
        file.chown(operator.uid, operator.gid)
        file.flush
        file.fsync
      end
    end
    # Refuse drift between validation/backup and replacement.
    stage = "verify_unchanged_inputs"
    originals.each { |path, bytes| raise RuntimeError unless File.binread(path) == bytes }
    mutated = true
    stage = "replace_configuration"
    replace(CONFIG, serialized, config_stat)
    replace(ENVIRONMENT, env, env_stat)
    stage = "verify_configuration_bytes"
    verify_bytes!(CONFIG, serialized, config_stat)
    stage = "verify_environment_bytes"
    verify_bytes!(ENVIRONMENT, env, env_stat)
    stage = "restart_librechat"
    restart
    stage = "write_receipt"
    receipt = { state: "complete", backup: backup, unit: "librechat.service", key_file: KEY,
      endpoints_preserved: true, secrets_printed: false,
      before_sha256: originals.transform_values { |bytes| Digest::SHA256.hexdigest(bytes) },
      after_sha256: [CONFIG, ENVIRONMENT].to_h { |path| [path, Digest::SHA256.file(path).hexdigest] } }
    File.write(File.join(backup, "receipt.json"), JSON.pretty_generate(receipt) + "\n", mode: "wx", perm: 0o600)
    puts JSON.generate(receipt.reject { |key, _| %i[before_sha256 after_sha256].include?(key) })
    0
  rescue StandardError, SignalException => error
    restored = false
    if mutated && originals
      begin
        replace(CONFIG, originals.fetch(CONFIG), config_stat)
        replace(ENVIRONMENT, originals.fetch(ENVIRONMENT), env_stat)
        verify_bytes!(CONFIG, originals.fetch(CONFIG), config_stat)
        verify_bytes!(ENVIRONMENT, originals.fetch(ENVIRONMENT), env_stat)
        restart
        restored = true
      rescue StandardError
        restored = false
      end
    end
    # Parser/subprocess messages can contain private configuration; never emit them.
    warn JSON.generate(state: "failed", stage: stage, error_class: error.class.name, backup: backup,
      mutation_started: !!mutated, restored: restored, secrets_printed: false)
    1
  end
end

if $PROGRAM_NAME == __FILE__
  Signal.trap("TERM") { raise Interrupt, "termination requested" }
  exit ContinuityLibreChatA24.run
end
