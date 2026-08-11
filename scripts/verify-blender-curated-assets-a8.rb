#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/blender_curated_asset_registry"

ROOT = File.expand_path("..", __dir__)
REGISTRY = File.join(ROOT, "config/blender_curated_assets.json")
failures = []
check = lambda do |name, condition|
  puts "#{condition ? 'PASS' : 'FAIL'} #{name}"
  failures << name unless condition
end

parsed = JSON.parse(File.read(REGISTRY))
files = parsed.fetch("assets").flat_map { |asset| asset.fetch("files") }
check.call("registry pins exactly the reviewed 1K tree and boulder", parsed.fetch("assets").map { |asset| asset.fetch("id") }.sort == %w[boulder_01 island_tree_01] && parsed.fetch("assets").all? { |asset| asset.fetch("resolution") == "1k" })
check.call("registry pins every API-manifest file with SHA-256 and bytes", files.length == 15 && files.all? { |file| file.fetch("bytes").positive? && file.fetch("sha256").match?(/\A[a-f0-9]{64}\z/) })
check.call("registry restricts source downloads to HTTPS Poly Haven delivery", files.all? { |file| file.fetch("url").start_with?("https://dl.polyhaven.org/") })
registry_source = File.binread(File.join(ROOT, "lib", "soul_core", "blender_curated_asset_registry.rb"))
check.call("downloads are byte-bounded and published atomically", registry_source.include?('asset download exceeded pinned byte count') && registry_source.include?('File.rename(staged, destination)') && registry_source.include?('File::EXCL'))

Dir.mktmpdir("soul-a8-registry-test-") do |root|
  registry = SoulCore::BlenderCuratedAssetRegistry.new(registry_path: REGISTRY, root: root)
  preview = registry.preview
  check.call("preview is digest-bound and foreground", preview.fetch("confirmation_phrase") == SoulCore::BlenderCuratedAssetRegistry::CONFIRMATION && preview.fetch("expected_digest").match?(/\A[a-f0-9]{64}\z/) && preview.fetch("background_execution") == false)
  denied = registry.install(expected_digest: preview.fetch("expected_digest"), confirmation: "WRONG")
  check.call("wrong confirmation writes nothing", denied.fetch("lifecycle_state") == "failed" && !File.exist?(File.join(root, "Soul")))
  check.call("missing assets fail closed", registry.verify.fetch("ok") == false)
  asset_root = File.join(root, SoulCore::BlenderCuratedAssetRegistry::INSTALL_RELATIVE_ROOT)
  FileUtils.mkdir_p(asset_root)
  File.symlink("/tmp", File.join(asset_root, "escaped"))
  check.call("symlinked asset root content fails closed", registry.verify.fetch("ok") == false && registry.verify.fetch("error").include?("symlink"))
  File.unlink(File.join(asset_root, "escaped"))
  File.binwrite(File.join(asset_root, "unreviewed.bin"), "not an approved asset")
  check.call("extra local asset files fail closed", registry.verify.fetch("ok") == false && registry.verify.fetch("error").include?("unexpected curated asset files"))
end

exit(failures.empty? ? 0 : 1)
