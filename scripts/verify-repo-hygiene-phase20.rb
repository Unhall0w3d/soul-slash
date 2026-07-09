
#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

errors = []
warnings = []

def capture(*cmd)
  Open3.capture3(*cmd)
end

def tracked_files
  stdout, _stderr, _status = capture("git", "ls-files")
  stdout.lines.map(&:strip).reject(&:empty?)
end

def ignored?(path)
  _stdout, _stderr, status = capture("git", "check-ignore", "-q", path)
  status.success?
end

puts "repo hygiene phase 20 verification:"

required_files = [
  ".gitignore",
  "docs/REPOSITORY_HYGIENE.md",
  "docs/assessments/README.md",
  "docs/overlays/README.md",
  "docs/workflows/README.md",
  "docs/internal-vs-public.md",
  "docs/maintenance/PHASE20_REPO_HYGIENE.md",
  "scripts/verify-repo-hygiene-phase20.rb"
]

required_files.each do |path|
  ok = File.exist?(path)
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing" unless ok
end

ignore_checks = {
  ".env ignored" => ".env",
  "model file ignored" => "models/example.gguf",
  "overlay_files ignored" => "overlay_files/example.txt",
  "root phase readme ignored" => "README_REPO_HYGIENE_PHASE20.md",
  "docs overlay phase readme ignored" => "docs/overlays/README_REPO_HYGIENE_PHASE20.md",
  "runtime JSON ignored" => "Soul/runtime/capability_matrix.json",
  "runtime tmp ignored" => "Soul/runtime/example.tmp",
  "runtime log ignored" => "Soul/runtime/example.log",
  "improvement proposal ignored" => "Soul/improvement/proposals/example/metadata.json",
  "cloud provider real config ignored" => "Soul/config/cloud_providers.yaml",
  "cloud provider example not ignored" => "Soul/config/cloud_providers.example.yaml",
  "cloud assist artifact ignored" => "Soul/artifacts/cloud_assist/example.json",
  "skill proposal artifact ignored" => "Soul/proposals/skills/example/metadata.json",
  "patch script ignored" => "scripts/patch-example.rb",
  "repair script ignored" => "scripts/repair-example.rb"
}

ignore_checks.each do |name, path|
  expected_ignored = !name.end_with?("not ignored")
  actual = ignored?(path)
  ok = expected_ignored ? actual : !actual
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} failed for #{path}" unless ok
end

files = tracked_files

tracked_failure_patterns = {
  "tracked env files" => /\A\.env(\..+)?\z/,
  "tracked model files" => /\.(gguf|safetensors|bin|pth|pt|onnx|tflite)\z/,
  "tracked generated proposals" => %r{\ASoul/improvement/proposals/(?!\.keep\z).+},
  "tracked runtime JSON" => %r{\ASoul/runtime/.+\.json\z},
  "tracked overlay extraction" => %r{\Aoverlay_files/},
  "tracked root phase readmes" => %r{\AREADME_.*(PHASE|REPAIR).*\.md\z},
  "tracked patch scripts" => %r{\Ascripts/patch-.*\.rb\z},
  "tracked repair scripts" => %r{\Ascripts/repair-.*\.rb\z}
}

tracked_failure_patterns.each do |name, pattern|
  matches = files.grep(pattern)
  matches -= [".env.example"] if name == "tracked env files"
  ok = matches.empty?
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name}: #{matches.join(', ')}" unless ok
end

tracked_docs_overlay_notes = files.grep(%r{\Adocs/overlays/README_.*(PHASE|REPAIR).*\.md\z})
if tracked_docs_overlay_notes.empty?
  puts "- tracked docs overlay phase/repair readmes: ok"
else
  puts "- tracked docs overlay phase/repair readmes: warning"
  warnings << "Tracked overlay README notes should be reviewed in the curation phase: #{tracked_docs_overlay_notes.join(', ')}"
end

doc_checks = {
  "repository hygiene documents generated proposals" => ["docs/REPOSITORY_HYGIENE.md", "Soul/improvement/proposals"],
  "repository hygiene documents durable verifiers" => ["docs/REPOSITORY_HYGIENE.md", "verify-*"],
  "internal/public docs mention local-only" => ["docs/internal-vs-public.md", "Local-only"],
  "assessments index mentions generated runtime JSON" => ["docs/assessments/README.md", "generated runtime JSON"],
  "overlays index mentions temporary" => ["docs/overlays/README.md", "temporary"],
  "workflows index mentions handler" => ["docs/workflows/README.md", "handler"]
}

doc_checks.each do |name, (path, text)|
  ok = File.exist?(path) && File.read(path).include?(text)
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing expected text" unless ok
end

stdout, _stderr, _status = capture("git", "status", "--porcelain")
untracked = stdout.lines.map(&:strip).select { |line| line.start_with?("??") }
leftovers = untracked.select do |line|
  line.include?("README_") ||
    line.include?("overlay_files") ||
    line.include?("Soul/improvement/proposals") ||
    line.include?("Soul/runtime/")
end

unless leftovers.empty?
  warnings << "Untracked local/generated leftovers are present. This is advisory only: #{leftovers.join('; ')}"
end

warnings.each { |warning| puts "- warning: #{warning}" }

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
