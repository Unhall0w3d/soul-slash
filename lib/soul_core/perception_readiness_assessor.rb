# frozen_string_literal: true

require "json"
require "pathname"

module SoulCore
  class PerceptionReadinessAssessor
    MAX_MANIFEST_BYTES = 1_048_576
    TOOL_NAMES = %w[grim slurp hyprctl tesseract].freeze
    PROJECTOR_MEDIA_TYPE = "application/vnd.ollama.image.projector"

    def initialize(root: Dir.pwd, env: ENV, home: Dir.home, path: nil, manifest_path: nil)
      @root = File.expand_path(root)
      @env = env
      @home = File.expand_path(home)
      @path = path || env.fetch("PATH", "")
      @manifest_path = manifest_path
    end

    def assess
      tools = TOOL_NAMES.to_h { |name| [name, executable(name)] }
      manifest = vision_manifest
      active_core = read_json(File.join(@root, "Soul", "runtime", "model_runtime", "core_selection.json"))
      active_core_id = active_core["active_core_id"].to_s
      projector = Array(manifest["layers"]).find { |layer| layer["mediaType"] == PROJECTOR_MEDIA_TYPE }
      vision_model_present = projector.is_a?(Hash)
      capture_ready = tools.values_at("grim", "hyprctl").all?

      {
        "schema_version" => "soul.perception_readiness.v1",
        "read_only" => true,
        "captured_images" => 0,
        "active_core_id" => active_core_id.empty? ? nil : active_core_id,
        "picture_understanding" => {
          "status" => vision_model_present ? "ready_for_beta" : "missing_vision_model",
          "model_manifest" => relative_private_path(manifest.fetch("_path", nil)),
          "projector_present" => vision_model_present,
          "projector_bytes" => projector&.fetch("size", nil),
          "access" => active_core_id == "daily" ? "active" : "requires_daily_core_transition"
        },
        "screen_understanding" => {
          "status" => vision_model_present && capture_ready ? "ready_for_beta" : "missing_requirements",
          "whole_monitor_capture" => !!tools["grim"],
          "region_selection" => !!tools["slurp"],
          "hyprland_inventory" => !!tools["hyprctl"],
          "deterministic_ocr_fallback" => !!tools["tesseract"]
        },
        "tools" => tools.transform_values { |value| value ? File.basename(value) : nil },
        "missing" => missing_requirements(vision_model_present, tools),
        "boundaries" => {
          "capture_activation" => "explicit_request_only",
          "background_observation" => false,
          "cloud_fallback" => false,
          "image_content_authority" => "untrusted_evidence",
          "default_retention" => "ephemeral",
          "mutation_authority" => false
        },
        "recommended_next_slice" => vision_model_present ? "perception_a1_picture_understanding" : "perception_model_qualification"
      }
    end

    private

    def executable(name)
      @path.split(File::PATH_SEPARATOR).filter_map do |directory|
        candidate = File.expand_path(name, directory)
        candidate if File.file?(candidate) && File.executable?(candidate)
      end.first
    end

    def vision_manifest
      path = @manifest_path || default_manifest_candidates.find { |candidate| File.file?(candidate) }
      return {} unless path && File.file?(path)
      return {} if File.size(path) > MAX_MANIFEST_BYTES

      parsed = read_json(path)
      parsed["_path"] = path
      parsed
    rescue Errno::ENOENT, Errno::EACCES
      {}
    end

    def default_manifest_candidates
      root = File.join(@home, ".ollama", "models", "manifests", "registry.ollama.ai", "library")
      [
        File.join(root, "soul-local-chat", "latest"),
        File.join(root, "gemma4", "12b-it-q4_K_M")
      ]
    end

    def read_json(path)
      return {} unless path && File.file?(path)

      JSON.parse(File.read(path, MAX_MANIFEST_BYTES))
    rescue JSON::ParserError, ArgumentError, Errno::ENOENT, Errno::EACCES
      {}
    end

    def relative_private_path(path)
      return nil unless path

      candidate = Pathname.new(File.expand_path(path))
      home = Pathname.new(@home)
      candidate.to_s.start_with?("#{home}/") ? candidate.relative_path_from(home).to_s.prepend("~/") : candidate.to_s
    end

    def missing_requirements(vision_model_present, tools)
      missing = []
      missing << "vision_model_projector" unless vision_model_present
      missing << "whole_monitor_capture_tool" unless tools["grim"]
      missing << "hyprland_monitor_inventory" unless tools["hyprctl"]
      missing << "region_selection_tool" unless tools["slurp"]
      missing << "deterministic_ocr_fallback" unless tools["tesseract"]
      missing
    end
  end
end
