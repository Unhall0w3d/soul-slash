# frozen_string_literal: true

require "digest"
require "json"
require_relative "conversation_memory_store"

module SoulCore
  class ConversationMemoryReflectionBridge
    DEFAULT_APPROVED_ROOT = "Soul/reflection/approved"

    def initialize(root: Dir.pwd, store: nil, approved_root: DEFAULT_APPROVED_ROOT)
      @root = File.expand_path(root)
      @approved_root = File.expand_path(approved_root, @root)
      @store = store || ConversationMemoryStore.new(root: @root)
    end

    def approved_paths
      Dir.glob(File.join(@approved_root, "*.json")).sort
    end

    def preview(target = "latest")
      path = resolve_approved_path(target)
      payload = read_approved(path)
      items = normalized_updates(payload)

      {
        "path" => relative_path(path),
        "task_kind" => payload["task_kind"],
        "reviewed_at" => payload["reviewed_at"],
        "review_status" => payload["review_status"],
        "item_count" => items.length,
        "items" => items.each_with_index.map do |item, index|
          item.merge(
            "index" => index,
            "import_key" => import_key(path, index, item),
            "already_imported" => !existing_record(import_key(path, index, item)).nil?
          )
        end
      }
    end

    def import_candidates(target = "latest")
      preview_result = preview(target)
      path = File.expand_path(preview_result.fetch("path"), @root)
      payload = read_approved(path)
      created = []
      skipped = []

      normalized_updates(payload).each_with_index do |item, index|
        key = import_key(path, index, item)
        existing = existing_record(key)
        if existing
          skipped << {
            "index" => index,
            "import_key" => key,
            "memory_id" => existing["id"],
            "reason" => "already_imported"
          }
          next
        end

        record = @store.propose(
          layer: item.fetch("layer"),
          content: item.fetch("content"),
          source: {
            "kind" => "approved_reflection",
            "reference" => relative_path(path)
          },
          confidence: item.fetch("confidence"),
          tags: Array(item["tags"]) + ["approved-reflection", payload["task_kind"]],
          metadata: {
            "reflection_import_key" => key,
            "reflection_path" => relative_path(path),
            "reflection_item_index" => index,
            "reflection_review_status" => payload["review_status"],
            "reflection_reviewed_at" => payload["reviewed_at"],
            "reflection_source_log" => payload["source_log"]
          }
        )
        created << record
      end

      {
        "path" => relative_path(path),
        "created" => created,
        "skipped" => skipped,
        "created_count" => created.length,
        "skipped_count" => skipped.length,
        "auto_approved" => false
      }
    end

    private

    def resolve_approved_path(target)
      token = target.to_s.strip
      token = "latest" if token.empty?

      if %w[latest last].include?(token.downcase)
        path = approved_paths.last
        raise ArgumentError, "No approved reflection candidates are available" unless path

        return path
      end

      direct = File.expand_path(token, @root)
      return validate_approved_path(direct) if File.file?(direct)

      matches = approved_paths.select { |path| File.basename(path).include?(token) }
      raise ArgumentError, "No approved reflection matched: #{token}" if matches.empty?
      raise ArgumentError, "Multiple approved reflections matched: #{token}" if matches.length > 1

      matches.first
    end

    def validate_approved_path(path)
      expanded = File.expand_path(path)
      prefix = "#{@approved_root}#{File::SEPARATOR}"
      unless expanded.start_with?(prefix) && File.extname(expanded) == ".json"
        raise ArgumentError, "Reflection import is limited to approved JSON candidates"
      end

      expanded
    end

    def read_approved(path)
      validated = validate_approved_path(path)
      payload = JSON.parse(File.read(validated, encoding: "UTF-8"))
      unless payload["review_status"] == "approved"
        raise ArgumentError, "Reflection candidate is not approved"
      end

      payload
    rescue JSON::ParserError => error
      raise ArgumentError, "Approved reflection is not valid JSON: #{error.message}"
    end

    def normalized_updates(payload)
      Array(payload["candidate_memory_updates"]).filter_map do |entry|
        normalize_update(entry)
      end
    end

    def normalize_update(entry)
      attributes = case entry
                   when String
                     { "content" => entry }
                   when Hash
                     entry.transform_keys(&:to_s)
                   else
                     {}
                   end

      content = (attributes["content"] || attributes["memory"] || attributes["text"]).to_s.strip
      return nil if content.empty?

      layer = attributes.fetch("layer", "semantic").to_s
      layer = "semantic" unless ConversationMemoryStore::LAYERS.include?(layer)
      confidence = normalize_confidence(attributes.fetch("confidence", 0.75))

      {
        "layer" => layer,
        "content" => content,
        "confidence" => confidence,
        "tags" => Array(attributes["tags"]).map(&:to_s).reject(&:empty?).uniq.first(20)
      }
    end

    def normalize_confidence(value)
      number = Float(value)
      number = 0.75 unless number.between?(0.0, 1.0)
      number.round(3)
    rescue ArgumentError, TypeError
      0.75
    end

    def import_key(path, index, item)
      material = [relative_path(path), index, canonical_json(item)].join("\n")
      "reflection:#{Digest::SHA256.hexdigest(material)}"
    end

    def existing_record(key)
      @store.records(include_deleted: true).find do |record|
        record.fetch("metadata", {})["reflection_import_key"] == key
      end
    end

    def canonical_json(value)
      JSON.generate(canonicalize(value))
    end

    def canonicalize(value)
      case value
      when Hash
        value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
          original_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
          result[key] = canonicalize(value[original_key])
        end
      when Array
        value.map { |item| canonicalize(item) }
      else
        value
      end
    end

    def relative_path(path)
      expanded = File.expand_path(path)
      prefix = "#{@root}#{File::SEPARATOR}"
      expanded.start_with?(prefix) ? expanded.delete_prefix(prefix) : expanded
    end
  end
end
