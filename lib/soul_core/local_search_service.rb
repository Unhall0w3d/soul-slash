# frozen_string_literal: true

require "digest"
require "find"
require "json"
require "time"
require_relative "knowledge_vault_service"
require_relative "music_project_store"
require_relative "visual_studio_service"

module SoulCore
  class LocalSearchService
    SOURCES = %w[repository knowledge_vault music visual].freeze
    MAX_QUERY_CHARACTERS = 200
    MAX_RESULTS = 20
    MAX_QUERY_TOKENS = 20
    MAX_REPOSITORY_FILES = 1_000
    MAX_REPOSITORY_FILE_BYTES = 256 * 1024
    MAX_REPOSITORY_TOTAL_BYTES = 32 * 1024 * 1024
    MAX_PROJECTS = 200
    EXCLUDED_DIRECTORIES = %w[.git .obsidian .trash].freeze

    def initialize(
      root: Dir.pwd,
      knowledge_vault_service: nil,
      music_store: nil,
      visual_studio: nil,
      process_env: ENV,
      clock: -> { Time.now.utc }
    )
      @root = File.expand_path(root)
      @knowledge_vault_service = knowledge_vault_service || KnowledgeVaultService.new(root: @root, process_env: process_env)
      @music_store = music_store || MusicProjectStore.new(root: @root)
      @visual_studio = visual_studio || VisualStudioService.new(root: @root)
      @clock = clock
    end

    def search(query:, limit: 10, sources: nil)
      text = query.to_s.strip
      return awaiting("local search query is required") if text.empty?
      raise ArgumentError, "local search query must be 2..#{MAX_QUERY_CHARACTERS} characters" unless text.length.between?(2, MAX_QUERY_CHARACTERS)

      wanted = normalize_limit(limit)
      selected_sources = normalize_sources(sources)
      query_tokens = tokens(text)
      raise ArgumentError, "local search query must contain at least one searchable term" if query_tokens.empty?

      retrieved_at = @clock.call.iso8601(6)
      results = []
      statuses = {}
      selected_sources.each do |source|
        records, status = send("search_#{source}", text, query_tokens, retrieved_at)
        results.concat(records)
        statuses[source] = status
      rescue StandardError => error
        statuses[source] = {
          "lifecycle_state" => "failed",
          "message" => "#{source} search failed safely: #{error.class}",
          "records_scanned" => 0
        }
      end

      ranked = ranked_results(
        results,
        selected_sources: selected_sources,
        limit: wanted
      )
      complete(
        {
          "query" => text,
          "sources" => selected_sources,
          "source_status" => statuses,
          "results" => ranked,
          "count" => ranked.length,
          "limit" => wanted,
          "retrieved_at" => retrieved_at,
          "content_trusted" => false,
          "authority" => "reference_only",
          "persistent_index" => false,
          "mutation" => "none"
        },
        "local project and document search complete"
      )
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      failed("local search failed safely: #{error.class}")
    end

    private

    def search_repository(query, query_tokens, retrieved_at)
      paths, skipped, bytes = repository_paths
      records = paths.filter_map do |path|
        content = read_repository_file(path)
        record_for(
          source: "repository",
          reference: relative_path(path),
          title: markdown_title(content, File.basename(path, File.extname(path))),
          content: content,
          query: query,
          query_tokens: query_tokens,
          updated_at: File.mtime(path).utc.iso8601(6),
          retrieved_at: retrieved_at
        )
      end
      [
        records,
        {
          "lifecycle_state" => "complete",
          "message" => "repository documentation searched",
          "records_scanned" => paths.length,
          "bytes_scanned" => bytes,
          "records_skipped" => skipped,
          "scan_truncated" => paths.length >= MAX_REPOSITORY_FILES || bytes >= MAX_REPOSITORY_TOTAL_BYTES
        }
      ]
    end

    def search_knowledge_vault(query, _query_tokens, retrieved_at)
      outcome = @knowledge_vault_service.search(query: query, limit: MAX_RESULTS)
      unless outcome["lifecycle_state"] == "complete"
        return [
          [],
          {
            "lifecycle_state" => outcome.fetch("lifecycle_state", "failed"),
            "message" => outcome.fetch("message", "knowledge vault unavailable"),
            "records_scanned" => 0
          }
        ]
      end

      data = outcome.fetch("data")
      records = Array(data["records"]).map do |record|
        {
          "source" => "knowledge_vault",
          "reference" => record.fetch("relative_path"),
          "title" => record.fetch("title"),
          "excerpt" => record.fetch("excerpt"),
          "score" => Integer(record.fetch("score")),
          "sha256" => record.fetch("sha256"),
          "updated_at" => nil,
          "retrieved_at" => retrieved_at,
          "authority" => "reference_only"
        }
      end
      [
        records,
        {
          "lifecycle_state" => "complete",
          "message" => "knowledge vault searched",
          "records_scanned" => Integer(data.fetch("files_scanned", records.length)),
          "records_skipped" => 0,
          "scan_truncated" => Integer(data.fetch("files_scanned", 0)) >= KnowledgeVaultService::MAX_FILES
        }
      ]
    end

    def search_music(query, query_tokens, retrieved_at)
      projects = @music_store.list(limit: MAX_PROJECTS)
      records = projects.filter_map do |project|
        content = music_content(project)
        record_for(
          source: "music",
          reference: "music://#{project.fetch('project_id')}",
          title: project.fetch("title"),
          content: content,
          query: query,
          query_tokens: query_tokens,
          updated_at: project["updated_at"],
          retrieved_at: retrieved_at
        )
      end
      [
        records,
        {
          "lifecycle_state" => "complete",
          "message" => "Music Studio projects searched",
          "records_scanned" => projects.length,
          "records_skipped" => 0,
          "scan_truncated" => projects.length >= MAX_PROJECTS
        }
      ]
    end

    def search_visual(query, query_tokens, retrieved_at)
      outcome = @visual_studio.list(limit: MAX_PROJECTS)
      unless outcome["lifecycle_state"] == "complete"
        return [
          [],
          {
            "lifecycle_state" => outcome.fetch("lifecycle_state", "failed"),
            "message" => outcome.fetch("message", "Visual Studio projects unavailable"),
            "records_scanned" => 0
          }
        ]
      end

      projects = Array(outcome.dig("data", "projects"))
      records = projects.filter_map do |project|
        content = visual_content(project)
        record_for(
          source: "visual",
          reference: "visual://#{project.fetch('project_id')}",
          title: project.fetch("title"),
          content: content,
          query: query,
          query_tokens: query_tokens,
          updated_at: project["updated_at"],
          retrieved_at: retrieved_at
        )
      end
      [
        records,
        {
          "lifecycle_state" => "complete",
          "message" => "Visual Studio projects searched",
          "records_scanned" => projects.length,
          "records_skipped" => 0,
          "scan_truncated" => projects.length >= MAX_PROJECTS
        }
      ]
    end

    def repository_paths
      paths = []
      skipped = 0
      bytes = 0
      readme = File.join(@root, "README.md")
      if safe_repository_file?(readme)
        paths << readme
        bytes += File.size(readme)
      elsif File.exist?(readme) || File.symlink?(readme)
        skipped += 1
      end

      docs = File.join(@root, "docs")
      if File.directory?(docs) && !File.symlink?(docs)
        Find.find(docs) do |path|
          stat = File.lstat(path)
          if stat.symlink?
            skipped += 1
            Find.prune if File.directory?(path)
            next
          end
          if stat.directory?
            if path != docs && (File.basename(path).start_with?(".") || EXCLUDED_DIRECTORIES.include?(File.basename(path)))
              Find.prune
            end
            next
          end
          unless safe_repository_file?(path)
            skipped += 1
            next
          end
          file_bytes = stat.size
          if bytes + file_bytes > MAX_REPOSITORY_TOTAL_BYTES
            skipped += 1
            break
          end
          paths << path
          bytes += file_bytes
          break if paths.length >= MAX_REPOSITORY_FILES
        rescue Errno::ENOENT, Errno::EACCES
          skipped += 1
          next
        end
      end
      [paths.sort.first(MAX_REPOSITORY_FILES), skipped, bytes]
    end

    def safe_repository_file?(path)
      return false unless File.extname(path).downcase == ".md"

      stat = File.lstat(path)
      stat.file? && !stat.symlink? && stat.size <= MAX_REPOSITORY_FILE_BYTES
    rescue Errno::ENOENT, Errno::EACCES
      false
    end

    def read_repository_file(path)
      raise "repository document is unsafe" unless safe_repository_file?(path)

      text = File.binread(path, MAX_REPOSITORY_FILE_BYTES).force_encoding(Encoding::UTF_8)
      raise "repository document is not valid UTF-8" unless text.valid_encoding?

      text
    end

    def record_for(source:, reference:, title:, content:, query:, query_tokens:, updated_at:, retrieved_at:)
      score = relevance_score(content, title, query, query_tokens)
      return nil unless score.positive?

      {
        "source" => source,
        "reference" => reference,
        "title" => title.to_s,
        "excerpt" => excerpt(content, query_tokens),
        "score" => score,
        "sha256" => Digest::SHA256.hexdigest(content),
        "updated_at" => updated_at,
        "retrieved_at" => retrieved_at,
        "authority" => "reference_only"
      }
    end

    def relevance_score(content, title, query, query_tokens)
      body = content.downcase
      normalized_title = title.to_s.downcase
      score = query_tokens.sum do |token|
        body.scan(/\b#{Regexp.escape(token)}\b/).length +
          (normalized_title.scan(/\b#{Regexp.escape(token)}\b/).length * 5)
      end
      phrase = query.downcase
      score += 12 if phrase.length >= 4 && body.include?(phrase)
      score
    end

    def excerpt(content, query_tokens)
      flattened = content.to_s.gsub(/\A---\s*\n.*?\n---\s*\n/m, "").gsub(/\s+/, " ").strip
      positions = query_tokens.filter_map { |token| flattened.downcase.index(token) }
      start = [positions.min.to_i - 80, 0].max
      slice = flattened[start, 420].to_s
      start.positive? ? "…#{slice}" : slice
    end

    def markdown_title(content, fallback)
      heading = content.lines.find { |line| line.match?(/\A#\s+\S/) }
      heading ? heading.sub(/\A#\s+/, "").strip : fallback
    end

    def music_content(project)
      [
        project["title"], project["intent"], project["caption"], project["lyrics"],
        project["bpm"], project["keyscale"], project["timesignature"],
        project["vocal_mode"], project["rights_status"]
      ].compact.join("\n")
    end

    def visual_content(project)
      [
        project["title"], project["intent"], project["prompt"],
        project["negative_prompt"], project["aspect_ratio"]
      ].compact.join("\n")
    end

    def tokens(text)
      text.to_s.downcase.scan(/[a-z0-9][a-z0-9_-]+/).uniq.first(MAX_QUERY_TOKENS)
    end

    def normalize_limit(value)
      integer = Integer(value || 10)
      raise ArgumentError, "local search result limit must be between 1 and #{MAX_RESULTS}" unless integer.between?(1, MAX_RESULTS)

      integer
    rescue TypeError, ArgumentError
      raise ArgumentError, "local search result limit must be between 1 and #{MAX_RESULTS}"
    end

    def normalize_sources(values)
      selected = Array(values).flat_map { |value| value.to_s.split(",") }.map(&:strip).reject(&:empty?).uniq
      selected = SOURCES if selected.empty?
      unknown = selected - SOURCES
      raise ArgumentError, "unknown local search sources: #{unknown.join(', ')}" unless unknown.empty?

      SOURCES.select { |source| selected.include?(source) }
    end

    def ranked_results(records, selected_sources:, limit:)
      ordered = records.sort_by do |record|
        [-record.fetch("score"), record.fetch("source"), record.fetch("reference")]
      end
      contributing_sources = selected_sources.select do |source|
        ordered.any? { |record| record.fetch("source") == source }
      end
      return ordered.first(limit) if contributing_sources.length <= 1 || limit < contributing_sources.length

      reserved = contributing_sources.filter_map do |source|
        ordered.find { |record| record.fetch("source") == source }
      end
      selected = (reserved + ordered).uniq.first(limit)
      selected.sort_by do |record|
        [-record.fetch("score"), record.fetch("source"), record.fetch("reference")]
      end
    end

    def relative_path(path)
      expanded = File.expand_path(path)
      prefix = "#{@root}#{File::SEPARATOR}"
      raise "repository document escapes project root" unless expanded.start_with?(prefix)

      expanded.delete_prefix(prefix)
    end

    def complete(data, message)
      { "ok" => true, "lifecycle_state" => "complete", "message" => message, "data" => data }
    end

    def awaiting(message)
      { "ok" => false, "lifecycle_state" => "awaiting_input", "message" => message, "data" => {}, "mutation" => "none" }
    end

    def failed(message)
      { "ok" => false, "lifecycle_state" => "failed", "message" => message, "data" => {}, "mutation" => "none" }
    end
  end
end
