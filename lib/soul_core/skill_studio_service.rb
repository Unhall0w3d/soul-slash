# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "time"
require "timeout"

module SoulCore
  class SkillStudioService
    PROPOSALS_ROOT = "Soul/proposals/skills"
    LEGACY_PROPOSALS_ROOT = "Soul/improvement/proposals"
    STATE_FILE = "studio_state.json"
    BETA_DIR = "beta"
    BETA_MANIFEST = "beta_manifest.json"
    TEST_RESULTS = "test_results.json"
    PROPOSAL_CONFIRMATION = "APPROVE_PROPOSAL_FOR_BETA_BUILD"
    PROMOTION_CONFIRMATION = "APPROVE_BETA_FOR_PROMOTION"
    MAX_RECORDS = 100
    MAX_TEXT_BYTES = 64 * 1024
    MAX_ARGS = 20
    MAX_ARG_BYTES = 4 * 1024
    MAX_OUTPUT_BYTES = 32 * 1024
    MAX_TIMEOUT_SECONDS = 60

    def initialize(root: Dir.pwd, clock: -> { Time.now })
      @root = File.expand_path(root)
      @clock = clock
    end

    def proposals(limit: MAX_RECORDS)
      records = proposal_directories.first(bounded_limit(limit)).filter_map { |directory| proposal_projection(directory) }
      success({ "records" => records, "count" => records.length, "limit" => bounded_limit(limit), "read_only" => true })
    end

    def proposal(proposal_id:)
      directory = proposal_directory(proposal_id)
      return awaiting("unknown proposal ID") unless directory

      projection = proposal_projection(directory, detail: true)
      return failed("proposal packet is invalid") unless projection

      success({ "record" => projection, "read_only" => true })
    end

    def proposal_approval_preview(proposal_id:)
      directory = proposal_directory(proposal_id)
      return awaiting("unknown proposal ID") unless directory

      record = proposal_projection(directory)
      return failed("proposal packet is invalid") unless record
      return blocked("proposal is already approved for Beta implementation") if record["proposal_gate"] == "approved"

      digest = proposal_digest(directory)
      success(
        {
          "proposal_id" => proposal_id,
          "title" => record["title"],
          "expected_digest" => digest,
          "confirmation_phrase" => PROPOSAL_CONFIRMATION,
          "effect" => "authorize bounded Beta implementation for this exact proposal revision",
          "does_not" => ["generate code", "invoke Codex", "run a Beta", "register a skill", "promote to production"]
        },
        lifecycle: "blocked_for_human_review"
      )
    end

    def approve_proposal(proposal_id:, expected_digest:, confirmation:)
      directory = proposal_directory(proposal_id)
      return awaiting("unknown proposal ID") unless directory
      return awaiting("exact proposal approval confirmation is required") unless confirmation == PROPOSAL_CONFIRMATION

      current_digest = proposal_digest(directory)
      return blocked("proposal changed after preview; review the current revision") unless secure_equal?(expected_digest, current_digest)

      state = read_state(directory)
      state["schema_version"] = "soul.skill_studio.v1"
      state["proposal_gate"] = {
        "status" => "approved",
        "approved_at" => now,
        "proposal_digest" => current_digest,
        "authority" => "human_exact_confirmation"
      }
      state["beta_gate"] ||= { "status" => "not_ready" }
      write_json(File.join(directory, STATE_FILE), state)
      success(
        { "proposal_id" => proposal_id, "proposal_gate" => "approved", "proposal_digest" => current_digest },
        mutation: "proposal_approved_for_beta_build"
      )
    end

    def betas(limit: MAX_RECORDS)
      records = beta_records.first(bounded_limit(limit))
      success({ "records" => records, "count" => records.length, "limit" => bounded_limit(limit), "production_registry_separate" => true, "read_only" => true })
    end

    def beta(beta_id:)
      located = locate_beta(beta_id)
      return awaiting("unknown Beta skill ID") unless located

      success({ "record" => beta_projection(*located, detail: true), "read_only" => true })
    end

    def beta_run_preview(beta_id:, args: [])
      located = locate_beta(beta_id)
      return awaiting("unknown Beta skill ID") unless located
      directory, manifest, proposal_directory = located
      record = beta_projection(directory, manifest, proposal_directory)
      return blocked("legacy alpha scaffold is not runnable") if record["maturity"] == "legacy_alpha_scaffold"
      return blocked("Beta implementation is incomplete") unless record["runnable"]

      validated_args = validate_args(args)
      return validated_args unless validated_args.is_a?(Array)

      digest = beta_digest(directory, manifest)
      success(
        {
          "beta_id" => beta_id,
          "description" => record["description"],
          "expected_digest" => digest,
          "confirmation_phrase" => "RUN_BETA_SKILL #{beta_id}",
          "argument_count" => validated_args.length,
          "timeout_seconds" => execution_timeout(manifest),
          "diagnostic_logging" => "bounded local JSONL; output may contain skill-produced content",
          "production_skill" => false
        },
        lifecycle: "blocked_for_human_review"
      )
    end

    def run_beta(beta_id:, args:, expected_digest:, confirmation:)
      located = locate_beta(beta_id)
      return awaiting("unknown Beta skill ID") unless located
      directory, manifest, proposal_directory = located
      record = beta_projection(directory, manifest, proposal_directory)
      return blocked("legacy alpha scaffold is not runnable") if record["maturity"] == "legacy_alpha_scaffold"
      return blocked("Beta implementation is incomplete") unless record["runnable"]
      return awaiting("exact Beta run confirmation is required") unless confirmation == "RUN_BETA_SKILL #{beta_id}"

      current_digest = beta_digest(directory, manifest)
      return blocked("Beta changed after preview; review the current revision") unless secure_equal?(expected_digest, current_digest)

      validated_args = validate_args(args)
      return validated_args unless validated_args.is_a?(Array)

      result = execute_beta(directory, manifest, validated_args)
      log_path = append_beta_log(beta_id, current_digest, validated_args.length, result)
      lifecycle = result.fetch("timed_out") ? "failed" : (result.fetch("exit_status") == 0 ? "complete" : "failed")
      success(
        result.merge(
          "beta_id" => beta_id,
          "beta_digest" => current_digest,
          "diagnostic_log" => relative(log_path),
          "production_registry_modified" => false
        ),
        lifecycle: lifecycle,
        mutation: "beta_executed_and_diagnostic_recorded"
      )
    end

    def promotion_preview(beta_id:)
      located = locate_beta(beta_id)
      return awaiting("unknown Beta skill ID") unless located
      directory, manifest, proposal_directory = located
      record = beta_projection(directory, manifest, proposal_directory, detail: true)
      return blocked("legacy alpha scaffold cannot be promoted") if record["maturity"] == "legacy_alpha_scaffold"

      blockers = promotion_blockers(record, proposal_directory)
      digest = beta_digest(directory, manifest)
      success(
        {
          "beta_id" => beta_id,
          "expected_digest" => digest,
          "confirmation_phrase" => PROMOTION_CONFIRMATION,
          "blockers" => blockers,
          "ready" => blockers.empty?,
          "effect" => "record human approval of this Beta revision for a later explicit promotion workflow",
          "promotion_performed" => false
        },
        lifecycle: "blocked_for_human_review"
      )
    end

    def approve_beta_for_promotion(beta_id:, expected_digest:, confirmation:)
      located = locate_beta(beta_id)
      return awaiting("unknown Beta skill ID") unless located
      directory, manifest, proposal_directory = located
      return awaiting("exact Beta promotion confirmation is required") unless confirmation == PROMOTION_CONFIRMATION

      record = beta_projection(directory, manifest, proposal_directory, detail: true)
      blockers = promotion_blockers(record, proposal_directory)
      return blocked("Beta is not ready for promotion review: #{blockers.join('; ')}") unless blockers.empty?

      current_digest = beta_digest(directory, manifest)
      return blocked("Beta changed after preview; review and retest the current revision") unless secure_equal?(expected_digest, current_digest)

      state = read_state(proposal_directory)
      state["schema_version"] = "soul.skill_studio.v1"
      state["beta_gate"] = {
        "status" => "approved_for_promotion",
        "approved_at" => now,
        "beta_id" => beta_id,
        "beta_digest" => current_digest,
        "authority" => "human_exact_confirmation",
        "promotion_performed" => false
      }
      write_json(File.join(proposal_directory, STATE_FILE), state)
      success(
        { "beta_id" => beta_id, "beta_gate" => "approved_for_promotion", "beta_digest" => current_digest, "promotion_performed" => false },
        mutation: "beta_approved_for_later_promotion"
      )
    end

    private

    def proposal_directories
      base = full(PROPOSALS_ROOT)
      return [] unless Dir.exist?(base)

      Dir.children(base).sort.reverse.filter_map do |name|
        next unless safe_id?(name)
        path = File.join(base, name)
        path if File.directory?(path) && File.file?(File.join(path, "metadata.json")) && File.file?(File.join(path, "proposal.md"))
      end
    end

    def proposal_directory(proposal_id)
      return nil unless safe_id?(proposal_id)
      candidate = File.join(full(PROPOSALS_ROOT), proposal_id)
      return nil unless inside?(candidate, full(PROPOSALS_ROOT)) && File.directory?(candidate)
      return nil unless File.file?(File.join(candidate, "metadata.json")) && File.file?(File.join(candidate, "proposal.md"))

      candidate
    end

    def proposal_projection(directory, detail: false)
      metadata = read_json(File.join(directory, "metadata.json"))
      return nil unless metadata.is_a?(Hash)

      proposal_text = read_text(File.join(directory, "proposal.md"))
      state = read_state(directory)
      title = proposal_text[/^#\s+(?:Skill Proposal:\s*)?(.+)$/, 1] || metadata["title"] || metadata["idea"] || File.basename(directory)
      record = {
        "proposal_id" => File.basename(directory),
        "title" => title.to_s.strip[0, 240],
        "description" => proposal_section(proposal_text, "Purpose") || metadata["idea"].to_s[0, 500],
        "created_at" => metadata["created_at"],
        "provider" => metadata["provider"],
        "model" => metadata["model"],
        "proposal_gate" => state.dig("proposal_gate", "status") || "awaiting_review",
        "beta_gate" => state.dig("beta_gate", "status") || "not_ready",
        "proposal_digest" => proposal_digest(directory),
        "human_review_required" => true,
        "beta_present" => File.file?(File.join(directory, BETA_DIR, BETA_MANIFEST))
      }
      if metadata["purpose"] == "capability_gap_intake"
        record["intake"] = true
        record["intake_status"] = state.dig("intake", "status") || metadata["status"] || "awaiting_human_triage"
        record["gap_classification"] = metadata.dig("origin", "classification")
        record["origin_chat_id"] = metadata.dig("origin", "chat_id")
        record["occurrence_count"] = bounded_line_count(File.join(directory, "gap_events.jsonl"), 1_000)
      end
      if detail
        record["proposal_markdown"] = proposal_text
        record["review_checklist"] = checklist_items(File.join(directory, "review_checklist.md"))
        record["cloud_assisted"] = !metadata["provider"].to_s.empty?
        record["cloud_data_class"] = metadata["data_class"]
        record["secrets_included"] = metadata["secrets_included"] == true
        if record["intake"]
          record["request_summary"] = metadata["request_summary"].to_s[0, 4_096]
          record["gap_reason"] = metadata.dig("origin", "reason").to_s[0, 500]
          record["declared_capability_id"] = metadata.dig("origin", "capability_id")
          record["automatic_cloud_use"] = false
        end
      end
      record
    rescue JSON::ParserError, Errno::ENOENT
      nil
    end

    def beta_records
      canonical = proposal_directories.filter_map do |proposal_directory|
        beta_directory = File.join(proposal_directory, BETA_DIR)
        manifest = read_json(File.join(beta_directory, BETA_MANIFEST))
        beta_projection(beta_directory, manifest, proposal_directory) if manifest.is_a?(Hash)
      end
      legacy = legacy_alpha_directories.filter_map do |alpha_directory|
        manifest = read_json(File.join(alpha_directory, "alpha_manifest.json")) || {}
        beta_projection(alpha_directory, manifest.merge("skill_id" => "legacy.#{File.basename(File.dirname(alpha_directory))}"), File.dirname(alpha_directory), legacy: true)
      end
      (canonical + legacy).sort_by { |record| record["beta_id"] }
    end

    def legacy_alpha_directories
      base = full(LEGACY_PROPOSALS_ROOT)
      return [] unless Dir.exist?(base)
      Dir.glob(File.join(base, "*", "alpha")).select { |path| File.directory?(path) && inside?(path, base) }
    end

    def locate_beta(beta_id)
      beta_records.each do |record|
        next unless record["beta_id"] == beta_id
        directory = full(record.fetch("package_path"))
        manifest_name = record["maturity"] == "legacy_alpha_scaffold" ? "alpha_manifest.json" : BETA_MANIFEST
        manifest = read_json(File.join(directory, manifest_name)) || {}
        manifest = manifest.merge("skill_id" => beta_id) if record["maturity"] == "legacy_alpha_scaffold"
        return [directory, manifest, File.dirname(directory)]
      end
      nil
    end

    def beta_projection(directory, manifest, proposal_directory, detail: false, legacy: false)
      entrypoint = manifest["entrypoint"].to_s
      entrypoint_path = File.expand_path(entrypoint, directory) unless entrypoint.empty?
      safe_entrypoint = entrypoint_path && inside?(entrypoint_path, directory) && File.file?(entrypoint_path)
      tests = read_json(File.join(directory, TEST_RESULTS)) || {}
      digest = legacy ? nil : beta_digest(directory, manifest)
      required_tests = Array(manifest["required_tests"]).first(50).map do |item|
        item.is_a?(Hash) ? item.slice("id", "description", "kind") : { "id" => item.to_s, "description" => item.to_s }
      end
      record = {
        "beta_id" => manifest["skill_id"].to_s.empty? ? "invalid.#{File.basename(proposal_directory)}" : manifest["skill_id"].to_s,
        "proposal_id" => File.basename(proposal_directory),
        "description" => (manifest["description"] || manifest["summary"] || "Legacy alpha behavior scaffold").to_s[0, 500],
        "maturity" => legacy ? "legacy_alpha_scaffold" : "beta",
        "risk" => (manifest["risk"] || "unknown").to_s,
        "lifecycle_states" => Array(manifest["lifecycle_states"]).map(&:to_s).first(10),
        "implementation_complete" => manifest["implementation_complete"] == true,
        "runnable" => !legacy && manifest["implementation_complete"] == true && safe_entrypoint,
        "required_tests" => required_tests,
        "test_summary" => test_summary(tests, digest),
        "beta_digest" => digest,
        "package_path" => relative(directory),
        "diagnostic_log_available_after_run" => !legacy,
        "production_registered" => false,
        "promotion_state" => read_state(proposal_directory).dig("beta_gate", "status") || "not_ready"
      }
      if detail
        record["known_weaknesses"] = Array(manifest["known_weaknesses"]).map(&:to_s).first(20)
        record["inputs"] = Array(manifest["inputs"]).first(20)
        record["failure_behavior"] = Array(manifest["failure_behavior"]).map(&:to_s).first(20)
        record["test_results"] = Array(tests["results"]).first(50)
        record["entrypoint_valid"] = !!safe_entrypoint
      end
      record
    end

    def test_summary(tests, digest)
      results = Array(tests["results"])
      {
        "declared" => results.length,
        "passed" => results.count { |item| item.is_a?(Hash) && item["passed"] == true },
        "failed" => results.count { |item| !item.is_a?(Hash) || item["passed"] != true },
        "suite_passed" => tests["passed"] == true,
        "tested_current_revision" => !digest.nil? && secure_equal?(tests["beta_digest"], digest),
        "tested_at" => tests["tested_at"]
      }
    end

    def promotion_blockers(record, proposal_directory)
      blockers = []
      blockers << "proposal Gate 1 is not approved" unless read_state(proposal_directory).dig("proposal_gate", "status") == "approved"
      blockers << "Beta implementation is incomplete" unless record["implementation_complete"]
      blockers << "Beta entrypoint is invalid" unless record["entrypoint_valid"]
      blockers << "no required tests are declared" if record["required_tests"].empty?
      blockers << "test suite has not passed" unless record.dig("test_summary", "suite_passed")
      blockers << "test evidence does not match the current Beta revision" unless record.dig("test_summary", "tested_current_revision")
      required_ids = record["required_tests"].map { |item| item["id"].to_s }.reject(&:empty?)
      passing_ids = Array(record["test_results"]).filter_map { |item| item["id"].to_s if item.is_a?(Hash) && item["passed"] == true }
      missing = required_ids - passing_ids
      blockers << "required tests are not passing: #{missing.join(', ')}" unless missing.empty?
      blockers
    end

    def execute_beta(directory, manifest, args)
      entrypoint = File.expand_path(manifest.fetch("entrypoint"), directory)
      timeout_seconds = execution_timeout(manifest)
      stdout = stderr = ""
      status = nil
      timed_out = false
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Open3.popen3("ruby", entrypoint, *args, chdir: directory) do |stdin, out, err, wait_thread|
        stdin.close
        out_reader = Thread.new { out.read(MAX_OUTPUT_BYTES + 1) }
        err_reader = Thread.new { err.read(MAX_OUTPUT_BYTES + 1) }
        begin
          Timeout.timeout(timeout_seconds) { status = wait_thread.value }
        rescue Timeout::Error
          timed_out = true
          Process.kill("TERM", wait_thread.pid) rescue nil
          begin
            Timeout.timeout(2) { wait_thread.join }
          rescue Timeout::Error
            Process.kill("KILL", wait_thread.pid) rescue nil
            wait_thread.join
          end
        ensure
          stdout = out_reader.value.to_s
          stderr = err_reader.value.to_s
        end
      end
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      {
        "ok" => !timed_out && status&.success? == true,
        "exit_status" => status&.exitstatus,
        "timed_out" => timed_out,
        "duration_ms" => duration_ms,
        "stdout" => truncate(stdout),
        "stderr" => truncate(stderr),
        "output_truncated" => stdout.bytesize > MAX_OUTPUT_BYTES || stderr.bytesize > MAX_OUTPUT_BYTES
      }
    rescue StandardError => error
      { "ok" => false, "exit_status" => nil, "timed_out" => false, "duration_ms" => 0, "stdout" => "", "stderr" => "#{error.class}: #{error.message}"[0, 1000], "output_truncated" => false }
    end

    def append_beta_log(beta_id, digest, argument_count, result)
      safe_name = beta_id.gsub(/[^A-Za-z0-9_.-]/, "_")
      directory = full("Soul/logs/beta_skills")
      FileUtils.mkdir_p(directory)
      path = File.join(directory, "#{safe_name}.jsonl")
      record = {
        "schema_version" => "soul.beta_diagnostic.v1",
        "timestamp" => now,
        "beta_id" => beta_id,
        "beta_digest" => digest,
        "argument_count" => argument_count,
        "ok" => result["ok"],
        "exit_status" => result["exit_status"],
        "timed_out" => result["timed_out"],
        "duration_ms" => result["duration_ms"],
        "stdout" => result["stdout"],
        "stderr" => result["stderr"],
        "output_truncated" => result["output_truncated"]
      }
      File.open(path, "a", 0o600) { |file| file.puts(JSON.generate(record)) }
      path
    end

    def validate_args(args)
      return failed("Beta args must be an array") unless args.is_a?(Array)
      return failed("Beta args exceed #{MAX_ARGS}") if args.length > MAX_ARGS
      return failed("Beta args must be strings") unless args.all? { |item| item.is_a?(String) }
      return failed("a Beta argument exceeds #{MAX_ARG_BYTES} bytes") if args.any? { |item| item.bytesize > MAX_ARG_BYTES }
      args
    end

    def execution_timeout(manifest)
      value = manifest.fetch("timeout_seconds", 30).to_i
      [[value, 1].max, MAX_TIMEOUT_SECONDS].min
    end

    def proposal_digest(directory)
      digest_files(directory, %w[metadata.json proposal.md review_checklist.md sources.md])
    end

    def beta_digest(directory, manifest)
      entrypoint = manifest["entrypoint"].to_s
      files = [BETA_MANIFEST]
      files << entrypoint if !entrypoint.empty? && inside?(File.expand_path(entrypoint, directory), directory)
      digest_files(directory, files)
    end

    def digest_files(directory, names)
      digest = Digest::SHA256.new
      names.sort.each do |name|
        path = File.expand_path(name, directory)
        next unless inside?(path, directory) && File.file?(path)
        digest << name << "\0" << File.binread(path) << "\0"
      end
      digest.hexdigest
    end

    def read_state(directory)
      read_json(File.join(directory, STATE_FILE)) || {}
    end

    def read_json(path)
      JSON.parse(File.read(path, MAX_TEXT_BYTES))
    rescue Errno::ENOENT, JSON::ParserError, ArgumentError
      nil
    end

    def read_text(path)
      File.read(path, MAX_TEXT_BYTES).encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
    end

    def checklist_items(path)
      return [] unless File.file?(path)
      read_text(path).lines.filter_map do |line|
        match = line.match(/^\s*-\s*\[([ xX])\]\s*(.+)$/)
        { "complete" => !match[1].casecmp("x").nonzero?, "text" => match[2].strip[0, 500] } if match
      end.first(50)
    end

    def bounded_line_count(path, limit)
      return 0 unless File.file?(path)
      File.foreach(path).take(limit + 1).length.clamp(0, limit)
    rescue StandardError
      0
    end

    def proposal_section(text, heading)
      match = text.match(/^##\s+#{Regexp.escape(heading)}\s*$\n(.*?)(?=^##\s+|\z)/mi)
      return nil unless match
      match[1].strip.gsub(/\s+/, " ")[0, 500]
    end

    def write_json(path, value)
      temporary = "#{path}.tmp-#{Process.pid}"
      File.open(temporary, "w", 0o600) { |file| file.write(JSON.pretty_generate(value)); file.write("\n") }
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if temporary && File.exist?(temporary)
    end

    def safe_id?(value)
      value.to_s.match?(/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,199}\z/)
    end

    def inside?(path, boundary)
      expanded = File.expand_path(path)
      root = File.expand_path(boundary)
      expanded == root || expanded.start_with?("#{root}#{File::SEPARATOR}")
    end

    def full(relative_path)
      File.expand_path(relative_path, @root)
    end

    def relative(path)
      Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s
    end

    def bounded_limit(limit)
      value = limit.to_i
      value = MAX_RECORDS if value <= 0
      [value, MAX_RECORDS].min
    end

    def truncate(value)
      value.to_s.byteslice(0, MAX_OUTPUT_BYTES).to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
    end

    def secure_equal?(left, right)
      left = left.to_s
      right = right.to_s
      return false unless left.bytesize == right.bytesize && !left.empty?
      left.bytes.zip(right.bytes).reduce(0) { |memo, (a, b)| memo | (a ^ b) }.zero?
    end

    def now
      @clock.call.utc.iso8601
    end

    def success(data, lifecycle: "complete", mutation: "none")
      { "ok" => lifecycle == "complete", "lifecycle_state" => lifecycle, "mutation" => mutation, "data" => data }
    end

    def awaiting(reason)
      { "ok" => false, "lifecycle_state" => "awaiting_input", "mutation" => "none", "data" => { "reason" => reason } }
    end

    def blocked(reason)
      { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "mutation" => "none", "data" => { "reason" => reason } }
    end

    def failed(reason)
      { "ok" => false, "lifecycle_state" => "failed", "mutation" => "none", "data" => { "reason" => reason } }
    end
  end
end
