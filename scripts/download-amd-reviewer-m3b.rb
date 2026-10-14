#!/usr/bin/env ruby
# frozen_string_literal: true
require "json"
require "digest"

abort "Use --approved-download" unless ARGV == ["--approved-download"]
File.umask(0o077)
root = "/home/bhones/ai_models"
abort "Unsafe model parent" unless File.realpath(root) == root && File.stat(root).uid == Process.uid
target = File.join(root, "amd-reviewer-m3b")
Dir.mkdir(target, 0o700) unless File.exist?(target)
abort "Unsafe target" unless File.realpath(target) == target && File.stat(target).uid == Process.uid
lock = File.open(File.join(target, ".download.lock"), File::RDWR | File::CREAT | File::NOFOLLOW, 0o600)
abort "Unsafe download lock" unless lock.stat.file? && lock.stat.nlink == 1 && lock.stat.uid == Process.uid
abort "Another download owns this directory" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
assets = JSON.parse(File.read(File.join(__dir__, "support/amd_reviewer_assets_m3b.json")))
abort "Unexpected catalog" unless assets.keys.sort == %w[phi4 qwen35]
$stdout.sync = true
assets.each do |name, asset|
  abort "Invalid source" unless %w[bartowski/Qwen_Qwen3.5-9B-GGUF microsoft/phi-4-gguf].include?(asset.fetch("repo")) &&
    asset.fetch("revision").match?(/\A[0-9a-f]{40}\z/) && asset.fetch("sha256").match?(/\A[0-9a-f]{64}\z/)
  abort "Invalid filename/size" unless asset.fetch("file").match?(/\A[A-Za-z0-9_.-]+\.gguf\z/) &&
    !asset["file"].include?("..") && asset.fetch("size").between?(1, 10 * 1024**3)
  path = File.join(target, asset.fetch("file"))
  verify = ->(p) { File.size(p) == asset.fetch("size") && Digest::SHA256.file(p).hexdigest == asset.fetch("sha256") }
  safe = lambda do |p|
    s = File.lstat(p)
    abort "Unsafe existing file" unless s.file? && !s.symlink? && s.nlink == 1 && s.uid == Process.uid
  end
  if File.exist?(path) || File.symlink?(path)
    safe.call(path)
    abort "Existing asset mismatch" unless verify.call(path)
    puts "VERIFIED existing #{name}"
    next
  end
  part = path + ".part"
  if File.exist?(part) || File.symlink?(part)
    safe.call(part)
    abort "Oversized partial" if File.size(part) > asset.fetch("size")
  else
    File.open(part, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) {}
  end
  url = "https://huggingface.co/#{asset.fetch('repo')}/resolve/#{asset.fetch('revision')}/#{asset.fetch('file')}"
  puts "DOWNLOAD #{name} #{asset.fetch('size')} bytes"
  ok = system("curl", "--fail", "--location", "--silent", "--show-error", "--proto", "=https", "--proto-redir", "=https",
    "--connect-timeout", "30", "--max-time", "1800", "--max-filesize", asset.fetch("size").to_s,
    "--continue-at", "-", "--output", part, url)
  abort "Download failed; partial retained: #{name}" unless ok
  abort "Downloaded digest/size mismatch: #{name}" unless verify.call(part)
  # link is exclusive: never replace a final file created during the download.
  # Removing our partial name leaves the verified bytes at the final name.
  File.link(part, path)
  File.unlink(part)
  puts "VERIFIED #{name} #{asset.fetch('sha256')}"
end
