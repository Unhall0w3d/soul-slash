#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "net/http"
require "uri"
require "time"

def run_cmd(cmd)
  stdout, stderr, status = Open3.capture3(*cmd)
  {
    ok: status.success?,
    stdout: stdout.strip,
    stderr: stderr.strip,
    exit_status: status.exitstatus
  }
rescue StandardError => e
  {
    ok: false,
    stdout: "",
    stderr: "#{e.class}: #{e.message}",
    exit_status: nil
  }
end

def read_file(path)
  File.exist?(path) ? File.read(path).strip : nil
rescue StandardError => e
  "ERROR: #{e.class}: #{e.message}"
end

def http_json(url)
  uri = URI(url)
  res = Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 5) do |http|
    http.get(uri.request_uri)
  end

  body = res.body.to_s
  parsed = begin
    JSON.parse(body)
  rescue JSON::ParserError
    body
  end

  {
    ok: res.is_a?(Net::HTTPSuccess),
    code: res.code.to_i,
    body: parsed
  }
rescue StandardError => e
  {
    ok: false,
    code: nil,
    body: "#{e.class}: #{e.message}"
  }
end

base_url = ENV.fetch("SOUL_OPENAI_BASE_URL", "http://127.0.0.1:8082/v1")
health_url = base_url.sub(%r{/v1/?$}, "") + "/health"
models_url = base_url.sub(%r{/?$}, "") + "/models"

os_release = read_file("/etc/os-release")
kernel = run_cmd(["uname", "-a"])
memory = run_cmd(["free", "-h"])
disk = run_cmd(["df", "-h", ENV.fetch("HOME", "/home/bhones")])
gpu = run_cmd(["nvidia-smi", "--query-gpu=name,memory.total,memory.used,power.draw", "--format=csv,noheader"])
service = run_cmd(["systemctl", "--user", "is-active", "llama-server.service"])
service_status = run_cmd(["systemctl", "--user", "status", "llama-server.service", "--no-pager"])
health = http_json(health_url)
models = http_json(models_url)

result = {
  skill: "system.status",
  generated_at: Time.now.iso8601,
  status: health[:ok] ? "ok" : "warning",
  host: {
    os_release: os_release,
    kernel: kernel,
    memory: memory,
    disk_home: disk
  },
  gpu: {
    nvidia_smi: gpu
  },
  runtime: {
    base_url: base_url,
    health_url: health_url,
    health: health,
    models_url: models_url,
    models: models,
    llama_server_service: {
      active: service,
      status_excerpt: service_status[:stdout].lines.first(20).join
    }
  },
  verification: {
    endpoint_healthy: health[:ok],
    service_active: service[:stdout] == "active",
    model_endpoint_reachable: models[:ok]
  },
  warnings: []
}

result[:warnings] << "llama-server.service is not active" unless result[:verification][:service_active]
result[:warnings] << "llama.cpp health endpoint is not OK" unless result[:verification][:endpoint_healthy]
result[:warnings] << "model endpoint is not reachable" unless result[:verification][:model_endpoint_reachable]

puts JSON.pretty_generate(result)
