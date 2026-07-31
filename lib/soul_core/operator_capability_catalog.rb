# frozen_string_literal: true

require "yaml"

module SoulCore
  class OperatorCapabilityCatalog
    SCHEMA = "soul.operator_capability_catalog.v1"
    MAX_SURFACES = 64
    COVERAGE = %w[available partial dashboard_only missing].freeze
    COVERAGE_CHANNELS = %w[dashboard chat voice].freeze

    def initialize(root: Dir.pwd, path: nil)
      @path = File.expand_path(path || File.join(root, "config", "operator_capability_catalog.yaml"))
    end

    def surfaces
      document = YAML.safe_load_file(@path, permitted_classes: [], aliases: false)
      raise RuntimeError, "operator capability catalog schema is unsupported" unless document["schema_version"] == SCHEMA

      records = Array(document["surfaces"])
      raise RuntimeError, "operator capability catalog size is invalid" if records.empty? || records.length > MAX_SURFACES
      ids = records.map { |record| record["id"].to_s }
      raise RuntimeError, "operator capability catalog IDs are invalid" unless ids.uniq.length == ids.length

      records.map { |record| normalize(record) }
    rescue Psych::Exception, Errno::ENOENT => error
      raise RuntimeError, "operator capability catalog is unavailable: #{error.class}"
    end

    def find(id)
      surfaces.find { |surface| surface["id"] == id.to_s }
    end

    private

    def normalize(record)
      required = %w[id label aliases summary inputs boundary skills invocations operations targets interfaces coverage authority completion]
      missing = required.reject { |field| record.key?(field) }
      raise RuntimeError, "operator capability entry is incomplete: #{record['id'] || 'unknown'}" unless missing.empty?

      coverage = record.fetch("coverage").transform_keys(&:to_s).transform_values(&:to_s)
      raise RuntimeError, "operator capability coverage is invalid" unless coverage.keys.sort == COVERAGE_CHANNELS.sort && coverage.values.all? { |value| COVERAGE.include?(value) }
      authority = record.fetch("authority")
      completion = record.fetch("completion")
      raise RuntimeError, "operator capability authority is invalid" unless authority.is_a?(Hash) && authority.keys.map(&:to_s).sort == %w[conversational_confirmation default operator_gesture_required].sort
      raise RuntimeError, "operator capability completion is invalid" unless completion.is_a?(Hash) && completion.keys.map(&:to_s).sort == %w[progress receipt].sort

      {
        "id" => token(record.fetch("id"), 80),
        "label" => text(record.fetch("label"), 120),
        "aliases" => list(record.fetch("aliases"), 12, 120),
        "summary" => text(record.fetch("summary"), 700),
        "inputs" => text(record.fetch("inputs"), 700),
        "boundary" => text(record.fetch("boundary"), 700),
        "skills" => list(record.fetch("skills"), 16, 120),
        "invocations" => list(record.fetch("invocations"), 16, 120),
        "operations" => list(record.fetch("operations"), 40, 160),
        "targets" => list(record.fetch("targets"), 16, 160),
        "interfaces" => list(record.fetch("interfaces"), 8, 80),
        "coverage" => coverage,
        "authority" => {
          "default" => text(authority.fetch("default"), 80),
          "conversational_confirmation" => list(authority.fetch("conversational_confirmation"), 16, 160),
          "operator_gesture_required" => list(authority.fetch("operator_gesture_required"), 16, 160)
        },
        "completion" => {
          "progress" => text(completion.fetch("progress"), 160),
          "receipt" => text(completion.fetch("receipt"), 240)
        }
      }
    end

    def token(value, limit)
      result = value.to_s.strip
      raise RuntimeError, "operator capability token is invalid" unless result.match?(/\A[a-z0-9]+(?:_[a-z0-9]+)*\z/) && result.length <= limit

      result
    end

    def text(value, limit)
      result = value.to_s.strip
      raise RuntimeError, "operator capability text is invalid" if result.empty? || result.length > limit

      result
    end

    def list(value, count, limit)
      values = Array(value)
      raise RuntimeError, "operator capability list is too large" if values.length > count

      values.map { |item| text(item, limit) }
    end
  end
end
