# frozen_string_literal: true

require_relative "config"
require_relative "retrieval"

module SoulCore
  module ContinuityLab
    module Actions
      ID = /\A[A-Za-z0-9][A-Za-z0-9_-]{0,63}\z/

      def self.valid_id?(id)
        id.is_a?(String) && id.encoding.ascii_compatible? && id.valid_encoding? && id.ascii_only? && id.match?(ID)
      end

      def self.parse(raw, config)
        return {} unless raw.is_a?(String) && raw.encoding.ascii_compatible? && raw.valid_encoding? && raw.bytesize <= config["max_response_bytes"]
        action = ContinuityLab.parse(raw)
        return {} unless action.is_a?(Hash)
        return {} if config.direct_evidence? && action["action"] != "reply"
        case action["action"]
        when "reply"
          return {} unless action.keys.sort == %w[action content] && action["content"].is_a?(String)
        when "wait"
          return {} unless action.keys == ["action"]
        when "tool"
          return {} unless action.keys.sort == %w[action arguments tool]
          args = action["arguments"]
          case action["tool"]
          when "note.write", "note.tombstone"
            tombstone = action["tool"] == "note.tombstone"
            return {} if tombstone && config["context_mode"] != "explicit_v1"
            fields = tombstone ? %w[expected_revision note_id] : %w[content expected_revision note_id]
            return {} unless args.is_a?(Hash) && args.keys.sort == fields && valid_id?(args["note_id"]) &&
                             args["expected_revision"].is_a?(Integer) && args["expected_revision"] >= 0
            return {} unless tombstone || (args["content"].is_a?(String) && args["content"].bytesize <= config["max_note_bytes"])
          when "search", "read"
            return {} unless config["context_mode"] == "explicit_v1" && Retrieval.valid_arguments?(action["tool"], args)
          else
            return {}
          end
        else
          return {}
        end
        action
      rescue JSON::ParserError, JSON::NestingError
        {}
      end

      def self.tool_result(state, action, config, event_id)
        raise ValidationError, "direct evidence profile has no tools" if config.direct_evidence?
        case action.fetch("tool")
        when "note.write" then note_result(state.fetch("notes"), action.fetch("arguments"), config)
        when "note.tombstone" then note_result(state.fetch("notes"), action.fetch("arguments"), config, tombstone: true)
        else
          { "result" => Retrieval.result(state, action.fetch("tool"), action.fetch("arguments"), event_id, config: config) }
        end
      end

      # Reconstructed from committed evidence, including after interrupted runs.
      # Only consecutive, semantically equal failed tool calls stop this event.
      def self.repeated_failure?(event, config)
        return false unless config.repeated_failure_guard? && event.fetch("calls").length >= 2
        previous, current = event.fetch("calls").last(2)
        first = parse(previous["response"], config)
        second = parse(current["response"], config)
        first["action"] == "tool" && first == second &&
          previous.dig("result", "ok") == false && current.dig("result", "ok") == false &&
          previous.dig("result", "reason").is_a?(String) &&
          previous.dig("result", "reason") == current.dig("result", "reason")
      end

      def self.note_result(notes, args, config, tombstone: false)
        previous = notes[args.fetch("note_id")]
        return { "result" => { "ok" => false, "reason" => "not_found" } } if tombstone && !previous
        content = tombstone ? "" : args.fetch("content")
        revision = previous ? previous.fetch("revision") : 0
        reason = if revision != args.fetch("expected_revision")
                   "revision_conflict"
                 elsif !previous && notes.length >= config["max_notes"]
                   "note_count_quota"
                 elsif notes.values.sum { |note| note["content"].bytesize } - (previous ? previous["content"].bytesize : 0) + content.bytesize > config["max_total_note_bytes"]
                   "note_bytes_quota"
                 end
        return { "result" => { "ok" => false, "reason" => reason } } if reason

        { "note" => { "note_id" => args.fetch("note_id"), "revision" => revision + 1, "parent_revision" => revision,
                      "content" => content, "content_digest" => Digest::SHA256.hexdigest(content),
                      "tombstone" => tombstone, "provenance" => "unverified_model_note" },
          "result" => { "ok" => true, "note_id" => args.fetch("note_id"), "revision" => revision + 1 } }
      end
    end
  end
end
