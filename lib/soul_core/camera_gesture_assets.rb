# frozen_string_literal: true

require "digest"

module SoulCore
  # Only the isolated camera page loads these exact local runtime bytes.
  class CameraGestureAssets
    PACKAGE_SHA256 = "ee318eaa3d42230aa10910d114faf2a488c577c4e4d33c7cb04126924aca505f"
    MODEL_SHA256 = "a966b1d4e774e0423c19c8aa71f070e5a72fe7a03c2663dd2f3cb0b0095ee3e1"
    ASSETS = {
      "vision_bundle.mjs" => ["d885630c297c0b20b1fe86096cb06291c4c8080876f27852e724f24ac603713f", "text/javascript; charset=utf-8"],
      "gesture_recognizer.task" => [MODEL_SHA256, "application/octet-stream"],
      "wasm/vision_wasm_internal.js" => ["e170ee67dd4e16c1a6fcd8840a206687e5a59b22c20e4a902bc445b095454d73", "text/javascript; charset=utf-8"],
      "wasm/vision_wasm_internal.wasm" => ["8da277a733926eacd0474b8704b36742d6ec3231c57a860c5b889dff8f1df886", "application/wasm"],
      "wasm/vision_wasm_module_internal.js" => ["da8934057f147b622e82cfb4c0dbd85461c598e268588b5a8ba9ca963a8ff82d", "text/javascript; charset=utf-8"],
      "wasm/vision_wasm_module_internal.wasm" => ["2dabd8e23c60984628beb7bb338764c81a08e6837145273f59578684b5d53c1b", "application/wasm"],
      "wasm/vision_wasm_nosimd_internal.js" => ["e81d715a3d42cc3373602eb2f7aff795d164934db680e32496b65dab537f9658", "text/javascript; charset=utf-8"],
      "wasm/vision_wasm_nosimd_internal.wasm" => ["a28483cd42e74e855bf5ebdb6b40d9b66a5b49e35e95020bc97669e6822a3192", "application/wasm"]
    }.freeze
    ROOT_RELATIVE = "Soul/runtime/gesture"

    def initialize(root:)
      @root = File.expand_path(root)
    end

    def read(name)
      expected = ASSETS[name]
      return nil unless expected
      path = File.join(@root, ROOT_RELATIVE, name)
      stat = File.lstat(path)
      return nil unless stat.file? && !stat.symlink? && stat.size.between?(1, 12 * 1024 * 1024)
      bytes = File.binread(path)
      return nil unless Digest::SHA256.hexdigest(bytes) == expected.first
      { "bytes" => bytes, "content_type" => expected.last }
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end
  end
end
