# frozen_string_literal: true

require "digest"
require "pathname"
require "time"

module SoulCore
  class ConversationArtifactContract
    KINDS = %w[
      document report code overlay package dataset spreadsheet presentation
      research_notes implementation_plan other
    ].freeze

    PRIVACY_CLASSES = %w[local_private project public].freeze
    LIFECYCLE_STATES = %w[active archived].freeze
    SOURCE_KINDS = %w[user model skill provider import manual_registration].freeze

    BLOCKED_PATH_PATTERNS = [
      /\A\.git(?:\/|\z)/,
      /\A\.env(?:\.|\z)/,
      /\A(?:.*\/)?\.ssh(?:\/|\z)/,
      /\A(?:.*\/)?(?:id_rsa|id_ed25519|[^\/]+\.(?:pem|key|p12|pfx))\z/i,
      /\ASoul\/(?:memory|identity|runtime|approvals)(?:\/|\z)/,
      /\ASoul\/artifacts\/conversation_artifacts\.jsonl\z/,
      /\A(?:logs|run)(?:\/|\z)/
    ].freeze

    class << self
      def normalize_kind(value, path: nil)
        candidate = value.to_s.strip.downcase.tr(" -", "_")
        candidate = infer_kind(path) if candidate.empty?
        KINDS.include?(candidate) ? candidate : "other"
      end

      def normalize_privacy(value)
        candidate = value.to_s.strip.downcase
        candidate = "project" if candidate.empty?
        raise ArgumentError, "Unsupported artifact privacy class: #{candidate}" unless PRIVACY_CLASSES.include?(candidate)

        candidate
      end

      def provider_allowed?(artifact_privacy, provider_privacy)
        case normalize_privacy(artifact_privacy)
        when "local_private" then provider_privacy.to_s == "local_only"
        when "project" then %w[local_only local_network].include?(provider_privacy.to_s)
        when "public" then %w[local_only local_network cloud].include?(provider_privacy.to_s)
        else false
        end
      end

      def normalize_source(source)
        data = stringify_keys(source || {})
        kind = data.fetch("kind", "manual_registration").to_s
        raise ArgumentError, "Unsupported artifact source kind: #{kind}" unless SOURCE_KINDS.include?(kind)

        {
          "kind" => kind,
          "reference" => data["reference"].to_s,
          "provider_id" => blank_to_nil(data["provider_id"]),
          "skill_id" => blank_to_nil(data["skill_id"]),
          "chat_id" => blank_to_nil(data["chat_id"])
        }.compact
      end

      def resolve_project_file(root:, path:)
        root_path = Pathname.new(File.expand_path(root)).realpath
        raw = path.to_s.strip
        raise ArgumentError, "Artifact path must not be empty" if raw.empty?
        raise ArgumentError, "Artifact path contains a null byte" if raw.include?("\0")

        candidate = Pathname.new(raw)
        candidate = root_path.join(candidate) unless candidate.absolute?
        expanded = Pathname.new(File.expand_path(candidate.to_s))
        raise ArgumentError, "Artifact path must remain inside the project root" unless inside_root?(expanded, root_path)
        raise ArgumentError, "Artifact path must not be a symbolic link" if File.symlink?(expanded)
        raise ArgumentError, "Artifact path must identify an existing regular file" unless File.file?(expanded)

        real = expanded.realpath
        raise ArgumentError, "Artifact path resolves outside the project root" unless inside_root?(real, root_path)

        relative = real.relative_path_from(root_path).to_s
        raise ArgumentError, "Artifact path is reserved local state" if blocked_relative_path?(relative)

        measured = measure_regular_file(real)
        {
          "absolute_path" => real.to_s,
          "relative_path" => relative,
          "size_bytes" => measured.fetch("size_bytes"),
          "sha256" => measured.fetch("sha256"),
          "media_type" => media_type(relative)
        }
      end

      def infer_kind(path)
        value = path.to_s.downcase
        return "overlay" if value.end_with?(".zip") && value.include?("overlay")
        return "package" if value.end_with?(".zip", ".tar", ".tar.gz", ".tgz")
        return "spreadsheet" if value.end_with?(".csv", ".xlsx", ".ods")
        return "presentation" if value.end_with?(".pptx", ".odp")
        return "code" if value.end_with?(".rb", ".py", ".sh", ".js", ".ts", ".go", ".rs")
        return "report" if value.include?("report") || value.include?("assessment")
        return "document" if value.end_with?(".md", ".txt", ".docx", ".pdf")

        "other"
      end

      def media_type(path)
        case File.extname(path.to_s).downcase
        when ".md" then "text/markdown"
        when ".txt", ".log" then "text/plain"
        when ".json" then "application/json"
        when ".csv" then "text/csv"
        when ".rb", ".py", ".sh", ".zsh", ".bash", ".js", ".mjs", ".cjs", ".ts", ".tsx", ".jsx",
             ".go", ".rs", ".java", ".c", ".h", ".cc", ".cpp", ".hpp", ".yaml", ".yml", ".toml",
             ".ini", ".conf", ".sql", ".xml", ".html", ".css" then "text/plain"
        when ".zip" then "application/zip"
        when ".pdf" then "application/pdf"
        when ".docx" then "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        when ".xlsx" then "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        when ".pptx" then "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        else "application/octet-stream"
        end
      end

      def blocked_relative_path?(relative)
        normalized = relative.to_s.tr("\\", "/")
        BLOCKED_PATH_PATTERNS.any? { |pattern| normalized.match?(pattern) }
      end

      private

      def measure_regular_file(path)
        raise RuntimeError, "This platform cannot enforce no-follow artifact registration" unless File.const_defined?(:NOFOLLOW)

        digest = Digest::SHA256.new
        size = 0
        File.open(path.to_s, File::RDONLY | File::NOFOLLOW) do |file|
          stat = file.stat
          raise ArgumentError, "Artifact path must identify a regular file" unless stat.file?
          current = File.stat(path)
          unless current.dev == stat.dev && current.ino == stat.ino
            raise RuntimeError, "Artifact path changed during registration"
          end

          while (chunk = file.read(64 * 1024))
            digest.update(chunk)
            size += chunk.bytesize
          end

          final = File.stat(path)
          unless final.dev == stat.dev && final.ino == stat.ino && final.size == size
            raise RuntimeError, "Artifact path changed during registration"
          end
        end
        { "size_bytes" => size, "sha256" => digest.hexdigest }
      rescue Errno::ENOENT, Errno::ELOOP, Errno::EACCES => error
        raise ArgumentError, "Artifact cannot be opened safely: #{error.class}"
      end

      def inside_root?(candidate, root)
        candidate_string = candidate.to_s
        root_string = root.to_s
        candidate_string == root_string || candidate_string.start_with?(root_string + File::SEPARATOR)
      end

      def stringify_keys(hash)
        hash.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
      end

      def blank_to_nil(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end
    end
  end
end
