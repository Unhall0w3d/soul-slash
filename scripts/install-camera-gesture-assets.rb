#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "optparse"
require "rubygems/package"
require "tmpdir"
require "zlib"
require_relative "../lib/soul_core/camera_gesture_assets"

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: install-camera-gesture-assets.rb --package ARCHIVE --model MODEL"
  parser.on("--package PATH", "Pinned @mediapipe/tasks-vision 1.0.1 archive") { |v| options[:package] = v }
  parser.on("--model PATH", "Pinned Google gesture_recognizer.task") { |v| options[:model] = v }
end.parse!
abort("both --package and --model are required") unless options.values_at(:package, :model).all? { |p| p && File.file?(p) && !File.symlink?(p) }
abort("package digest mismatch") unless Digest::SHA256.file(options.fetch(:package)).hexdigest == SoulCore::CameraGestureAssets::PACKAGE_SHA256
abort("model digest mismatch") unless Digest::SHA256.file(options.fetch(:model)).hexdigest == SoulCore::CameraGestureAssets::MODEL_SHA256

root = File.expand_path("..", __dir__)
destination = File.join(root, SoulCore::CameraGestureAssets::ROOT_RELATIVE)
if File.exist?(destination)
  verifier = SoulCore::CameraGestureAssets.new(root: root)
  abort("existing gesture installation is incomplete; review it before replacement") unless SoulCore::CameraGestureAssets::ASSETS.keys.all? { |name| verifier.read(name) }
  puts "PASS pinned local gesture assets already installed"
  exit
end
parent = File.dirname(destination)
FileUtils.mkdir_p(parent)
staging = Dir.mktmpdir("gesture-install-", parent)
begin
  expected = SoulCore::CameraGestureAssets::ASSETS
  found = {}
  Zlib::GzipReader.open(options.fetch(:package)) do |gzip|
    Gem::Package::TarReader.new(gzip) do |tar|
      tar.each do |entry|
        relative = entry.full_name.delete_prefix("package/")
        next unless expected.key?(relative) && relative != "gesture_recognizer.task"
        abort("duplicate package entry: #{relative}") if found.key?(relative)
        bytes = entry.read(12 * 1024 * 1024 + 1)
        abort("package asset size or digest mismatch: #{relative}") if bytes.bytesize > 12 * 1024 * 1024 || Digest::SHA256.hexdigest(bytes) != expected.fetch(relative).first
        path = File.join(staging, relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, bytes)
        found[relative] = true
      end
    end
  end
  abort("package assets missing") unless found.length == expected.length - 1
  FileUtils.cp(options.fetch(:model), File.join(staging, "gesture_recognizer.task"))
  Dir.glob(File.join(staging, "**", "*")).each { |path| File.chmod(File.directory?(path) ? 0o700 : 0o600, path) }
  File.rename(staging, destination)
  puts "PASS pinned local gesture assets installed under Soul/runtime/gesture"
ensure
  FileUtils.remove_entry_secure(staging) if File.exist?(staging)
end
