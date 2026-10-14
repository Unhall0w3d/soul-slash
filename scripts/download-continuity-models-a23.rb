#!/usr/bin/env ruby
# frozen_string_literal: true
require "json"
require "digest"

abort "Use --approved-download" unless ARGV == ["--approved-download"]
File.umask(0o077)
root = "/home/bhones/ai_models"
abort "Noncanonical model parent" unless File.realpath(root) == root
target = File.join(root, "continuity-a23")
Dir.mkdir(target, 0o700) unless File.exist?(target)
abort "Unsafe target" unless File.realpath(target) == target && File.stat(target).uid == Process.uid
assets = JSON.parse(File.read(File.join(__dir__, "support/continuity_model_assets_a23.json")))
$stdout.sync = true
assets.each do |name, asset|
  abort "Invalid asset filename" unless asset.fetch("file").match?(/\A[A-Za-z0-9_.-]+\.gguf\z/) && !asset.fetch("file").include?("..")
  abort "Invalid asset source" unless asset.fetch("repo").match?(/\A(?:unsloth|mistralai)\/[A-Za-z0-9_.-]+\z/) && asset.fetch("revision").match?(/\A[0-9a-f]{40}\z/) && asset.fetch("sha256").match?(/\A[0-9a-f]{64}\z/)
  path = File.join(target, asset.fetch("file"))
  verify = ->(p) { File.size(p) == asset.fetch("size") && Digest::SHA256.file(p).hexdigest == asset.fetch("sha256") }
  if File.exist?(path) || File.symlink?(path)
    abort "Unsafe existing file" unless File.lstat(path).file? && !File.symlink?(path) && File.stat(path).nlink == 1
    abort "Existing asset mismatch" unless verify.call(path)
    puts "VERIFIED existing #{name}"
    next
  end
  part = path + ".part"
  if File.exist?(part) || File.symlink?(part)
    stat = File.lstat(part)
    abort "Unsafe partial" unless stat.file? && !stat.symlink? && stat.nlink == 1 && stat.uid == Process.uid && stat.size <= asset.fetch("size")
  end
  url = "https://huggingface.co/#{asset.fetch('repo')}/resolve/#{asset.fetch('revision')}/#{asset.fetch('file')}"
  puts "DOWNLOAD #{name} #{asset.fetch('size')} bytes"
  ok = system("curl", "--fail", "--location", "--silent", "--show-error", "--proto", "=https", "--proto-redir", "=https",
    "--connect-timeout", "30", "--max-time", "1800", "--retry", "2", "--retry-max-time", "1800",
    "--continue-at", "-", "--output", part, url)
  abort "Download failed; partial retained: #{name}" unless ok
  abort "Downloaded digest/size mismatch: #{name}" unless verify.call(part)
  File.rename(part, path)
  puts "VERIFIED #{name} #{asset.fetch('sha256')}"
end
