#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

errors = []
check = ->(name, condition) { condition ? puts("PASS #{name}") : (puts("FAIL #{name}"); errors << name) }

script = File.expand_path("run-dev-core-model-bakeoff.rb", __dir__)
syntax_out, syntax_err, syntax_status = Open3.capture3("ruby", "-c", script)
check.call("runner has valid Ruby syntax", syntax_status.success? && syntax_out.include?("Syntax OK") && syntax_err.empty?)

source = File.read(script)
check.call("runner requires loopback endpoint", source.include?("base URL must be loopback HTTP ending in /v1"))
check.call("runner has total timeout", source.include?("Timeout.timeout(1_800)"))
check.call("runner records but does not execute tool selection", source.include?('"executed" => false') && !source.include?("repo_apply_patch.call"))
check.call("generated code stays in disposable fixture", source.include?("Dir.mktmpdir(\"soul-dev-core-fixture-\")"))
check.call("generated code runs in bounded networkless sandbox", source.include?('"/usr/bin/bwrap", "--unshare-all"') && source.include?('"/usr/bin/timeout", "10"') && source.include?('"--as=536870912"') && source.include?('"--nproc=32"'))
check.call("runner ends at human review", source.include?('result["lifecycle_state"] = "blocked_for_human_review"'))

brief = File.read(File.expand_path("../docs/soul/DEV_CORE_MODEL_BAKEOFF_BRIEF.md", __dir__))
check.call("brief prohibits persistent runtime", brief.include?("must not replace Soul's production chat models or create a\npersistent runtime"))
check.call("brief excludes modified models by default", brief.include?("abliterated derivatives are excluded"))
check.call("brief keeps human authority", brief.include?("human gates authoritative") && brief.include?("Passing this bake-off does not"))

abort "#{errors.length} Dev Core bake-off verification checks failed" unless errors.empty?
puts "Dev Core bake-off verifier passed"
