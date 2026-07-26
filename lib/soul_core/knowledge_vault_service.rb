# frozen_string_literal: true

require "digest"
require "fileutils"
require "find"
require "json"
require "securerandom"
require "time"
require_relative "conversation_memory_store"

module SoulCore
  class KnowledgeVaultService
    INITIALIZE_CONFIRMATION = "INITIALIZE_KNOWLEDGE_VAULT"
    EXPORT_CONFIRMATION = "EXPORT_APPROVED_MEMORY_TO_VAULT"
    IMPORT_CONFIRMATION = "IMPORT_VAULT_NOTE_AS_MEMORY_CANDIDATE"
    REFLECTION_CONFIRMATION = "WRITE_KNOWLEDGE_VAULT_NOTE"
    SCHEMA = "soul.knowledge_vault.v1"
    MAX_FILES = 500
    MAX_FILE_BYTES = 256 * 1024
    MAX_RESULTS = 20
    MAX_QUERY_CHARACTERS = 200
    MAX_IMPORT_CHARACTERS = 4_000
    GENERATED_MEMORY_PATH = "Generated/Approved Memory.md"
    EXCLUDED_DIRECTORIES = %w[.git .obsidian .trash].freeze
    REFLECTION_KINDS = %w[
      project decision research workflow lesson environment preference
      episodic_personal studio_candidate transient_status raw_conversation
      credential
    ].freeze
    REFLECTION_EVIDENCE = %w[
      operator_confirmed repository_documentation verified_evidence candidate
      unverified
    ].freeze
    VAULT_EVIDENCE = %w[operator_confirmed repository_documentation verified_evidence].freeze
    VAULT_KINDS = %w[project decision research workflow lesson environment].freeze
    REFLECTION_DIRECTORY = {
      "project" => "Projects",
      "decision" => "Decisions",
      "research" => "Research",
      "workflow" => "Creative Works",
      "lesson" => "Research",
      "environment" => "Environment"
    }.freeze
    REFLECTION_DESTINATION = {
      "preference" => "shared_memory_candidate",
      "episodic_personal" => "shared_memory_candidate",
      "studio_candidate" => "studio_archive",
      "transient_status" => "conversation_only",
      "raw_conversation" => "conversation_only",
      "credential" => "never_store"
    }.freeze
    MAX_REFLECTION_TITLE = 120
    MAX_REFLECTION_BODY = 8_000
    MAX_REFLECTION_SOURCE = 200
    MAX_REFLECTION_TAGS = 10
    STARTER_DIRECTORIES = [
      "Projects",
      "Research",
      "Decisions",
      "Creative Works",
      "Environment",
      "Memory Candidates",
      "Reviews",
      "Generated",
      "Templates"
    ].freeze

    STARTER_FILES = {
      "Index.md" => <<~MARKDOWN,
        ---
        title: Soul Knowledge
        type: index
        status: active
        ---

        # Soul Knowledge

        This vault is a human-readable knowledge surface shared with Soul. It is
        not the canonical authority for approvals, memory promotion, project
        archives, or execution history.

        ## Areas

        - [[Projects]]
        - [[Research]]
        - [[Decisions]]
        - [[Creative Works]]
        - [[Environment]]
        - [[Memory Candidates]]
        - [[Reviews]]
        - [[Generated/Approved Memory]]

        Soul reads this vault only through bounded foreground operations.
      MARKDOWN
      "README.md" => <<~MARKDOWN,
        # Soul Knowledge Vault

        These files are ordinary Markdown and do not require Obsidian. Obsidian
        may be used as the human editing, linking, properties, and graph surface.

        Canonical Soul memory remains in Soul's reviewed append-only memory
        ledger. Notes imported from this vault become candidates and require the
        existing separate memory-approval gate.
      MARKDOWN
      "Templates/Knowledge Note.md" => <<~MARKDOWN,
        ---
        title:
        type: note
        status: draft
        tags: []
        related: []
        created:
        updated:
        ---

        # Title

        ## Summary

        ## Evidence

        ## Decisions

        ## Related
      MARKDOWN
      ".gitignore" => <<~TEXT
        .DS_Store
        .trash/
        .obsidian/cache/
        .obsidian/workspace.json
        .obsidian/workspaces.json
      TEXT
    }.freeze

    def initialize(root: Dir.pwd, process_env: ENV, memory_store: nil, clock: -> { Time.now })
      @project_root = File.expand_path(root)
      @process_env = process_env.to_h.transform_keys(&:to_s)
      @memory_store = memory_store || ConversationMemoryStore.new(root: @project_root)
      @clock = clock
    end

    def status
      path = configured_path
      return awaiting("SOUL_KNOWLEDGE_VAULT_PATH is not configured") unless path

      validate_root_ancestry!(path)
      return complete(status_data(path, exists: false), "knowledge vault path is configured but not initialized") unless File.exist?(path)

      validate_directory!(path)
      files = markdown_paths(path)
      complete(status_data(path, exists: true).merge(
        "markdown_file_count" => files.length,
        "scan_truncated" => files.length >= MAX_FILES,
        "obsidian_surface_detected" => File.directory?(File.join(path, ".obsidian")),
        "git_repository_detected" => File.directory?(File.join(path, ".git"))
      ), "knowledge vault is available")
    rescue StandardError => error
      failed(error.message)
    end

    def search(query:, limit: 10)
      path = ready_root!
      text = query.to_s.strip
      return awaiting("knowledge vault search query is required") if text.empty?
      raise "knowledge vault query exceeds #{MAX_QUERY_CHARACTERS} characters" if text.length > MAX_QUERY_CHARACTERS

      wanted = normalize_limit(limit)
      query_tokens = tokens(text)
      raise "knowledge vault query must contain at least one searchable term" if query_tokens.empty?

      paths = markdown_paths(path)
      records = paths.filter_map do |file|
        content = read_bounded_file(file)
        score = relevance_score(content, query_tokens)
        next unless score.positive?

        relative = relative_path(path, file)
        {
          "relative_path" => relative,
          "title" => note_title(content, relative),
          "score" => score,
          "excerpt" => excerpt(content, query_tokens),
          "sha256" => Digest::SHA256.hexdigest(content)
        }
      end
      records.sort_by! { |record| [-record.fetch("score"), record.fetch("relative_path")] }
      selected = records.first(wanted)
      complete({
        "query" => text,
        "records" => selected,
        "count" => selected.length,
        "limit" => wanted,
        "files_scanned" => paths.length,
        "max_files" => MAX_FILES,
        "content_trusted" => false,
        "mutation" => "none"
      }, "knowledge vault search complete")
    rescue StandardError => error
      failed(error.message)
    end

    def initialize_preview
      path = configured_path
      return awaiting("SOUL_KNOWLEDGE_VAULT_PATH is not configured") unless path

      scope = initialize_scope(path)
      blocked("knowledge vault initialization requires exact human confirmation", scope.merge(
        "confirmation_phrase" => INITIALIZE_CONFIRMATION,
        "expected_digest" => digest(scope)
      ))
    rescue StandardError => error
      failed(error.message)
    end

    def initialize_execute(confirmation:, expected_digest:)
      return awaiting("confirmation and preview digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      return blocked("exact knowledge vault initialization confirmation did not match") unless confirmation == INITIALIZE_CONFIRMATION

      path = configured_path
      return awaiting("SOUL_KNOWLEDGE_VAULT_PATH is not configured") unless path
      scope = initialize_scope(path)
      return blocked("knowledge vault initialization scope changed; preview again") unless secure_compare(expected_digest, digest(scope))

      created = []
      STARTER_DIRECTORIES.each do |relative|
        directory = File.join(path, relative)
        next if File.directory?(directory)

        FileUtils.mkdir_p(directory, mode: 0o700)
        created << directory
      end
      FileUtils.mkdir_p(path, mode: 0o700)
      STARTER_FILES.each do |relative, content|
        destination = File.join(path, relative)
        next if File.file?(destination)

        atomic_write(destination, content)
        created << destination
      end
      complete(scope.merge(
        "created_count" => created.length,
        "created_paths" => created.map { |item| relative_path(path, item) },
        "canonical_memory_changed" => false
      ), "knowledge vault initialized")
    rescue StandardError => error
      failed(error.message)
    end

    def memory_export_preview
      path = ready_root!
      scope = memory_export_scope(path)
      blocked("approved-memory projection requires exact human confirmation", scope.merge(
        "confirmation_phrase" => EXPORT_CONFIRMATION,
        "expected_digest" => digest(scope)
      ))
    rescue StandardError => error
      failed(error.message)
    end

    def memory_export_execute(confirmation:, expected_digest:)
      return awaiting("confirmation and preview digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      return blocked("exact approved-memory projection confirmation did not match") unless confirmation == EXPORT_CONFIRMATION

      path = ready_root!
      scope = memory_export_scope(path)
      return blocked("approved-memory projection scope changed; preview again") unless secure_compare(expected_digest, digest(scope))

      records = @memory_store.records(status: "approved")
      destination = File.join(path, GENERATED_MEMORY_PATH)
      atomic_write(destination, render_memory_export(records))
      complete(scope.merge(
        "written" => true,
        "canonical_memory_changed" => false
      ), "approved memory projected into the knowledge vault")
    rescue StandardError => error
      failed(error.message)
    end

    def memory_import_preview(relative_path:, layer:)
      path = ready_root!
      scope = memory_import_scope(path, relative_path, layer)
      blocked("vault note import requires exact human confirmation", scope.merge(
        "confirmation_phrase" => IMPORT_CONFIRMATION,
        "expected_digest" => digest(scope)
      ))
    rescue StandardError => error
      failed(error.message)
    end

    def memory_import_execute(relative_path:, layer:, confirmation:, expected_digest:)
      return awaiting("confirmation and preview digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      return blocked("exact vault note import confirmation did not match") unless confirmation == IMPORT_CONFIRMATION

      path = ready_root!
      scope = memory_import_scope(path, relative_path, layer)
      return blocked("vault note changed; preview again") unless secure_compare(expected_digest, digest(scope))

      file = safe_markdown_path!(path, relative_path)
      content = import_body(read_bounded_file(file))
      record = @memory_store.propose(
        layer: scope.fetch("layer"),
        content: content,
        source: {
          "kind" => "knowledge_vault",
          "reference" => scope.fetch("relative_path")
        },
        confidence: 1.0,
        tags: ["knowledge-vault", scope.fetch("layer")],
        metadata: {
          "source_sha256" => scope.fetch("sha256"),
          "import_contract" => SCHEMA,
          "requires_separate_approval" => true
        }
      )
      complete(scope.merge(
        "memory_id" => record.fetch("id"),
        "memory_status" => record.fetch("status"),
        "approved_context" => false,
        "next_gate" => "approve memory #{record.fetch('id')}"
      ), "vault note imported as a memory candidate")
    rescue StandardError => error
      failed(error.message)
    end

    def reflection_preview(title:, body:, knowledge_kind:, evidence_status:, source_reference:, target_relative_path: nil, tags: [])
      path = ready_root!
      scope = reflection_scope(
        path,
        title: title,
        body: body,
        knowledge_kind: knowledge_kind,
        evidence_status: evidence_status,
        source_reference: source_reference,
        target_relative_path: target_relative_path,
        tags: tags
      )
      unless scope.fetch("recommended_destination") == "knowledge_vault"
        return complete(scope.merge(
          "write_authorized" => false,
          "mutation" => "none"
        ), "knowledge reflection classified without a vault write")
      end

      blocked("knowledge vault note awaits exact human approval", scope.merge(
        "confirmation_phrase" => REFLECTION_CONFIRMATION,
        "expected_digest" => digest(scope),
        "write_authorized" => false
      ))
    rescue StandardError => error
      failed(error.message)
    end

    def reflection_execute(title:, body:, knowledge_kind:, evidence_status:, source_reference:, target_relative_path: nil, tags: [], confirmation:, expected_digest:)
      return awaiting("confirmation and preview digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      return blocked("exact knowledge vault note confirmation did not match") unless confirmation == REFLECTION_CONFIRMATION

      path = ready_root!
      scope = reflection_scope(
        path,
        title: title,
        body: body,
        knowledge_kind: knowledge_kind,
        evidence_status: evidence_status,
        source_reference: source_reference,
        target_relative_path: target_relative_path,
        tags: tags
      )
      return blocked("this information belongs outside the Knowledge Vault", scope) unless scope.fetch("recommended_destination") == "knowledge_vault"
      return blocked("knowledge reflection scope changed; preview again") unless secure_compare(expected_digest, digest(scope))

      destination = File.join(path, scope.fetch("relative_path"))
      atomic_write(destination, scope.fetch("markdown"))
      complete(scope.except("markdown", "duplicate_candidates").merge(
        "written" => true,
        "sha256" => Digest::SHA256.hexdigest(scope.fetch("markdown")),
        "canonical_memory_changed" => false,
        "git_mutation" => false
      ), "knowledge vault note written")
    rescue StandardError => error
      failed(error.message)
    end

    private

    def configured_path
      raw = @process_env["SOUL_KNOWLEDGE_VAULT_PATH"].to_s.strip
      return nil if raw.empty?
      raise "SOUL_KNOWLEDGE_VAULT_PATH contains a null byte" if raw.include?("\0")
      raise "SOUL_KNOWLEDGE_VAULT_PATH must be absolute or start with ~/" unless raw.start_with?("/", "~/")

      File.expand_path(raw)
    end

    def ready_root!
      path = configured_path
      raise "SOUL_KNOWLEDGE_VAULT_PATH is not configured" unless path

      validate_root_ancestry!(path)
      raise "knowledge vault is not initialized: #{path}" unless File.exist?(path)

      validate_directory!(path)
      path
    end

    def validate_root_ancestry!(path)
      cursor = File::SEPARATOR
      path.split(File::SEPARATOR).reject(&:empty?).each do |component|
        cursor = File.join(cursor, component)
        next unless File.exist?(cursor) || File.symlink?(cursor)

        stat = File.lstat(cursor)
        raise "knowledge vault ancestry must not contain symlinks: #{cursor}" if stat.symlink?
        raise "knowledge vault ancestry must contain only directories: #{cursor}" unless stat.directory?
      end
    end

    def validate_directory!(path)
      stat = File.lstat(path)
      raise "knowledge vault must be a regular non-symlink directory: #{path}" unless stat.directory? && !stat.symlink?
    rescue Errno::ENOENT
      raise "knowledge vault does not exist: #{path}"
    end

    def initialize_scope(path)
      validate_root_ancestry!(path)
      validate_directory!(path) if File.exist?(path)
      files = STARTER_FILES.map do |relative, content|
        destination = File.join(path, relative)
        if File.exist?(destination) || File.symlink?(destination)
          validate_regular_file!(destination)
          existing = File.binread(destination)
          raise "knowledge vault starter file conflicts with existing content: #{relative}" unless existing == content
          state = "retained"
        else
          state = "create"
        end
        {
          "relative_path" => relative,
          "state" => state,
          "sha256" => Digest::SHA256.hexdigest(content),
          "bytes" => content.bytesize
        }
      end
      directories = STARTER_DIRECTORIES.map do |relative|
        destination = File.join(path, relative)
        if File.exist?(destination) || File.symlink?(destination)
          validate_directory!(destination)
          state = "retained"
        else
          state = "create"
        end
        { "relative_path" => relative, "state" => state }
      end
      {
        "schema" => SCHEMA,
        "operation" => "initialize",
        "vault_path" => path,
        "directories" => directories,
        "files" => files,
        "overwrite" => false,
        "obsidian_required" => false,
        "git_mutation" => false
      }
    end

    def memory_export_scope(path)
      destination = File.join(path, GENERATED_MEMORY_PATH)
      destination_state = "absent"
      destination_sha = nil
      if File.exist?(destination) || File.symlink?(destination)
        validate_regular_file!(destination)
        existing = File.binread(destination)
        raise "approved-memory projection destination is not Soul-generated" unless existing.include?("generated_by: soul")
        destination_state = "replace_generated_projection"
        destination_sha = Digest::SHA256.hexdigest(existing)
      end
      records = @memory_store.records(status: "approved")
      {
        "schema" => SCHEMA,
        "operation" => "approved_memory_projection",
        "relative_path" => GENERATED_MEMORY_PATH,
        "destination_state" => destination_state,
        "destination_sha256" => destination_sha,
        "record_count" => records.length,
        "record_ids" => records.map { |record| record.fetch("id") },
        "source_digest" => digest(records),
        "canonical_source" => "conversation_memory_ledger",
        "canonical_memory_changed" => false
      }.compact
    end

    def memory_import_scope(path, requested_relative, requested_layer)
      layer = requested_layer.to_s
      raise "unknown memory layer: #{requested_layer}" unless ConversationMemoryStore::LAYERS.include?(layer)

      file = safe_markdown_path!(path, requested_relative)
      content = read_bounded_file(file)
      body = import_body(content)
      {
        "schema" => SCHEMA,
        "operation" => "vault_note_to_memory_candidate",
        "relative_path" => relative_path(path, file),
        "layer" => layer,
        "title" => note_title(content, requested_relative.to_s),
        "bytes" => content.bytesize,
        "body_characters" => body.length,
        "sha256" => Digest::SHA256.hexdigest(content),
        "result_status" => "candidate",
        "automatic_approval" => false
      }
    end

    def reflection_scope(path, title:, body:, knowledge_kind:, evidence_status:, source_reference:, target_relative_path:, tags:)
      normalized_title = normalize_reflection_title(title)
      normalized_body = normalize_reflection_body(body)
      kind = knowledge_kind.to_s.strip
      evidence = evidence_status.to_s.strip
      source = source_reference.to_s.strip
      raise "unknown knowledge kind: #{knowledge_kind}" unless REFLECTION_KINDS.include?(kind)
      raise "unknown evidence status: #{evidence_status}" unless REFLECTION_EVIDENCE.include?(evidence)
      raise "knowledge reflection source_reference is required" if source.empty?
      raise "knowledge reflection source_reference exceeds #{MAX_REFLECTION_SOURCE} characters" if source.length > MAX_REFLECTION_SOURCE

      normalized_tags = normalize_reflection_tags(tags)
      sensitive = likely_secret?(normalized_title) || likely_secret?(normalized_body)
      destination, reason = reflection_destination(kind, evidence, sensitive)
      base = {
        "schema" => SCHEMA,
        "operation" => "knowledge_reflection",
        "title" => normalized_title,
        "knowledge_kind" => kind,
        "evidence_status" => evidence,
        "source_reference" => source,
        "tags" => normalized_tags,
        "recommended_destination" => destination,
        "recommendation_reason" => reason,
        "secret_material_detected" => sensitive,
        "automatic_write" => false,
        "automatic_memory_promotion" => false,
        "canonical_memory_changed" => false,
        "git_mutation" => false
      }
      return base unless destination == "knowledge_vault"

      relative = reflection_target_path(path, normalized_title, kind, target_relative_path)
      absolute = File.join(path, relative)
      prior_sha = nil
      mode = "create"
      if File.exist?(absolute) || File.symlink?(absolute)
        validate_regular_file!(absolute)
        prior_sha = Digest::SHA256.hexdigest(read_bounded_file(absolute))
        mode = "replace_reviewed_note"
      end
      markdown = render_reflection_note(
        title: normalized_title,
        body: normalized_body,
        kind: kind,
        evidence: evidence,
        source: source,
        tags: normalized_tags
      )
      duplicates = reflection_duplicates(normalized_title, normalized_body)
      base.merge(
        "relative_path" => relative,
        "write_mode" => mode,
        "prior_sha256" => prior_sha,
        "new_sha256" => Digest::SHA256.hexdigest(markdown),
        "markdown" => markdown,
        "duplicate_candidates" => duplicates,
        "duplicate_count" => duplicates.length
      ).compact
    end

    def reflection_destination(kind, evidence, sensitive)
      return ["never_store", "likely credential or secret material must not enter the vault"] if sensitive || kind == "credential"
      return [REFLECTION_DESTINATION.fetch(kind), reflection_non_vault_reason(kind)] if REFLECTION_DESTINATION.key?(kind)
      return ["conversation_only", "candidate or unverified evidence is not durable reviewed knowledge"] unless VAULT_EVIDENCE.include?(evidence)
      return ["conversation_only", "the supplied kind is not eligible for durable vault storage"] unless VAULT_KINDS.include?(kind)

      ["knowledge_vault", "durable project knowledge has reviewed provenance and may be proposed for the vault"]
    end

    def reflection_non_vault_reason(kind)
      case kind
      when "preference", "episodic_personal" then "personal durable context belongs in the reviewed shared-memory flow"
      when "studio_candidate" then "candidate-specific creative lineage belongs in its canonical Studio archive"
      when "transient_status" then "point-in-time status belongs in its evidence surface or current conversation"
      when "raw_conversation" then "raw conversation remains in the conversation store"
      else "this information must not be stored"
      end
    end

    def normalize_reflection_title(value)
      text = value.to_s.strip
      raise "knowledge reflection title must be 3..#{MAX_REFLECTION_TITLE} characters" unless text.length.between?(3, MAX_REFLECTION_TITLE)
      raise "knowledge reflection title contains invalid control characters" if text.match?(/[\u0000-\u001f\u007f]/)

      text
    end

    def normalize_reflection_body(value)
      text = value.to_s.strip
      raise "knowledge reflection body is required" if text.empty?
      raise "knowledge reflection body exceeds #{MAX_REFLECTION_BODY} characters" if text.length > MAX_REFLECTION_BODY
      raise "knowledge reflection body is not valid UTF-8" unless text.valid_encoding?
      raise "knowledge reflection body contains a null byte" if text.include?("\0")

      text
    end

    def normalize_reflection_tags(values)
      tags = Array(values).map { |value| value.to_s.strip.downcase }.reject(&:empty?).uniq
      raise "knowledge reflection accepts at most #{MAX_REFLECTION_TAGS} tags" if tags.length > MAX_REFLECTION_TAGS
      raise "knowledge reflection tags must use letters, numbers, hyphens, or underscores" unless tags.all? { |tag| tag.match?(/\A[a-z0-9][a-z0-9_-]{0,39}\z/) }

      tags
    end

    def likely_secret?(text)
      value = text.to_s
      patterns = [
        /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
        /\b(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[:=]\s*["']?[A-Za-z0-9_\-\/+=]{8,}/i,
        /\bgh[opusr]_[A-Za-z0-9]{20,}\b/,
        /\bsk-[A-Za-z0-9_-]{20,}\b/
      ]
      patterns.any? { |pattern| value.match?(pattern) }
    end

    def reflection_target_path(root, title, kind, requested)
      if requested.to_s.strip.empty?
        filename = title.gsub(/[\\\/:*?"<>|]/, " ").gsub(/\s+/, " ").strip
        filename = filename[0, 100].to_s.strip
        raise "knowledge reflection title cannot produce a safe filename" if filename.empty? || %w[. ..].include?(filename)
        relative = File.join(REFLECTION_DIRECTORY.fetch(kind), "#{filename}.md")
        safe_new_markdown_path!(root, relative)
        return relative
      end

      existing = safe_markdown_path!(root, requested)
      relative = relative_path(root, existing)
      directory = relative.split(File::SEPARATOR).first
      raise "knowledge reflection update target must be in a durable vault area" unless REFLECTION_DIRECTORY.values.uniq.include?(directory)

      relative
    end

    def safe_new_markdown_path!(root, relative)
      components = relative.to_s.split(/[\\\/]/)
      raise "knowledge reflection path is unsafe" if components.any? { |component| component.empty? || component == "." || component == ".." || component.start_with?(".") }
      raise "knowledge reflection path must name a Markdown file" unless File.extname(relative).downcase == ".md"
      path = File.expand_path(File.join(root, *components))
      raise "knowledge reflection path escapes the vault" unless path.start_with?("#{root}#{File::SEPARATOR}")
      parent = File.dirname(path)
      validate_directory!(parent)
      raise "knowledge reflection destination may not be a symlink" if File.symlink?(path)

      path
    end

    def reflection_duplicates(title, body)
      query = ([title] + tokens(body).first(8)).join(" ")
      result = search(query: query, limit: 5)
      return [] unless result["lifecycle_state"] == "complete"

      result.dig("data", "records").to_a.map do |record|
        record.slice("relative_path", "title", "score", "sha256")
      end
    end

    def render_reflection_note(title:, body:, kind:, evidence:, source:, tags:)
      review_date = @clock.call.strftime("%Y-%m-%d")
      lines = [
        "---",
        "title: #{JSON.generate(title)}",
        "type: #{kind}",
        "status: active",
        "tags: #{JSON.generate(tags)}",
        "source_reference: #{JSON.generate(source)}",
        "evidence_status: #{evidence}",
        "generated_by: soul-knowledge-reflection",
        "updated: #{review_date}",
        "---",
        "",
        "# #{title}",
        "",
        body,
        ""
      ]
      lines.join("\n")
    end

    def safe_markdown_path!(root, requested)
      text = requested.to_s.strip
      raise "relative_path is required" if text.empty?
      raise "relative_path must be relative to the knowledge vault" if text.start_with?("/", "~/")
      components = text.split(/[\\\/]/)
      raise "relative_path contains unsafe traversal" if components.any? { |component| component.empty? || component == "." || component == ".." }
      raise "relative_path must name a Markdown file" unless File.extname(text).downcase == ".md"
      raise "relative_path may not enter a hidden directory" if components.any? { |component| component.start_with?(".") }

      path = File.expand_path(File.join(root, *components))
      prefix = "#{root}#{File::SEPARATOR}"
      raise "relative_path escapes the knowledge vault" unless path.start_with?(prefix)
      validate_regular_file!(path)
      path
    end

    def validate_regular_file!(path)
      stat = File.lstat(path)
      raise "knowledge vault path must be a regular non-symlink file: #{path}" unless stat.file? && !stat.symlink?
      raise "knowledge vault file exceeds #{MAX_FILE_BYTES} bytes: #{path}" if stat.size > MAX_FILE_BYTES
    rescue Errno::ENOENT
      raise "knowledge vault file does not exist: #{path}"
    end

    def markdown_paths(root)
      paths = []
      Find.find(root) do |path|
        relative = path.delete_prefix("#{root}#{File::SEPARATOR}")
        stat = File.lstat(path)
        if stat.symlink?
          Find.prune if File.directory?(path)
          next
        end
        if path != root && stat.directory?
          name = File.basename(path)
          if name.start_with?(".") || EXCLUDED_DIRECTORIES.include?(name)
            Find.prune
            next
          end
        end
        next if path == root || stat.directory?
        next unless stat.file?
        next unless File.extname(path).downcase == ".md"
        next if relative.split(File::SEPARATOR).any? { |component| component.start_with?(".") }

        validate_regular_file!(path)
        paths << path
        break if paths.length >= MAX_FILES
      rescue RuntimeError
        raise
      rescue StandardError
        next
      end
      paths.sort
    end

    def read_bounded_file(path)
      validate_regular_file!(path)
      content = File.binread(path)
      text = content.force_encoding(Encoding::UTF_8)
      raise "knowledge vault file is not valid UTF-8: #{path}" unless text.valid_encoding?

      text
    end

    def import_body(content)
      body = content.sub(/\A---\s*\n.*?\n---\s*\n/m, "").strip
      raise "knowledge vault note body is empty" if body.empty?
      raise "knowledge vault note body exceeds #{MAX_IMPORT_CHARACTERS} characters" if body.length > MAX_IMPORT_CHARACTERS

      body
    end

    def note_title(content, fallback)
      frontmatter = content[/\A---\s*\n(.*?)\n---\s*\n/m, 1]
      property_title = frontmatter&.lines&.find { |line| line.match?(/\Atitle:\s*/i) }&.sub(/\Atitle:\s*/i, "")&.strip
      return property_title unless property_title.to_s.empty?

      heading = content.lines.find { |line| line.match?(/\A#\s+\S/) }
      return heading.sub(/\A#\s+/, "").strip if heading

      File.basename(fallback.to_s, File.extname(fallback.to_s))
    end

    def relevance_score(content, query_tokens)
      normalized = content.downcase
      query_tokens.sum { |token| normalized.scan(/\b#{Regexp.escape(token)}\b/).length }
    end

    def excerpt(content, query_tokens)
      flattened = content.gsub(/\A---\s*\n.*?\n---\s*\n/m, "").gsub(/\s+/, " ").strip
      positions = query_tokens.filter_map { |token| flattened.downcase.index(token) }
      start = [positions.min.to_i - 100, 0].max
      slice = flattened[start, 500].to_s
      start.positive? ? "…#{slice}" : slice
    end

    def tokens(text)
      text.to_s.downcase.scan(/[a-z0-9][a-z0-9_-]{1,}/).uniq.first(20)
    end

    def normalize_limit(value)
      integer = Integer(value || 10)
      raise "knowledge vault result limit must be between 1 and #{MAX_RESULTS}" unless integer.between?(1, MAX_RESULTS)

      integer
    rescue ArgumentError, TypeError
      raise "knowledge vault result limit must be between 1 and #{MAX_RESULTS}"
    end

    def render_memory_export(records)
      lines = [
        "---",
        "title: Approved Soul Memory",
        "type: generated-memory-index",
        "generated_by: soul",
        "generated_at: #{@clock.call.iso8601(6)}",
        "canonical_source: conversation-memory-ledger",
        "record_count: #{records.length}",
        "---",
        "",
        "# Approved Soul Memory",
        "",
        "> Generated projection. Edit canonical memory through Soul's reviewed memory controls, not this file.",
        ""
      ]
      ConversationMemoryStore::LAYERS.each do |layer|
        layer_records = records.select { |record| record["layer"] == layer }
        next if layer_records.empty?

        lines << "## #{layer.capitalize}"
        lines << ""
        layer_records.each do |record|
          source = record.fetch("source", {})
          source_label = [source["kind"], source["reference"]].compact.join(":")
          lines << "### #{record.fetch('id')}"
          lines << ""
          lines << record.fetch("content").to_s
          lines << ""
          lines << "- Status: approved"
          lines << "- Confidence: #{record.fetch('confidence')}"
          lines << "- Source: #{source_label.empty? ? 'unspecified' : source_label}"
          lines << "- Updated: #{record.fetch('updated_at')}"
          lines << ""
        end
      end
      lines.join("\n") + "\n"
    end

    def status_data(path, exists:)
      {
        "schema" => SCHEMA,
        "configured" => true,
        "vault_path" => path,
        "exists" => exists,
        "obsidian_required" => false,
        "canonical_memory_store" => "conversation_memory_ledger",
        "automatic_indexing" => false,
        "watcher" => false,
        "network_access" => false,
        "max_files" => MAX_FILES,
        "max_file_bytes" => MAX_FILE_BYTES
      }
    end

    def atomic_write(path, content)
      validate_root_ancestry!(File.dirname(path))
      FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
      if File.exist?(path) || File.symlink?(path)
        validate_regular_file!(path)
      end
      temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      File.chmod(0o600, path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def relative_path(root, path)
      return "." if File.expand_path(path) == File.expand_path(root)

      File.expand_path(path).delete_prefix("#{File.expand_path(root)}#{File::SEPARATOR}")
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
    end

    def canonicalize(value)
      case value
      when Hash
        value.keys.map(&:to_s).sort.to_h { |key| [key, canonicalize(value.fetch(key))] }
      when Array then value.map { |item| canonicalize(item) }
      else value
      end
    end

    def secure_compare(left, right)
      left = left.to_s
      right = right.to_s
      return false unless left.bytesize == right.bytesize

      left.bytes.zip(right.bytes).reduce(0) { |difference, pair| difference | (pair[0] ^ pair[1]) }.zero?
    end

    def complete(data, message)
      { "ok" => true, "lifecycle_state" => "complete", "message" => message, "data" => data }
    end

    def awaiting(message)
      { "ok" => false, "lifecycle_state" => "awaiting_input", "message" => message, "data" => {} }
    end

    def blocked(message, data = {})
      { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "message" => message, "data" => data }
    end

    def failed(message)
      { "ok" => false, "lifecycle_state" => "failed", "message" => message, "data" => {} }
    end
  end
end
