# frozen_string_literal: true

require "base64"
require_relative "config"

module SoulCore
  module ContinuityLab
    # Native b9851 /completion SSE. Fragments are diagnostic data until a complete
    # stream returns terminal metadata; they are never parsed as executable actions.
    class QwenStreamResponse
      MAX_WIRE = 524_288
      MAX_CONTENT = 65_536
      MAX_EVENTS = 2048

      def initialize(on_progress:)
        @on_progress = on_progress
        @buffer, @data, @content = +"".b, [], +""
        @wire_bytes, @event_count = 0, 0
        @final = nil
      end

      def feed(chunk)
        raise ValidationError, "stream chunk is not bytes" unless chunk.is_a?(String)
        @wire_bytes += chunk.bytesize
        raise ValidationError, "stream wire budget exceeded" if @wire_bytes > MAX_WIRE
        @buffer << chunk.b
        while (offset = @buffer.index("\n"))
          line = @buffer.slice!(0..offset).delete_suffix("\n").delete_suffix("\r")
          if line.empty?
            dispatch_event unless @data.empty?
          elsif line.start_with?(":")
            next
          elsif line.start_with?("data:")
            raise ValidationError, "data after final stream event" if @final
            @data << line.delete_prefix("data:").delete_prefix(" ")
          else
            raise ValidationError, "unsupported stream field"
          end
        end
      end

      def finish
        raise ValidationError, "incomplete stream" unless @final && @buffer.empty? && @data.empty?
        @final.merge("content" => @content.dup)
      end

      def diagnostic
        { "partial_content" => @content.dup, "content_bytes" => @content.bytesize,
          "wire_bytes" => @wire_bytes, "event_count" => @event_count, "terminal_seen" => !@final.nil?,
          "pending_frame_base64" => Base64.strict_encode64((@data.join("\n") + @buffer).byteslice(0, 4096).to_s),
          "pending_frame_bytes" => @data.sum(&:bytesize) + @buffer.bytesize }
      end

      private

      def dispatch_event
        @event_count += 1
        raise ValidationError, "stream event budget exceeded" if @event_count > MAX_EVENTS
        text = @data.join("\n").force_encoding(Encoding::UTF_8)
        raise ValidationError, "invalid stream UTF-8" unless text.valid_encoding?
        row = ContinuityLab.parse(text)
        unless row.is_a?(Hash) && [true, false].include?(row["stop"]) && row["content"].is_a?(String) && !row.key?("error")
          raise ValidationError, "invalid native stream event"
        end
        raise ValidationError, "stream content budget exceeded" if @content.bytesize + row["content"].bytesize > MAX_CONTENT
        if row["stop"]
          # In this pinned server build, final content is empty: all text is in deltas.
          unless row["content"].empty? && row["tokens_evaluated"].is_a?(Integer) && row["tokens_evaluated"].positive? &&
                 row["tokens_predicted"].is_a?(Integer) && row["tokens_predicted"].between?(0, 768) && row["truncated"] == false
            raise ValidationError, "invalid stream terminal metadata"
          end
          @final = row
        else
          @content << row["content"]
        end
        @data.clear
        @on_progress.call({ "event_index" => @event_count - 1, "fragment" => row,
          "content_bytes" => @content.bytesize, "wire_bytes" => @wire_bytes })
      end
    end
  end
end
