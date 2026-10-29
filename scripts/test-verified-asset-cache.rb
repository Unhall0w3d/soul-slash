# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "digest"
require_relative "../lib/soul_core/verified_asset_cache"
require_relative "../lib/soul_core/application_facade"

class VerifiedAssetCacheTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir
    @path = File.join(@root, "asset")
    @bytes = "test checkpoint\0" * 100
    File.binwrite(@path, @bytes)
    @sha = Digest::SHA256.hexdigest(@bytes)
    @cache = SoulCore::VerifiedAssetCache.new
  end

  def teardown = FileUtils.remove_entry(@root)
  def verify(cache = @cache, sha: @sha, bytes: @bytes.bytesize, **options)
    cache.verified?(@path, bytes: bytes, sha256: sha, **options)
  end

  def test_full_digest_then_identity_bound_reuse_and_cold_restart
    assert verify
    assert verify
    assert_equal 1, @cache.stats["full_hashes"]
    assert_equal 1, @cache.stats["cache_hits"]
    cold = SoulCore::VerifiedAssetCache.new
    assert verify(cold)
    assert_equal 1, cold.stats["full_hashes"]
    assert_equal @bytes.bytesize, cold.stats["bytes_hashed"]
  end

  def test_same_size_write_with_restored_mtime_invalidates_success
    assert verify
    original = File.stat(@path)
    File.binwrite(@path, "x" * @bytes.bytesize)
    File.utime(original.atime, original.mtime, @path)
    refute verify
    assert_equal 2, @cache.stats["full_hashes"]
    assert_equal 0, @cache.stats["cache_hits"]
  end

  def test_new_inode_identical_bytes_requires_new_full_digest
    assert verify
    replacement = @path + ".new"
    File.binwrite(replacement, @bytes)
    File.rename(replacement, @path)
    assert verify
    assert_equal 2, @cache.stats["full_hashes"]
  end

  def test_changed_manifest_digest_size_and_failed_digest_not_trusted
    assert verify
    refute verify(sha: "0" * 64)
    refute verify(bytes: 1)
    assert verify
    assert_equal 3, @cache.stats["full_hashes"]
    refute verify(sha: "invalid")
  end

  def test_mutating_the_original_manifest_string_cannot_rewrite_cached_proof
    expected = @sha.dup
    assert verify(sha: expected)
    expected.replace("0" * 64)
    refute verify(sha: expected)
    assert_equal 2, @cache.stats["full_hashes"]
    assert_equal 0, @cache.stats["cache_hits"]
  end

  def test_hardlinks_symlinks_and_symlink_ancestors_rejected_on_hits
    assert verify
    link = @path + ".link"
    File.link(@path, link)
    refute verify
    File.unlink(link)
    File.symlink(@path, link)
    refute @cache.verified?(link, bytes: @bytes.bytesize, sha256: @sha)
    Dir.mkdir(File.join(@root, "real"))
    File.rename(@path, File.join(@root, "real", "asset"))
    File.symlink(File.join(@root, "real"), File.join(@root, "alias"))
    refute @cache.verified?(File.join(@root, "alias", "asset"), bytes: @bytes.bytesize, sha256: @sha)
  end

  def test_missing_truncated_and_fifo_fail_closed_without_blocking
    refute verify(bytes: @bytes.bytesize + 1)
    File.unlink(@path)
    refute verify
    File.mkfifo(@path)
    refute verify
  end

  def test_mode_change_invalidates_cache_even_when_digest_unchanged
    assert verify
    File.chmod(0600, @path)
    assert verify
    assert_equal 2, @cache.stats["full_hashes"]
  end

  def test_modification_and_identical_path_replacement_during_hash_refused
    %i[write replace].each do |change|
      File.binwrite(@path, @bytes)
      cache = SoulCore::VerifiedAssetCache.new
      path = @path
      cache.define_singleton_method(:digest_file) do |io, cancel|
        result = super(io, cancel)
        if change == :write
          File.binwrite(path, "z" * File.size(path))
        else
          File.binwrite(path + ".new", File.binread(path))
          File.rename(path + ".new", path)
        end
        result
      end
      refute verify(cache)
      assert_equal 0, cache.stats["cache_hits"]
    end
  end

  def test_cancellation_before_hash_and_on_hit_and_during_read
    assert_raises(SoulCore::VerifiedAssetCache::Canceled) { verify(cancel: -> { true }) }
    assert verify
    assert_raises(SoulCore::VerifiedAssetCache::Canceled) { verify(cancel: -> { true }) }
    calls = 0
    cold = SoulCore::VerifiedAssetCache.new
    assert_raises(SoulCore::VerifiedAssetCache::Canceled) { verify(cold, cancel: -> { calls += 1; calls >= 3 }) }
    assert verify(cold)
    assert_equal 0, cold.stats["cache_hits"]
  end

  def test_parallel_callers_coalesce_full_digest
    results = 6.times.map { Thread.new { verify } }.map(&:value)
    assert results.all?
    assert_equal 1, @cache.stats["full_hashes"]
    assert_equal 5, @cache.stats["cache_hits"]
  end

  def test_cache_has_finite_capacity_and_eviction_requires_rehash
    assert verify
    SoulCore::VerifiedAssetCache::MAX_ENTRIES.times do |i|
      path = File.join(@root, "asset-#{i}")
      File.binwrite(path, @bytes)
      assert @cache.verified?(path, bytes: @bytes.bytesize, sha256: @sha)
    end
    assert verify
    assert_equal SoulCore::VerifiedAssetCache::MAX_ENTRIES + 2, @cache.stats["full_hashes"]
  end

  def test_bridge_services_share_only_asset_proofs_not_request_cancellation
    facade = SoulCore::ApplicationFacade.new(root: @root)
    facade.define_singleton_method(:shared_compute) { nil }
    cancel_a = -> { true }; cancel_b = -> { false }
    first = facade.creative_bridge_services(cancel: cancel_a)
    second = facade.creative_bridge_services(cancel: cancel_b)
    cache = first[:visual].instance_variable_get(:@asset_verifier)
    assert_same cache, second[:visual].instance_variable_get(:@asset_verifier)
    assert_same cache, second[:music].instance_variable_get(:@vulkan_backend).instance_variable_get(:@asset_verifier)
    refute_same first[:visual], second[:visual]
    refute_same first[:music], second[:music]
    refute_same first[:handoff], second[:handoff]
    assert_same cancel_a, first[:visual].instance_variable_get(:@verification_cancel)
    assert_same cancel_b, second[:visual].instance_variable_get(:@verification_cancel)
    assert_same cancel_b, second[:music].instance_variable_get(:@vulkan_backend).instance_variable_get(:@verification_cancel)
  end

  def test_music_checks_every_manifest_file_and_source_revision_on_each_reentry
    manifest = JSON.parse(File.read(File.expand_path("../config/music_vulkan_models.json", __dir__)))
    manifest["models"]["files"].each do |item|
      item.merge!("bytes" => @bytes.bytesize, "sha256" => @sha)
    end
    models = File.join(@root, "acestep-cpp", manifest["runtime"]["revision"], "models")
    FileUtils.mkdir_p(models)
    manifest["models"]["files"].each { |item| File.binwrite(File.join(models, item["filename"]), @bytes) }
    calls = 0
    runner = Object.new
    runner.define_singleton_method(:run) do |*args, **options|
      calls += 1
      raise "unexpected command" unless args == %w[git rev-parse HEAD]
      SoulCore::BoundedCommandRunner::Result.new(status: "ok", stdout: manifest["runtime"]["revision"], stderr: "", truncated: false)
    end
    create = -> { SoulCore::MusicVulkanGenerationBackend.new(music_root: @root, manifest: manifest, runner: runner, asset_verifier: @cache) }
    assert create.call.verify_checkpoints!
    count = manifest["models"]["files"].length
    assert_equal count, @cache.stats["full_hashes"]
    assert create.call.verify_checkpoints!
    assert_equal count, @cache.stats["cache_hits"]
    assert_equal 2, calls
    path = File.join(models, manifest["profile"]["synth_model"])
    File.binwrite(path, "z" * @bytes.bytesize)
    assert_raises(RuntimeError) { create.call.verify_checkpoints! }
    assert_equal 3, calls
  end

  def test_fresh_visual_services_reuse_hashes_but_observe_new_manifest
    runtime = File.join(@root, "visual")
    FileUtils.mkdir_p(File.join(runtime, "stable-diffusion.cpp", "bin"))
    FileUtils.mkdir_p(File.join(runtime, "models"))
    binary = File.join(runtime, "stable-diffusion.cpp", "bin", "sd-cli")
    File.binwrite(binary, "not executed"); File.chmod(0700, binary)
    FileUtils.cp(@path, File.join(runtime, "models", "asset"))
    file = {"role" => "diffusion_model", "filename" => "asset", "bytes" => @bytes.bytesize, "sha256" => @sha}
    profile = {"label" => "fixture", "accelerator" => "fixture", "vulkan_device_selector" => "fixture", "vulkan_device_index" => 0, "files" => [file]}
    manifest = File.join(@root, "visual.json")
    document = {"profiles" => {"fixture" => profile}, "motion_candidates" => {}}
    File.write(manifest, JSON.generate(document))
    create = -> { SoulCore::VisualStudioService.new(root: @root, runtime_root: runtime, manifest_path: manifest, asset_verifier: @cache) }
    assert create.call.resources.dig("data", "ready")
    assert create.call.resources.dig("data", "ready")
    assert_equal 1, @cache.stats["full_hashes"]
    assert_equal 1, @cache.stats["cache_hits"]
    file["sha256"] = "f" * 64
    File.write(manifest, JSON.generate(document))
    refute create.call.resources.dig("data", "ready")
    assert_equal 2, @cache.stats["full_hashes"]
  end
end
