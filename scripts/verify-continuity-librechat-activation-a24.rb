#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "activate-continuity-librechat-a24"
require "stringio"
require "tmpdir"

checks = 0
check = lambda { |value| raise "fixture failed" unless value; checks += 1 }
staged = YAML.safe_load(File.read(ContinuityLibreChatA24::STAGED), aliases: false)
old = { "version" => "1.3.1", "cache" => true, "registration" => { "socialLogins" => ["openid"] },
  "endpoints" => { "custom" => [{ "name" => "retained", "apiKey" => "synthetic-not-secret" }] },
  "modelSpecs" => { "list" => [{ "name" => "retained-model" }] } }
copy = Marshal.load(Marshal.dump(old))
merged = ContinuityLibreChatA24.merge(old, staged)
check.call(old == copy)
check.call(merged["registration"] == old["registration"] && merged["cache"] == true)
check.call(merged["endpoints"]["custom"].first == old["endpoints"]["custom"].first)
check.call(merged["modelSpecs"]["list"].first == old["modelSpecs"]["list"].first)
check.call(ContinuityLibreChatA24.merge(merged, staged) == merged)
collision = Marshal.load(Marshal.dump(merged))
collision["endpoints"]["custom"].last["baseURL"] = "http://different.invalid"
begin
  ContinuityLibreChatA24.merge(collision, staged)
  raise "collision accepted"
rescue ArgumentError
  checks += 1
end
token = "a" * 64
base = "# retained\nOTHER=synthetic\n"
env = ContinuityLibreChatA24.environment(base, token)
check.call(env.start_with?(base))
check.call(ContinuityLibreChatA24.environment(env, token) == env)
begin
  ContinuityLibreChatA24.environment(env, "b" * 64)
  raise "existing credential overwritten"
rescue ArgumentError
  checks += 1
end
begin
  ContinuityLibreChatA24.environment(base, "bad\nOTHER=bad")
  raise "invalid token accepted"
rescue ArgumentError
  checks += 1
end

refused_backup_parent = lambda do |path, uid: Process.uid|
  ContinuityLibreChatA24.backup_parent(path, uid: uid)
  false
rescue ArgumentError, SystemCallError
  true
end
Dir.mktmpdir("soul-a24-backup-parent-") do |fixture|
  missing = File.join(fixture, "backups")
  ContinuityLibreChatA24.backup_parent(missing, uid: Process.uid)
  stat = File.lstat(missing)
  check.call(stat.directory? && !stat.symlink? && stat.uid == Process.uid &&
    (stat.mode & 0o777) == 0o700 && File.realpath(missing) == missing)

  File.chmod(0o750, missing)
  ContinuityLibreChatA24.backup_parent(missing, uid: Process.uid)
  check.call((File.lstat(missing).mode & 0o777) == 0o750)
  File.chmod(0o770, missing)
  check.call(refused_backup_parent.call(missing))

  regular_file = File.join(fixture, "regular-file")
  File.write(regular_file, "fixture")
  check.call(refused_backup_parent.call(regular_file))
  linked = File.join(fixture, "linked")
  File.symlink(missing, linked)
  check.call(refused_backup_parent.call(linked))
  check.call(refused_backup_parent.call(File.join(fixture, "wrong-owner"), uid: Process.uid + 1) &&
    !File.exist?(File.join(fixture, "wrong-owner")))
  existing_wrong_owner = File.join(fixture, "existing-wrong-owner")
  Dir.mkdir(existing_wrong_owner, 0o700)
  check.call(refused_backup_parent.call(existing_wrong_owner, uid: Process.uid + 1) &&
    File.directory?(existing_wrong_owner))

  File.chmod(0o777, fixture)
  unsafe = File.join(fixture, "unsafe")
  check.call(refused_backup_parent.call(unsafe) && !File.exist?(unsafe))
  File.chmod(0o700, fixture)
  nested = File.join(fixture, "absent", "backups")
  check.call(refused_backup_parent.call(nested) && !File.exist?(File.join(fixture, "absent")))
  Dir.mkdir(File.join(fixture, "subdir"), 0o700)
  noncanonical = File.join(fixture, "subdir", "..", "noncanonical")
  check.call(refused_backup_parent.call(noncanonical) && !File.exist?(File.join(fixture, "noncanonical")))
  parent_link = File.join(fixture, "parent-link")
  File.symlink(fixture, parent_link)
  via_link = File.join(parent_link, "via-link")
  check.call(refused_backup_parent.call(via_link) && !File.exist?(File.join(fixture, "via-link")))
