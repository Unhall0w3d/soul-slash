# frozen_string_literal: true

require "json"
require "net/http"
require "open3"
require "time"
require "uri"

module SoulCore
  class ModelRuntimeAssessor
    DEFAULT_LLAMA_CPP_URL = "http://127.0.0.1:8082"
    DEFAULT_OLLAMA_URL = "http://127.0.0.1:11434"

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess(include_processes: false)
      llama_url = ENV["SOUL_LOCAL_LLM_URL"] || ENV["SOUL_LLAMA_CPP_URL"] || DEFAULT_LLAMA_CPP_URL
      ollama_url = ENV["OLLAMA_HOST"] || DEFAULT_OLLAMA_URL

      report = {
        "status" => "ok",
        "assessment" => "model_runtime",
        "generated_at" => Time.now.iso8601,
        "read_only" => true,
        "process_checks_requested" => include_processes,
        "endpoints" => {
          "llama_cpp_openai" => assess_openai_compatible(llama_url),
          "ollama" => assess_ollama(ollama_url)
        },
        "commands" => command_inventory,
        "gpu" => gpu_inventory,
        "model_files" => model_file_inventory,
        "capability_gaps" => capability_gaps,
        "recommendations" => [],
        "verification" => {
          "no_models_downloaded" => true,
          "no_model_files_modified" => true,
          "no_services_started_or_stopped" => true,
          "read_only_commands_only" => true
        }
      }

      report["processes"] = process_inventory if include_processes
      report["recommendations"] = recommendations(report)
      report
    end

    def render(report)
      lines = []
      lines << "Soul Model Runtime Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Read-only: #{report['read_only']}"
      lines << ""

      lines << "Endpoints"
      report.fetch("endpoints").each do |name, data|
        lines << "- #{name}: #{data['reachable'] ? 'reachable' : 'not reachable'}"
        lines << "  url: #{data['url']}"
        lines << "  models: #{Array(data['models']).length}"
      end
      lines << ""

      lines << "Model Runtime Commands"
      report.fetch("commands").each do |name, data|
        lines << "- #{name}: #{data['detected'] ? 'detected' : 'not detected'}"
      end
      lines << ""

      lines << "GPU / Acceleration"
      report.fetch("gpu").each do |name, data|
        next unless data.is_a?(Hash)
        lines << "- #{name}: #{data['detected'] ? 'detected' : 'not detected'}"
      end
      lines << ""

      lines << "Capability Gaps"
      report.fetch("capability_gaps").each do |gap|
        lines << "- #{gap['capability']}: #{gap['status']}"
        lines << "  #{gap['detail']}"
      end
      lines << ""

      lines << "Recommendations"
      if report.fetch("recommendations").empty?
        lines << "- No recommendations generated."
      else
        report.fetch("recommendations").each_with_index do |rec, index|
          lines << "#{index + 1}. [#{rec['severity'].upcase}] #{rec['title']}"
          lines << "   #{rec['detail']}"
          lines << "   Recommended action: #{rec['action']}"
        end
      end

      lines.join("\n")
    end

    private

    def assess_openai_compatible(base_url)
      url = normalize_url(base_url)
      models = fetch_json("#{url}/v1/models")

      {
        "url" => url,
        "type" => "openai_compatible",
        "reachable" => !models.nil?,
        "models" => extract_openai_models(models),
        "error" => models.nil? ? "not reachable or did not return JSON" : nil
      }
    end

    def assess_ollama(base_url)
      url = normalize_url(base_url)
      tags = fetch_json("#{url}/api/tags")

      {
        "url" => url,
        "type" => "ollama",
        "reachable" => !tags.nil?,
        "models" => extract_ollama_models(tags),
        "error" => tags.nil? ? "not reachable or did not return JSON" : nil
      }
    end

    def fetch_json(url)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 2, open_timeout: 1) do |http|
        response = http.get(uri.request_uri)
        return nil unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end
    rescue StandardError
      nil
    end

    def extract_openai_models(payload)
      Array(payload && payload["data"]).map do |item|
        {
          "id" => item["id"],
          "object" => item["object"]
        }
      end
    end

    def extract_ollama_models(payload)
      Array(payload && payload["models"]).map do |item|
        {
          "name" => item["name"],
          "model" => item["model"],
          "size" => item["size"],
          "modified_at" => item["modified_at"]
        }
      end
    end

    def normalize_url(value)
      raw = value.to_s.strip
      raw = "http://#{raw}" unless raw.start_with?("http://", "https://")
      raw.sub(%r{/\z}, "")
    end

    def command_inventory
      %w[llama-server llama-cli ollama nvidia-smi rocm-smi vulkaninfo lspci].to_h do |name|
        path = command_path(name)
        [name, {"detected" => !path.nil?, "path" => path}]
      end
    end

    def gpu_inventory
      inventory = {
        "nvidia_smi" => {"detected" => !command_path("nvidia-smi").nil?},
        "rocm_smi" => {"detected" => !command_path("rocm-smi").nil?},
        "vulkaninfo" => {"detected" => !command_path("vulkaninfo").nil?}
      }

      if inventory.dig("nvidia_smi", "detected")
        lines = command_lines("nvidia-smi", "--query-gpu=name,memory.total,memory.used,memory.free", "--format=csv,noheader,nounits")
        inventory["nvidia_smi"]["gpus"] = lines.map do |line|
          name, total, used, free = line.split(",").map(&:strip)
          {"name" => name, "memory_total_mib" => total.to_i, "memory_used_mib" => used.to_i, "memory_free_mib" => free.to_i}
        end
      end

      if command_path("lspci")
        inventory["pci_display"] = {
          "detected" => true,
          "items" => command_lines("sh", "-lc", "lspci | grep -Ei 'vga|3d|display' || true")
        }
      else
        inventory["pci_display"] = {"detected" => false, "items" => []}
      end

      inventory
    end

    def model_file_inventory
      candidates = [
        File.join(@root, "models"),
        File.join(@root, "Soul", "models"),
        File.expand_path("~/models"),
        File.expand_path("~/.ollama/models")
      ].uniq

      paths = candidates.each_with_object({}) do |path, hash|
        files = Dir.exist?(path) ? Dir.glob(File.join(path, "**", "*.{gguf,bin,safetensors}")) : []
        hash[path] = {
          "exists" => Dir.exist?(path),
          "model_file_count" => files.length,
          "sample" => files.first(10).map { |f| f.sub(File.expand_path("~"), "~") }
        }
      end

      {
        "read_only" => true,
        "paths" => paths
      }
    end

    def capability_gaps
      [
        {
          "capability" => "vision_screen_understanding",
          "status" => "missing",
          "detail" => "No vision model or screenshot ingestion workflow is currently registered by this assessment.",
          "requires" => ["screenshot_capture_skill", "vision_model_runtime", "vision_workflow_handler"]
        },
        {
          "capability" => "speech_to_text",
          "status" => "missing",
          "detail" => "No local speech-to-text runtime is currently registered by this assessment.",
          "requires" => ["audio_capture", "stt_runtime", "transcription_skill"]
        },
        {
          "capability" => "model_suitability_routing",
          "status" => "partial",
          "detail" => "Soul can detect model endpoints, but does not yet route tasks by model capability.",
          "requires" => ["model_capability_registry", "task_router_policy"]
        },
        {
          "capability" => "skill_generation",
          "status" => "partial",
          "detail" => "Soul can draft and review skill briefs, but does not yet generate alpha skill prototypes.",
          "requires" => ["alpha_skill_generator", "promotion_workflow"]
        }
      ]
    end

    def recommendations(report)
      recs = []

      unless report.dig("endpoints", "llama_cpp_openai", "reachable") || report.dig("endpoints", "ollama", "reachable")
        recs << rec(
          "warn",
          "No local model endpoint reachable",
          "Soul did not detect a reachable llama.cpp/OpenAI-compatible endpoint or Ollama endpoint.",
          "Start the intended local model server when model-backed local workflows are needed."
        )
      end

      if report.dig("endpoints", "llama_cpp_openai", "reachable")
        models = report.dig("endpoints", "llama_cpp_openai", "models")
        if models.empty?
          recs << rec(
            "info",
            "OpenAI-compatible endpoint reachable but no models listed",
            "The endpoint responded to /v1/models but did not expose model IDs.",
            "Confirm the server exposes model metadata if Soul should make model suitability decisions."
          )
        end
      end

      unless report.dig("gpu", "nvidia_smi", "detected")
        recs << rec(
          "info",
          "NVIDIA telemetry unavailable",
          "nvidia-smi was not detected, so Soul cannot report NVIDIA VRAM usage.",
          "No action unless NVIDIA model-runtime routing is needed."
        )
      end

      recs << rec(
        "info",
        "Vision capability not implemented",
        "Soul cannot yet inspect screenshots or reason over visible screen content.",
        "Future phase: add screenshot capture, a vision model runtime, and a bounded vision workflow."
      )

      recs
    end

    def process_inventory
      {
        "llama" => command_lines("sh", "-lc", "ps -eo pid,comm,args | grep -Ei 'llama|ollama' | grep -v grep || true"),
        "gpu" => command_lines("sh", "-lc", "ps -eo pid,comm,args | grep -Ei 'nvidia|rocm|cuda' | grep -v grep || true")
      }
    end

    def rec(severity, title, detail, action)
      {"severity" => severity, "title" => title, "detail" => detail, "action" => action}
    end

    def command_path(name)
      out, status = Open3.capture2("sh", "-lc", "command -v #{name}")
      status.success? ? out.strip : nil
    rescue StandardError
      nil
    end

    def command_lines(*cmd)
      out, _err, status = Open3.capture3(*cmd)
      return [] unless status.success?
      out.lines.map(&:strip).reject(&:empty?)
    rescue StandardError
      []
    end
  end
end
