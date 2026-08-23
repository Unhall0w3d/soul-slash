# frozen_string_literal: true

require "digest"
require "json"
require "pathname"

module SoulCore
  # Projects only previously reviewed Markdown bullets into the shared ledger.
  # Source text never crosses the service response boundary.
  class ReviewedMemoryLedgerBootstrapService
    SCHEMA = "soul.reviewed_memory_ledger_bootstrap.a6.v1"
    CONFIRMATION = "IMPORT_REVIEWED_MEMORY_LEDGER"
    SOURCES = {
      "approved_rules" => "Soul/private/memory/approved_rules.md",
      "approved_lessons" => "Soul/private/memory/approved_lessons.md"
    }.freeze
    MAX_SOURCE_BYTES = 64 * 1024
    MAX_RECORDS = 64
    MAX_CONTENT_CHARACTERS = 1_000
    MAX_LEDGER_RECORDS = 10_000

    def initialize(root: Dir.pwd, memory_store:)
      @root = File.expand_path(root)
      @memory_store = memory_store
    end

    def preview
      plan = build_plan
      blocked("reviewed memory ledger import requires exact human confirmation", plan.merge(
        "confirmation_phrase" => CONFIRMATION,
        "expected_digest" => plan_digest(plan),
        "mutation" => "none"
      ))
    rescue StandardError => error
      failed("reviewed memory ledger preview failed safely: #{error.class}: #{error.message}")
    end

    def execute(confirmation:, expected_digest:)
      if confirmation.to_s.empty? || expected_digest.to_s.empty?
        return awaiting("confirmation and preview digest are required")
      end
      return blocked("exact reviewed-memory confirmation did not match") unless confirmation == CONFIRMATION

      plan = build_plan
      return blocked("reviewed memory sources changed; preview again") unless secure_compare(expected_digest, plan_digest(plan))

      imported = []
      skipped = []
      plan.fetch("records").each do |descriptor|
        existing = record_for_import_key(descriptor.fetch("import_key"))
        if existing
          case existing.fetch("status")
          when "approved"
            skipped << existing.fetch("id")
            next
          when "candidate"
            approved = @memory_store.approve(existing.fetch("id"), note: "Approved owner-reviewed memory projection")
            imported << approved.fetch("id")
            next
          else
            return blocked("reviewed memory import conflicts with prior lifecycle state", {
              "conflicting_memory_id" => existing.fetch("id"),
              "conflicting_status" => existing.fetch("status"),
              "mutation" => imported.empty? ? "none" : "partial_append_only_import"
            })
          end
        end

        content = content_for_descriptor(descriptor)
        candidate = @memory_store.propose(
          layer: "semantic",
          content: content,
          source: { "kind" => "owner_reviewed_memory", "reference" => descriptor.fetch("source_id") },
          confidence: 1.0,
          tags: ["owner-reviewed", descriptor.fetch("source_id")],
          metadata: {
            "reviewed_ledger_import_key" => descriptor.fetch("import_key"),
            "source_sha256" => descriptor.fetch("source_sha256"),
            "content_sha256" => descriptor.fetch("content_sha256"),
            "import_contract" => SCHEMA
          }
        )
        approved = @memory_store.approve(candidate.fetch("id"), note: "Approved owner-reviewed memory projection")
        imported << approved.fetch("id")
      end

      complete({
        "schema_version" => SCHEMA,
        "source_digest" => plan.fetch("source_digest"),
        "projected_record_count" => plan.fetch("record_count"),
        "imported_memory_ids" => imported,
        "skipped_memory_ids" => skipped,
        "approved_record_count" => @memory_store.records(status: "approved").length,
        "mutation" => imported.empty? ? "none" : "append_only_memory_events"
      }, "reviewed memory ledger projection completed")
    rescue StandardError => error
      failed("reviewed memory ledger import failed safely: #{error.class}: #{error.message}")
    end

    private

    def build_plan
      @records_snapshot = @memory_store.records(include_deleted: true)
      raise "canonical memory ledger exceeds #{MAX_LEDGER_RECORDS} records" if @records_snapshot.length > MAX_LEDGER_RECORDS

      sources = []
      descriptors = []
      SOURCES.each do |source_id, relative_path|
        path = safe_source_path(relative_path)
        bytes = File.size(path)
        raise "reviewed memory source exceeds #{MAX_SOURCE_BYTES} bytes" if bytes > MAX_SOURCE_BYTES

        content = File.binread(path)
        raise "reviewed memory source is not UTF-8" unless content.force_encoding(Encoding::UTF_8).valid_encoding?

        source_sha = Digest::SHA256.hexdigest(content)
        entries = parse_bullets(content)
        sources << { "source_id" => source_id, "bytes" => bytes, "sha256" => source_sha, "record_count" => entries.length }
        entries.each_with_index do |entry, index|
          content_sha = Digest::SHA256.hexdigest(entry)
          descriptors << {
            "source_id" => source_id,
            "source_sha256" => source_sha,
            "ordinal" => index + 1,
            "content_sha256" => content_sha,
            "import_key" => Digest::SHA256.hexdigest([SCHEMA, source_id, source_sha, index + 1, content_sha].join("\0"))
          }
        end
      end
      raise "reviewed memory projection is empty" if descriptors.empty?
      raise "reviewed memory projection exceeds #{MAX_RECORDS} records" if descriptors.length > MAX_RECORDS

      source_digest = Digest::SHA256.hexdigest(canonical_json(sources))
      {
        "schema_version" => SCHEMA,
        "sources" => sources,
        "source_digest" => source_digest,
        "record_count" => descriptors.length,
        "existing_approved_count" => descriptors.count { |item| record_for_import_key(item.fetch("import_key"))&.fetch("status", nil) == "approved" },
        "records" => descriptors
      }
    end

    def content_for_descriptor(descriptor)
      relative_path = SOURCES.fetch(descriptor.fetch("source_id"))
      content = File.binread(safe_source_path(relative_path)).force_encoding(Encoding::UTF_8)
      entry = parse_bullets(content).fetch(Integer(descriptor.fetch("ordinal")) - 1)
      raise "reviewed memory content changed; preview again" unless Digest::SHA256.hexdigest(entry) == descriptor.fetch("content_sha256")

      entry
    end

    def parse_bullets(content)
      entries = content.lines.filter_map do |line|
        match = line.match(/\A[-*] ([^\r\n]+)\r?\n?\z/)
        next unless match

        value = match[1].strip
        raise "reviewed memory bullet is empty" if value.empty?
        raise "reviewed memory bullet exceeds #{MAX_CONTENT_CHARACTERS} characters" if value.length > MAX_CONTENT_CHARACTERS
        value
      end
      raise "reviewed memory source contains no top-level bullets" if entries.empty?

      entries
    end

    def safe_source_path(relative_path)
      candidate = File.join(@root, relative_path)
      root_path = Pathname.new(@root).realpath
      lexical = Pathname.new(candidate).cleanpath
      raise "reviewed memory source escapes project root" unless lexical.to_s.start_with?("#{root_path}#{File::SEPARATOR}")

      current = root_path
      lexical.relative_path_from(root_path).each_filename do |component|
        current = current.join(component)
        raise "reviewed memory source contains a symlink" if current.symlink?
      end
      raise "reviewed memory source must be a regular file" unless lexical.file?

      lexical.to_s
    end

    def record_for_import_key(import_key)
      (@records_snapshot || @memory_store.records(include_deleted: true)).find do |record|
        record.fetch("metadata", {})["reviewed_ledger_import_key"] == import_key
      end
    end

    def plan_digest(plan)
      Digest::SHA256.hexdigest(canonical_json(plan))
    end

    def canonical_json(value)
      case value
      when Hash then "{" + value.keys.sort.map { |key| "#{JSON.generate(key)}:#{canonical_json(value.fetch(key))}" }.join(",") + "}"
      when Array then "[" + value.map { |item| canonical_json(item) }.join(",") + "]"
      else JSON.generate(value)
      end
    end

    def secure_compare(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize && left.bytes.zip(right.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    end

    def complete(data, message)
      { "lifecycle_state" => "complete", "message" => message, "data" => data }
    end

    def awaiting(message)
      { "lifecycle_state" => "awaiting_input", "message" => message, "data" => { "mutation" => "none" } }
    end

    def blocked(message, data = { "mutation" => "none" })
      { "lifecycle_state" => "blocked_for_human_review", "message" => message, "data" => data }
    end

    def failed(message)
      { "lifecycle_state" => "failed", "message" => message, "data" => { "mutation" => "none" } }
    end
  end
end