end

schema_argv = ContinuityLibreChatA24.schema_command
check.call(schema_argv.is_a?(Array) && schema_argv.length == 7 &&
  schema_argv.take(6) == ["/usr/bin/runuser", "-u", "librechat", "--", "/usr/bin/node", "-e"] &&
  schema_argv.last.is_a?(String) && schema_argv.last.include?("configSchema") &&
  schema_argv.last.include?("readFileSync(0") &&
  schema_argv.none? { |argument| argument.include?(token) || argument.include?("synthetic-not-secret") ||
    argument.include?(ContinuityLibreChatA24::SECRET_NAME) })

Dir.mktmpdir("soul-a24-byte-readback-") do |fixture|
  path = File.join(fixture, "config.yaml")
  original = "original:\x00\xFF\n".b
  File.binwrite(path, original)
  File.chmod(0o640, path)
  original_stat = File.lstat(path)
  unicode_yaml = "name: Café\n"
  ContinuityLibreChatA24.replace(path, unicode_yaml, original_stat)
  ContinuityLibreChatA24.verify_bytes!(path, unicode_yaml, original_stat)
  check.call(unicode_yaml.encoding == Encoding::UTF_8 && File.binread(path) == unicode_yaml.b &&
    File.binread(path) != unicode_yaml)

  ascii_yaml = "name: Cafe\n"
  ContinuityLibreChatA24.replace(path, ascii_yaml, original_stat)
  ContinuityLibreChatA24.verify_bytes!(path, ascii_yaml, original_stat)
  check.call(File.binread(path) == ascii_yaml.b)

  File.open(path, "r+b") { |file| file.write("N") }
  changed_byte_rejected = begin
    ContinuityLibreChatA24.verify_bytes!(path, ascii_yaml, original_stat)
    false
  rescue RuntimeError
    true
  end
  check.call(changed_byte_rejected && File.binread(path) != ascii_yaml.b)

  ContinuityLibreChatA24.replace(path, ascii_yaml, original_stat)
  File.chmod(0o600, path)
  mode_rejected = begin
    ContinuityLibreChatA24.verify_bytes!(path, ascii_yaml, original_stat)
    false
  rescue RuntimeError
    true
  end
  check.call(mode_rejected)

  File.chmod(0o640, path)
  wrong_gid = Struct.new(:uid, :gid, :mode).new(original_stat.uid, original_stat.gid + 1, original_stat.mode)
  gid_rejected = begin
    ContinuityLibreChatA24.verify_bytes!(path, ascii_yaml, wrong_gid)
    false
  rescue RuntimeError
    true
  end
  check.call(gid_rejected)

  ContinuityLibreChatA24.replace(path, original, original_stat)
  ContinuityLibreChatA24.verify_bytes!(path, original, original_stat)
  restored_stat = File.lstat(path)
  check.call(File.binread(path) == original && restored_stat.uid == original_stat.uid &&
    restored_stat.gid == original_stat.gid && (restored_stat.mode & 0o777) == (original_stat.mode & 0o777))
end

original_argv, original_stderr = ARGV.dup, $stderr
begin
  ARGV.replace(["--invalid-fixture-only"])
  $stderr = StringIO.new
  result = ContinuityLibreChatA24.run
  report = JSON.parse($stderr.string)
  check.call(result == 1 && report["stage"] == "validate_invocation" && report["mutation_started"] == false)
  check.call(report["secrets_printed"] == false && !report.key?("message") && !report.key?("backtrace"))
ensure
  ARGV.replace(original_argv)
  $stderr = original_stderr
end
puts "#{checks} activation checks passed; temporary fixtures only, no host files changed"
