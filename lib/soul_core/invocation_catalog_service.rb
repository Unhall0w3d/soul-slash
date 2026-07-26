# frozen_string_literal: true

require "yaml"
require_relative "skill_registry"

module SoulCore
  class InvocationCatalogService
    SCHEMA_VERSION = "soul.invocation_catalog.v1"
    MAX_ENTRIES = 100
    MAX_QUERY = 120
    REQUEST_PATTERNS = [
      /\A\s*(?:please\s+)?(?:show|list|open|explain|describe)\s+(?:the\s+)?(?:invocation|invocations|invocation catalog|invocation list)\b/i,
      /\A\s*(?:please\s+)?(?:show|list|explain|describe)\s+(?:the\s+)?(?:Everyday|Knowledge|Perception|Creative|Runtime|Project|Administration)\s+invocations?\b/i,
      /\A\s*(?:what|which)\s+(?:invocations?|actions)\s+(?:can|do)\s+(?:i|you)\b/i,
      /\A\s*how\s+(?:can|do)\s+i\s+(?:invoke|ask for|request)\s+.+\z/i
    ].freeze

    def initialize(root: Dir.pwd, catalog_path: nil, registry: nil)
      @root = File.expand_path(root)
      @catalog_path = File.expand_path(catalog_path || File.join(@root, "config/invocation_catalog.yaml"))
      @registry = registry || SkillRegistry.new(path: File.join(@root, "Soul/skills/registry.yaml"))
    end

    def match?(message)
      REQUEST_PATTERNS.any? { |pattern| message.to_s.strip.match?(pattern) }
    end

    def list(category: nil, query: nil)
      entries = load_entries
      selected_category = category.to_s.strip
      selected_query = query.to_s.strip
      raise ArgumentError, "invocation category exceeds 80 characters" if selected_category.length > 80
      raise ArgumentError, "invocation query exceeds #{MAX_QUERY} characters" if selected_query.length > MAX_QUERY

      unless selected_category.empty?
        entries = entries.select { |entry| entry.fetch("category").casecmp?(selected_category) }
      end
      unless selected_query.empty?
        needle = selected_query.downcase
        entries = entries.select do |entry|
          searchable(entry).include?(needle)
        end
      end

      {
        "schema_version" => SCHEMA_VERSION,
        "records" => entries,
        "count" => entries.length,
        "categories" => load_entries.map { |entry| entry.fetch("category") }.uniq.sort,
        "read_only" => true,
        "examples_are_authority" => false,
        "mutation" => "none"
      }
    end

    def respond(message)
      entries = load_entries
      text = message.to_s.strip
      exact = resolve_entry(entries, text)
      return render_entry(exact) if exact

      category = resolve_category(entries, text)
      render_overview(category ? entries.select { |entry| entry["category"] == category } : entries, category: category)
    end

    private

    def load_entries
      document = YAML.safe_load_file(@catalog_path, permitted_classes: [], aliases: false)
      raise RuntimeError, "invocation catalog schema is unsupported" unless document["schema_version"] == SCHEMA_VERSION
      entries = Array(document["entries"])
      raise RuntimeError, "invocation catalog size is invalid" if entries.empty? || entries.length > MAX_ENTRIES

      ids = entries.map { |entry| entry["id"].to_s }
      raise RuntimeError, "invocation catalog IDs are invalid" unless ids.uniq.length == ids.length && ids.all? { |id| id.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/) }
      entries.map { |entry| normalize(entry) }
    rescue Psych::Exception, Errno::ENOENT => error
      raise RuntimeError, "invocation catalog is unavailable: #{error.class}"
    end

    def normalize(record)
      required = %w[id label category summary required_inputs optional_inputs core approval output boundary examples]
      missing = required.reject { |key| record.key?(key) }
      raise RuntimeError, "invocation catalog entry is incomplete: #{record['id'] || 'unknown'}" unless missing.empty?
      skill_ids = Array(record["skill_ids"]).map(&:to_s)
      handler_id = record["handler_id"].to_s.strip
      raise RuntimeError, "invocation catalog entry has no owning path: #{record['id']}" if skill_ids.empty? && handler_id.empty?

      unavailable = skill_ids.reject { |skill_id| skill_available?(skill_id) }
      status = unavailable.empty? ? "available" : "unavailable"
      {
        "id" => record.fetch("id").to_s,
        "label" => bounded(record.fetch("label"), 120),
        "category" => bounded(record.fetch("category"), 80),
        "summary" => bounded(record.fetch("summary"), 600),
        "status" => status,
        "skill_ids" => skill_ids,
        "handler_id" => handler_id.empty? ? nil : handler_id,
        "required_inputs" => bounded_list(record.fetch("required_inputs"), 8, 240),
        "optional_inputs" => bounded_list(record.fetch("optional_inputs"), 10, 240),
        "core" => bounded(record.fetch("core"), 240),
        "approval" => bounded(record.fetch("approval"), 400),
        "output" => bounded(record.fetch("output"), 400),
        "boundary" => bounded(record.fetch("boundary"), 500),
        "examples" => bounded_list(record.fetch("examples"), 4, 300),
        "unavailable_skill_ids" => unavailable
      }.reject { |_key, value| value.nil? }
    end

    def skill_available?(skill_id)
      definition = @registry.list[skill_id]
      return false unless definition
      return false if definition["status"].to_s == "unavailable"

      !definition["path"].to_s.empty? || !definition["internal_handler"].to_s.empty?
    end

    def bounded(value, limit)
      text = value.to_s.strip
      raise RuntimeError, "invocation catalog text is blank" if text.empty?
      raise RuntimeError, "invocation catalog text exceeds #{limit} characters" if text.length > limit

      text
    end

    def bounded_list(value, count, limit)
      list = Array(value)
      raise RuntimeError, "invocation catalog list is too large" if list.length > count
      list.map { |item| bounded(item, limit) }
    end

    def searchable(entry)
      [
        entry["id"], entry["label"], entry["category"], entry["summary"],
        entry["core"], entry["output"], entry["boundary"],
        *entry["skill_ids"], *entry["required_inputs"], *entry["optional_inputs"],
        *entry["examples"]
      ].join(" ").downcase
    end

    def resolve_entry(entries, text)
      lowered = text.downcase
      entries
        .select { |entry| lowered.match?(/\b#{Regexp.escape(entry['label'].downcase)}\b/) || lowered.match?(/\b#{Regexp.escape(entry['id'].tr('-', ' '))}\b/) }
        .max_by { |entry| entry["label"].length }
    end

    def resolve_category(entries, text)
      entries.map { |entry| entry["category"] }.uniq.find do |category|
        text.match?(/\b#{Regexp.escape(category)}\b/i)
      end
    end

    def render_overview(entries, category: nil)
      lines = [
        category ? "#{category} invocations" : "Soul invocation catalog",
        "",
        "This is a read-only guide. Listing an invocation does not run it or authorize its gates."
      ]
      entries.each do |entry|
        required = entry["required_inputs"].empty? ? "no required fields" : "requires #{entry['required_inputs'].join('; ')}"
        lines << "- #{entry['label']} — #{entry['status']}; #{required}. #{entry['summary']}"
      end
      lines.concat([
        "",
        "Ask how to invoke one named capability for its Core, approval, output, and boundary.",
        "Lifecycle: complete. Mutation: none."
      ])
      lines.join("\n")
    end

    def render_entry(entry)
      required = entry["required_inputs"].empty? ? "None." : entry["required_inputs"].join("; ")
      optional = entry["optional_inputs"].empty? ? "None." : entry["optional_inputs"].join("; ")
      [
        entry.fetch("label"),
        "Availability: #{entry.fetch('status')}",
        "Category: #{entry.fetch('category')}",
        "",
        entry.fetch("summary"),
        "Required inputs: #{required}",
        "Optional inputs: #{optional}",
        "Core: #{entry.fetch('core')}",
        "Approval: #{entry.fetch('approval')}",
        "Result: #{entry.fetch('output')}",
        "Boundary: #{entry.fetch('boundary')}",
        "Example wording: #{entry.fetch('examples').first}",
        "",
        "The example is inert documentation here. A later request still enters the owning deterministic gates.",
        "Lifecycle: complete. Mutation: none."
      ].join("\n")
    end
  end
end
