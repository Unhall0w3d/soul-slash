# frozen_string_literal: true

module SoulCore
  module ContinuityLab
    # Generation shape only; Actions.parse and journal validation remain binding.
    module QwenActionSchema
      def self.object(properties)
        { "type" => "object", "properties" => properties, "required" => properties.keys,
          "additionalProperties" => false }
      end

      def self.literal(value) = { "const" => value }
      def self.string = { "type" => "string" }
      def self.integer(min, max = nil)
        { "type" => "integer", "minimum" => min }.tap { |schema| schema["maximum"] = max if max }
      end

      def self.tool(name, arguments)
        object("action" => literal("tool"), "tool" => literal(name), "arguments" => object(arguments))
      end

      COMMON_RETRIEVAL = { "lineage_id" => string, "collection" => { "enum" => %w[notes history corpus] } }.freeze
      SCHEMA = { "oneOf" => [
        object("action" => literal("reply"), "content" => string),
        object("action" => literal("wait")),
        tool("note.write", { "note_id" => string, "expected_revision" => integer(0), "content" => string }),
        tool("note.tombstone", { "note_id" => string, "expected_revision" => integer(0) }),
        tool("read", COMMON_RETRIEVAL.merge("id" => string, "revision" => integer(1), "start" => integer(0, 131_072), "length" => integer(1, 1024))),
        tool("search", COMMON_RETRIEVAL.merge("query" => string, "limit" => integer(1, 8)))
      ] }.freeze
    end
  end
end
