# frozen_string_literal: true

require_relative "actions"
require_relative "direct_evidence"
require "strscan"

module SoulCore
  module ContinuityLab
    # A pure computation over caller-selected evidence and an explicit contract.
    # No natural-language intent inference, I/O, model authority, or memory writes.
    module VerifiedSelection
      VERSION = "source_verified_selection_v1"
      SCOPE = "computation_over_supplied_source_and_explicit_request_only"
      NUMBER = /(?:0|[1-9][0-9]{0,8})(?:\.[0-9]{1,6})?/
      REFERENCE_FIELDS = %w[lineage_id id revision content_digest].freeze
      MAX_INPUT_BYTES = 32_768
      MAX_EXPLANATION_BYTES = 4096
      # Fixed grammar, not caller-supplied regular expressions or field mappings.
      ATTRIBUTES = [
        [/\A(#{NUMBER}) shelves\z/, "shelves", "count", 1, true],
        [/\A(#{NUMBER}) crowns\z/, "price", "crowns", 1, false],
        [/\A(#{NUMBER}) credits\z/, "price", "credits", 1, false],
        [/\A(#{NUMBER}) watts\z/, "power", "W", 1, false],
        [/\A(#{NUMBER}) cubic meters per hour\z/, "airflow", "m3/h", 1, false],
        [/\A(#{NUMBER}) decibels\z/, "noise", "dB", 1, false],
        [/\A(#{NUMBER}) hours\z/, "runtime", "h", 1, false],
        [/\A(#{NUMBER}) minutes\z/, "runtime", "h", Rational(1, 60), false],
        [/\A(#{NUMBER}) kilowatt-hours\z/, "capacity", "kWh", 1, false],
        [/\A(#{NUMBER}) watt-hours\z/, "capacity", "kWh", Rational(1, 1000), false],
        [/\Aheight (#{NUMBER}) centimeters\z/, "height", "cm", 1, false],
        [/\Aheight (#{NUMBER}) meters\z/, "height", "cm", 100, false],
        [/\A(#{NUMBER}) pages per minute\z/, "speed", "pages/min", 1, false],
        [/\A(#{NUMBER}) drive bays\z/, "bays", "count", 1, true],
        [/\Asetup (#{NUMBER}) minutes\z/, "setup", "min", 1, false],
        [/\Asetup (#{NUMBER}) hours\z/, "setup", "min", 60, false]
      ].map(&:freeze).freeze

      class Refusal < StandardError; end

      def self.refused(reason)
        { "version" => VERSION, "state" => "awaiting_input", "reason" => reason,
          "verification_scope" => SCOPE }
      end

      def self.evaluate(source:, request:, proposal: nil)
        validate_source!(source)
        options = parse_catalog(source.fetch("text"))
        validate_request!(request, source, options.first.fetch("values"))
        verify_proposal!(proposal, options) unless proposal.nil?

        options.each do |option|
          failed = request.fetch("constraints").each_index.reject do |index|
            constraint_matches?(option.fetch("values"), request.fetch("constraints")[index])
          end
          option["eligible"] = failed.empty?
          option["failed_constraints"] = failed
        end
        eligible = options.select { |option| option.fetch("eligible") }
        objective = request.fetch("objective")
        field = objective.fetch("field")
        values = eligible.map { |option| numeric(option.fetch("values").fetch(field).fetch("value")) }
        best = objective.fetch("direction") == "min" ? values.min : values.max
        winners = eligible.select { |option| numeric(option.fetch("values").fetch(field).fetch("value")) == best }
        result = {
          "version" => VERSION, "state" => "complete",
          "reason" => winners.empty? ? "none_eligible" : winners.length == 1 ? "selected" : "tie",
          "verification_scope" => SCOPE, "source_ref" => reference(source),
          "request_digest" => ContinuityLab.digest(request), "request" => request,
          "options" => options, "winners" => winners.map { |option| option.fetch("option") },
          "objective" => objective.merge("unit" => options.first.fetch("values").fetch(field).fetch("unit"),
            "value" => best && decimal(best)), "proposal_verified" => !proposal.nil?
        }
        if request.key?("totals")
          totals = request.fetch("totals")
          result["totals"] = winners.map do |winner|
            { "option" => winner.fetch("option"), "quantity" => totals.fetch("quantity"),
              "values" => totals.fetch("fields").to_h do |name|
                value = winner.fetch("values").fetch(name)
                [name, { "value" => decimal(numeric(value.fetch("value")) * totals.fetch("quantity")),
                         "unit" => value.fetch("unit") }]
              end }
          end
          result["totals_scope"] = "scalar_product_not_physical_capacity_or_bundle_optimization"
        end
        # Detach returned request/metadata strings from caller-owned objects.
        ContinuityLab.parse(ContinuityLab.encode(result))
      rescue Refusal => error
        refused(error.message)
      end

      def self.present(source:, request:, proposal: nil, explanation: nil)
        unless explanation.nil? || utf8?(explanation, MAX_EXPLANATION_BYTES)
          return { "verified_result" => refused("invalid_explanation"), "generated_explanation" => nil }
        end
        { "verified_result" => evaluate(source: source, request: request, proposal: proposal),
          "generated_explanation" => explanation && { "status" => "unverified_model_text", "text" => explanation.dup } }
      end

      def self.reference(source)
        REFERENCE_FIELDS.to_h { |field| [field, source.fetch(field)] }
      end

      def self.keys?(value, required, optional = [])
        value.is_a?(Hash) && (required - value.keys).empty? && (value.keys - required - optional).empty?
      end

      def self.utf8?(value, max)
        value.is_a?(String) && value.encoding == Encoding::UTF_8 && value.valid_encoding? && value.bytesize <= max
      end

      def self.validate_source!(source)
        valid = keys?(source, DirectEvidence::FIELDS) &&
          utf8?(source["lineage_id"], 32) && source["lineage_id"].match?(/\A[a-f0-9]{32}\z/) &&
          source["collection"] == "corpus" && Actions.valid_id?(source["id"]) &&
          source["revision"].is_a?(Integer) && source["revision"].between?(1, 2_147_483_647) &&
          source["provenance"] == "operator_selected_source_not_authority" &&
          utf8?(source["text"], 8192) && source["span"].is_a?(Array) &&
          source["span"].all? { |offset| offset.is_a?(Integer) } && source["span"] == [0, source["text"].length] &&
          source["content_digest"] == Digest::SHA256.hexdigest(source["text"])
        raise Refusal, "invalid_source_binding" unless valid
      end

      def self.parse_catalog(text)
        raise Refusal, "unsupported_catalog" unless text.ascii_only?
        scanner = StringScanner.new(text)
        raise Refusal, "unsupported_catalog" unless scanner.scan(/[A-Za-z][A-Za-z0-9 -]{0,95} catalog\.\s*/)
        options = []
        until scanner.eos?
          raise Refusal, "option_limit" if options.length >= 32
          label = scanner.scan(/[A-Za-z][A-Za-z0-9 -]{0,63}(?=:)/)
          raise Refusal, "unsupported_catalog" unless label && label == label.strip && scanner.scan(/:\s*/)
          start = scanner.pos
          body = scanner.scan(/.*?\.(?=\s|\z)/m)
          raise Refusal, "unsupported_catalog" unless body
          body = body[0...-1]
          pieces = body.split(",", -1)
          raise Refusal, "field_limit" unless pieces.length.between?(1, 12)
          offset = 0
          attributes = pieces.to_h do |piece|
            quote = piece.strip
            position = start + offset + (piece.index(/\S/) || 0)
            offset += piece.length + 1
            name, value, unit = parse_attribute(quote)
            [name, { "value" => value, "unit" => unit,
                     "evidence" => { "span" => [position, position + quote.length], "quote" => quote } }]
          end
          raise Refusal, "duplicate_field" unless attributes.length == pieces.length
          options << { "option" => label, "values" => attributes }
          scanner.skip(/\s*/)
        end
        raise Refusal, "empty_catalog" if options.empty?
        raise Refusal, "duplicate_option" unless options.map { |o| o.fetch("option").downcase }.uniq.length == options.length
        schemas = options.map { |o| o.fetch("values").transform_values { |v| v.fetch("unit") } }
        raise Refusal, "inconsistent_catalog_schema" unless schemas.all? { |schema| schema == schemas.first }
        options
      end

      def self.parse_attribute(quote)
        return ["stock", quote == "in stock", "boolean"] if ["in stock", "out of stock"].include?(quote)
        ATTRIBUTES.each do |pattern, name, unit, factor, count|
          match = pattern.match(quote)
          next unless match
          value = Rational(match[1]) * factor
          raise Refusal, "fractional_count" if count && value.denominator != 1
          return [name, decimal(value), unit]
        end
        raise Refusal, "unsupported_attribute"
      end

      def self.validate_request!(request, source, fields)
        unless keys?(request, %w[version source_ref constraints objective], %w[totals]) &&
               request["version"] == "selection_request_v1" && keys?(request["source_ref"], REFERENCE_FIELDS) &&
               request["source_ref"]["revision"].is_a?(Integer) && request["source_ref"] == reference(source)
          raise Refusal, "invalid_request_binding"
        end
        constraints = request["constraints"]
        raise Refusal, "invalid_constraints" unless constraints.is_a?(Array) && constraints.length <= 8
        constraints.each do |constraint|
          unless keys?(constraint, %w[field op value unit]) && fields.key?(constraint["field"]) &&
                 %w[gte lte eq].include?(constraint["op"]) && constraint["unit"] == fields[constraint["field"]]["unit"]
            raise Refusal, "invalid_constraint"
          end
          if constraint["unit"] == "boolean"
            raise Refusal, "invalid_constraint" unless constraint["op"] == "eq" && [true, false].include?(constraint["value"])
          else
            request_number!(constraint["value"])
          end
        end
        raise Refusal, "duplicate_constraint" unless constraints.map { |c| [c["field"], c["op"]] }.uniq.length == constraints.length
        constraints.group_by { |c| c["field"] }.each_value do |group|
          next if group.first["unit"] == "boolean"
          lower = group.find { |c| c["op"] == "gte" }; upper = group.find { |c| c["op"] == "lte" }
          exact = group.find { |c| c["op"] == "eq" }
          low = lower && numeric(lower["value"]); high = upper && numeric(upper["value"])
          equal = exact && numeric(exact["value"])
          if (low && high && low > high) || (equal && ((low && equal < low) || (high && equal > high)))
            raise Refusal, "contradictory_constraints"
          end
        end
        objective = request["objective"]
        unless keys?(objective, %w[field direction]) && %w[min max].include?(objective["direction"]) &&
               fields.key?(objective["field"]) && fields[objective["field"]]["unit"] != "boolean"
          raise Refusal, "invalid_objective"
        end
        return unless request.key?("totals")
        totals = request["totals"]
        unless keys?(totals, %w[quantity fields]) && totals["quantity"].is_a?(Integer) &&
               totals["quantity"].between?(1, 1_000_000) && totals["fields"].is_a?(Array) &&
               totals["fields"].length.between?(1, 12) && totals["fields"].uniq == totals["fields"] &&
               totals["fields"].all? { |name| fields.key?(name) && fields[name]["unit"] != "boolean" }
          raise Refusal, "invalid_totals"
        end
      end

      def self.request_number!(value)
        raise Refusal, "invalid_number" unless value.is_a?(String) && value.ascii_only? && value.match?(/\A#{NUMBER}\z/)
      end

      def self.verify_proposal!(proposal, options)
        unless proposal.is_a?(Array) && proposal.length == options.length && proposal.all? do |row|
                 keys?(row, %w[option values]) && row["option"].is_a?(String) && row["values"].is_a?(Hash)
               end
          raise Refusal, "proposal_mismatch"
        end
        expected = options.to_h do |option|
          [option.fetch("option"), option.fetch("values").transform_values { |v| v.slice("value", "unit") }]
        end
        actual = proposal.to_h { |row| [row.fetch("option"), row.fetch("values")] }
        raise Refusal, "proposal_mismatch" unless actual.length == proposal.length && actual == expected
      end

      def self.constraint_matches?(fields, constraint)
        value = fields.fetch(constraint.fetch("field")).fetch("value")
        return value == constraint.fetch("value") if constraint.fetch("unit") == "boolean"
        left = numeric(value); right = numeric(constraint.fetch("value"))
        case constraint.fetch("op")
        when "gte" then left >= right
        when "lte" then left <= right
        when "eq" then left == right
        end
      end

      def self.numeric(value) = Rational(value)

      def self.decimal(value)
        return value.numerator.to_s if value.denominator == 1
        denominator = value.denominator
        powers = [2, 5].map do |prime|
          count = 0
          while (denominator % prime).zero?
            denominator /= prime
            count += 1
          end
          count
        end
        return "#{value.numerator}/#{value.denominator}" unless denominator == 1
        scale = powers.max
        digits = (value.numerator * (10**scale) / value.denominator).to_s.rjust(scale + 1, "0")
        "#{digits[0...-scale]}.#{digits[-scale..]}".sub(/0+\z/, "")
      end

      private_class_method :keys?, :utf8?, :validate_source!, :parse_catalog, :parse_attribute,
        :validate_request!, :request_number!, :verify_proposal!, :constraint_matches?, :numeric, :decimal
    end
  end
end
