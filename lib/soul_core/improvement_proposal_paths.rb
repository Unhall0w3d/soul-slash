# frozen_string_literal: true

require "pathname"

module SoulCore
  module ImprovementProposalPaths
    DEFAULT_ROOT = "Soul/improvement/proposals"
    VERIFICATION_ROOT = "Soul/runtime/verification"
    ENV_KEY = "SOUL_IMPROVEMENT_PROPOSALS_ROOT"

    module_function

    def relative_root(root:, env: ENV, configured: nil)
      raw = configured.nil? ? env[ENV_KEY] : configured
      candidate = raw.to_s.strip
      candidate = DEFAULT_ROOT if candidate.empty?
      raise ArgumentError, "Improvement proposal root must be project-relative" if Pathname.new(candidate).absolute?

      normalized = Pathname.new(candidate).cleanpath.to_s
      allowed = normalized == DEFAULT_ROOT || normalized.start_with?("#{VERIFICATION_ROOT}/")
      raise ArgumentError, "Improvement proposal root override is restricted to #{VERIFICATION_ROOT}" unless allowed

      project_root = File.realpath(root)
      expanded = File.expand_path(normalized, project_root)
      unless expanded.start_with?(project_root + File::SEPARATOR)
        raise ArgumentError, "Improvement proposal root must remain inside the project root"
      end

      cursor = Pathname.new(expanded)
      project = Pathname.new(project_root)
      until cursor == project
        raise ArgumentError, "Improvement proposal root must not traverse a symbolic link" if File.symlink?(cursor)

        cursor = cursor.parent
      end

      normalized
    end
  end
end
