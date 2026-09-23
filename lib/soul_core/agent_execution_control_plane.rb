# frozen_string_literal: true

require "json"
require "pathname"
require "time"

module SoulCore
  class AgentExecutionControlPlane
    MAX_INPUT_BYTES = 1024 * 1024
    MAX_CLASSIFIED_BYTES = 2 * 1024 * 1024
    IDENTIFIER = /\A[A-Za-z0-9][A-Za-z0-9._-]{2,95}\z/
    ROLES = %w[mapper implementer reviewer].freeze
    TERMINAL_STATES = %w[complete failed awaiting_input canceled blocked_for_human_review].freeze
    EVIDENCE_FIELDS = %w[changed_paths commands results uncertainties scope_deviations].freeze
    REVIEW_HEADINGS = [
      "Skill",
      "Candidate status",
      "Implementation summary",
      "Files changed",
      "Commands run",
      "Deterministic test results",
      "Local LLM eval results",
      "Memory keys",
      "Lifecycle states touched",
      "Safety and persistence check",
      "Known weaknesses",
      "Human review checklist"
    ].freeze
    PERSISTENCE_PATH_PATTERNS = {
      "systemd_path" => /(?:\A|\/)(?:systemd|units?)(?:\/|\z)|\.(?:service|timer|socket|path)\z/i,
      "scheduler_path" => /(?:\A|\/)(?:cron|crontab|autostart)(?:\/|\z)/i
    }.freeze
    PERSISTENCE_CONTENT_PATTERNS = {
      "systemd_unit_section" => /^\s*\[(?:Unit|Service|Timer|Socket|Path|Install)\]\s*$/,
      "service_enablement" => /\bsystemctl\s+(?:--user\s+)?(?:enable|reenable|start|restart)\b/,
      "scheduler" => /\b(?:crontab|cron\.d|OnCalendar|systemd-run)\b/,
      "network_listener" => /\b(?:TCPServer|UDPServer|listen\s*\(|socket\.listen|HTTPServer)\b/,
      "unbounded_loop" => /\bwhile\s+true\b|\bloop\s+do\b/,
      "background_launch" => /\b(?:nohup|setsid)\b|(?:^|\s)&\s*(?:#.*)?$/,
      "daemonization" => /\b(?:daemonize|Process\.daemon|fork\s+do)\b/
    }.freeze

    def initialize(root: Dir.pwd)
      @root = File.realpath(root)
    end

    def validate_assignment_file(path)
      data = read_json(path)
      errors = validate_assignment(data)
      report("assignment", errors, "role" => data["role"], "assignment_id" => data["assignment_id"])
    rescue StandardError => error
      failure("assignment", error)
    end

    def validate_lifecycle_file(path)
      data = read_json(path)
      errors = validate_lifecycle(data)
      report(
        "lifecycle",
        errors,
        "receipt_id" => data["receipt_id"],
        "lifecycle_state" => data["lifecycle_state"],
        "continuation_kind" => data.dig("continuation", "kind")
      )
    rescue StandardError => error
      failure("lifecycle", error)
    end

    def validate_approval_link_file(path)
      data = read_json(path)
      required = %w[schema_version link_id artifact_path decision source_kind source_reference scope recorded_at]
      errors = exact_object_errors(data, required)
      errors << "schema_version must be soul.codex.approval_link.v1" unless data["schema_version"] == "soul.codex.approval_link.v1"
      errors << "link_id is invalid" unless data["link_id"].is_a?(String) && data["link_id"].match?(IDENTIFIER)
      errors << "decision is invalid" unless %w[approved rejected changes_requested].include?(data["decision"])
      errors << "source_kind is invalid" unless %w[current_user_message signed_review].include?(data["source_kind"])
      errors.concat(string_errors(data, %w[source_reference]))
      errors.concat(array_of_strings_errors(data, %w[scope]))
      errors << "scope must not contain duplicates" if data["scope"].is_a?(Array) && data["scope"].uniq.length != data["scope"].length
      begin
        Time.iso8601(data.fetch("recorded_at"))
      rescue KeyError, TypeError, ArgumentError
        errors << "recorded_at must be an ISO 8601 timestamp"
      end

      artifact = nil
      begin
        relative = safe_relative_pattern(data.fetch("artifact_path"))
        artifact = safe_file(relative, max_bytes: MAX_INPUT_BYTES)
      rescue KeyError, TypeError, ArgumentError, SystemCallError => error
        errors << "artifact_path: #{error.message}"
      end
      outcome = artifact && File.read(artifact, encoding: "UTF-8")[/^Outcome:\s*(\S+)/i, 1]&.downcase
      report("approval_link", errors.uniq, {
        "artifact_path" => artifact && relative_path(artifact),
        "artifact_outcome" => outcome || "unrecorded",
        "needs_reconciliation" => errors.empty? && outcome != data["decision"],
        "source_verified" => false,
        "authorization_granted" => false,
        "message" => "This links a claimed decision to an artifact; validate the cited user source before recording authority or changing the review outcome."
      })
    rescue StandardError => error
      failure("approval_link", error)
    end

    def validate_review_file(path)
      expanded = safe_file(path, max_bytes: MAX_INPUT_BYTES)
      content = File.read(expanded, encoding: "UTF-8")
      errors = []
      missing = REVIEW_HEADINGS.reject { |heading| content.match?(/^#{Regexp.escape("#")}+\s+#{Regexp.escape(heading)}\s*$/i) }
      errors << "missing review headings: #{missing.join(', ')}" unless missing.empty?
      errors << "risk class must be Class 0 through Class 5" unless content.match?(/^Risk class:\s*(?:Class\s+)?[0-5](?:\b|:)/i)
      statuses = content.scan(/^\s*(candidate_complete|blocked|requires_repair)\s*$/).flatten.uniq
      errors << "candidate status must select exactly one recognized value" unless statuses.length == 1
      states = content.scan(/`?(complete|failed|awaiting_input|canceled|blocked_for_human_review)`?/).flatten.uniq
      errors << "review must name at least one recognized lifecycle state" if states.empty?
      errors << "human review checklist must contain at least one checkbox" unless content.match?(/^\s*-?\s*\[[ xX]\]/)

      report(
        "review",
        errors,
        "path" => relative_path(expanded),
        "candidate_status" => statuses.first,
        "lifecycle_states" => states,
        "required_headings" => REVIEW_HEADINGS
      )
    rescue StandardError => error
      failure("review", error)
    end

    def required_checks(paths, registry_path: "config/codex_required_checks.json")
      registry = read_json(registry_path)
      errors = validate_check_registry(registry)
      return report("required_checks", errors, {}) unless errors.empty?

      normalized = paths.map { |path| safe_relative_pattern(path) }
      checks = Array(registry["default_checks"]).dup
      matched = []
      normalized.each do |path|
        registry.fetch("rules").each do |rule|
          next unless File.fnmatch?(rule.fetch("pattern"), path, File::FNM_PATHNAME | File::FNM_EXTGLOB)

          checks.concat(rule.fetch("checks"))
          matched << { "path" => path, "pattern" => rule.fetch("pattern") }
        end
      end
      checks.uniq!
      definitions = registry.fetch("check_definitions").slice(*checks)
      report(
        "required_checks",
        [],
        "paths" => normalized,
        "checks" => checks,
        "definitions" => definitions,
        "matched_rules" => matched
      )
    rescue StandardError => error
      failure("required_checks", error)
    end

    def classify_persistence(paths)
      findings = []
      normalized = paths.map { |path| safe_relative_pattern(path) }
      normalized.each do |relative|
        PERSISTENCE_PATH_PATTERNS.each do |kind, pattern|
          findings << finding(relative, kind, nil, "path matches #{pattern.inspect}") if relative.match?(pattern)
        end

        expanded = safe_file(relative, max_bytes: MAX_CLASSIFIED_BYTES)
        File.foreach(expanded, encoding: "UTF-8").with_index(1) do |line, number|
          PERSISTENCE_CONTENT_PATTERNS.each do |kind, pattern|
            findings << finding(relative, kind, number, line.strip[0, 240]) if line.match?(pattern)
          end
        end
      end

      report(
        "persistence",
        [],
        "advisory" => true,
        "authorization_granted" => false,
        "paths" => normalized,
        "findings" => findings,
        "message" => "Lexical signals require review; they are neither proof of persistence nor authorization."
      )
    rescue StandardError => error
      failure("persistence", error)
    end

    private

    def validate_assignment(data)
      required = %w[
        schema_version assignment_id role objective expected_deliverable scope
        acceptance_commands authority_limits non_goals shared_worktree evidence_required
      ]
      errors = exact_object_errors(data, required)
      errors << "schema_version must be soul.codex.subagent_assignment.v1" unless data["schema_version"] == "soul.codex.subagent_assignment.v1"
      errors << "assignment_id is invalid" unless data["assignment_id"].is_a?(String) && data["assignment_id"].match?(IDENTIFIER)
      errors << "role must be mapper, implementer, or reviewer" unless ROLES.include?(data["role"])
      errors.concat(string_errors(data, %w[objective expected_deliverable]))
      errors.concat(array_of_strings_errors(data, %w[acceptance_commands authority_limits non_goals]))

      scope = data["scope"]
      errors.concat(exact_object_errors(scope, %w[mode paths], prefix: "scope"))
      if scope.is_a?(Hash)
        expected_mode = data["role"] == "implementer" ? "owned_paths" : "read_only"
        errors << "#{data['role']} scope mode must be #{expected_mode}" unless scope["mode"] == expected_mode
        errors.concat(path_array_errors(scope["paths"], "scope.paths"))
      end

      shared = data["shared_worktree"]
      errors.concat(exact_object_errors(shared, %w[preserve_existing_changes], prefix: "shared_worktree"))
      if shared.is_a?(Hash) && shared["preserve_existing_changes"] != true
        errors << "shared_worktree.preserve_existing_changes must be true"
      end

      evidence = data["evidence_required"]
      unless evidence.is_a?(Array) && evidence.sort == EVIDENCE_FIELDS.sort
        errors << "evidence_required must contain exactly: #{EVIDENCE_FIELDS.join(', ')}"
      end
      errors.uniq
    end

    def validate_lifecycle(data)
      required = %w[
        schema_version receipt_id subject lifecycle_state started_at ended_at message
        continuation evidence_paths
      ]
      errors = exact_object_errors(data, required)
      errors << "schema_version must be soul.skill.lifecycle_receipt.v1" unless data["schema_version"] == "soul.skill.lifecycle_receipt.v1"
      errors << "receipt_id is invalid" unless data["receipt_id"].is_a?(String) && data["receipt_id"].match?(IDENTIFIER)
      errors.concat(string_errors(data, %w[subject message]))
      errors << "lifecycle_state is not terminal" unless TERMINAL_STATES.include?(data["lifecycle_state"])

      begin
        started = Time.iso8601(data.fetch("started_at"))
        ended = Time.iso8601(data.fetch("ended_at"))
        errors << "ended_at precedes started_at" if ended < started
      rescue KeyError, TypeError, ArgumentError
        errors << "started_at and ended_at must be ISO 8601 timestamps"
      end

      continuation = data["continuation"]
      continuation_fields = %w[kind processes_remaining authorization_reference inspect_command stop_command recovery_notes]
      errors.concat(exact_object_errors(continuation, continuation_fields, prefix: "continuation"))
      if continuation.is_a?(Hash)
        kind = continuation["kind"]
        count = continuation["processes_remaining"]
        errors << "continuation.kind is invalid" unless %w[none approved_persistent bounded_development_job].include?(kind)
        errors << "continuation.processes_remaining must be a non-negative integer" unless count.is_a?(Integer) && count >= 0
        if kind == "none"
          errors << "continuation none requires zero remaining processes" unless count == 0
          %w[authorization_reference inspect_command stop_command recovery_notes].each do |field|
            errors << "continuation.#{field} must be null when kind is none" unless continuation[field].nil?
          end
        elsif %w[approved_persistent bounded_development_job].include?(kind)
          errors << "continued work must report at least one remaining process" unless count.is_a?(Integer) && count.positive?
          %w[authorization_reference inspect_command stop_command recovery_notes].each do |field|
            value = continuation[field]
            errors << "continuation.#{field} is required for #{kind}" unless value.is_a?(String) && !value.strip.empty?
          end
        end
      end
      errors.concat(path_array_errors(data["evidence_paths"], "evidence_paths", allow_empty: true))
      errors.uniq
    end

    def validate_check_registry(registry)
      errors = exact_object_errors(registry, %w[schema_version default_checks check_definitions rules])
      errors << "required-check registry schema_version is invalid" unless registry["schema_version"] == "soul.codex.required_checks.v1"
      definitions = registry["check_definitions"]
      errors << "check_definitions must be a non-empty object" unless definitions.is_a?(Hash) && !definitions.empty?
      known = definitions.is_a?(Hash) ? definitions.keys : []
      all_checks = Array(registry["default_checks"]).dup
      rules = registry["rules"]
      if rules.is_a?(Array)
        rules.each_with_index do |rule, index|
          errors.concat(exact_object_errors(rule, %w[pattern checks], prefix: "rules[#{index}]"))
          all_checks.concat(Array(rule["checks"])) if rule.is_a?(Hash)
        end
      else
        errors << "rules must be an array"
      end
      unknown = all_checks.uniq - known
      errors << "undefined checks: #{unknown.join(', ')}" unless unknown.empty?
      errors.uniq
    end

    def read_json(path)
      expanded = safe_file(path, max_bytes: MAX_INPUT_BYTES)
      value = JSON.parse(File.binread(expanded))
      raise ArgumentError, "JSON input must be an object" unless value.is_a?(Hash)

      value
    rescue JSON::ParserError => error
      raise ArgumentError, "invalid JSON: #{error.message}"
    end

    def safe_file(path, max_bytes:)
      value = path.to_s
      raise ArgumentError, "path is required" if value.strip.empty?

      expanded = File.expand_path(value, @root)
      prefix = @root.end_with?(File::SEPARATOR) ? @root : "#{@root}#{File::SEPARATOR}"
      raise ArgumentError, "path must remain inside the repository" unless expanded.start_with?(prefix)

      stat = File.lstat(expanded)
      raise ArgumentError, "input must be a regular non-symlink file" unless stat.file? && !stat.symlink?
      raise ArgumentError, "path must remain inside the repository" unless File.realpath(expanded).start_with?(prefix)
      raise ArgumentError, "input exceeds #{max_bytes} bytes" if stat.size > max_bytes

      expanded
    end

    def safe_relative_pattern(path)
      value = path.to_s.strip
      raise ArgumentError, "path is required" if value.empty?
      raise ArgumentError, "path must be repository-relative" if Pathname.new(value).absolute?
      raise ArgumentError, "path may not contain parent traversal" if Pathname.new(value).each_filename.include?("..")
      raise ArgumentError, "path contains a null byte" if value.include?("\0")

      value.sub(%r{\A\./}, "")
    end

    def relative_path(expanded)
      Pathname.new(expanded).relative_path_from(Pathname.new(@root)).to_s
    end

    def exact_object_errors(value, required, prefix: "input")
      return ["#{prefix} must be an object"] unless value.is_a?(Hash)

      errors = []
      missing = required - value.keys
      unknown = value.keys - required
      errors << "#{prefix} missing fields: #{missing.join(', ')}" unless missing.empty?
      errors << "#{prefix} unknown fields: #{unknown.join(', ')}" unless unknown.empty?
      errors
    end

    def string_errors(data, fields)
      return [] unless data.is_a?(Hash)

      fields.filter_map do |field|
        value = data[field]
        "#{field} must be a non-empty string" unless value.is_a?(String) && !value.strip.empty?
      end
    end

    def array_of_strings_errors(data, fields)
      return [] unless data.is_a?(Hash)

      fields.filter_map do |field|
        value = data[field]
        valid = value.is_a?(Array) && !value.empty? && value.all? { |item| item.is_a?(String) && !item.strip.empty? }
        "#{field} must be a non-empty array of non-empty strings" unless valid
      end
    end

    def path_array_errors(value, field, allow_empty: false)
      return ["#{field} must be an array"] unless value.is_a?(Array)
      return ["#{field} must not be empty"] if value.empty? && !allow_empty
      return ["#{field} must contain unique paths"] unless value.uniq.length == value.length

      value.filter_map do |path|
        safe_relative_pattern(path)
        nil
      rescue ArgumentError => error
        "#{field}: #{error.message}"
      end
    end

    def finding(path, kind, line, evidence)
      { "path" => path, "kind" => kind, "line" => line, "evidence" => evidence }
    end

    def report(operation, errors, data)
      {
        "ok" => errors.empty?,
        "operation" => operation,
        "errors" => errors,
        "data" => data
      }
    end

    def failure(operation, error)
      report(operation, [error.message], {})
    end
  end
end
