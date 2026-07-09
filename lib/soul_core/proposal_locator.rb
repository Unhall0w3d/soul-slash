# frozen_string_literal: true

require "json"

module SoulCore
  class ProposalLocator
    DEFAULT_ROOT = "Soul/improvement/proposals"

    def initialize(root: Dir.pwd, proposals_root: DEFAULT_ROOT)
      @root = File.expand_path(root)
      @proposals_root = File.expand_path(File.join(@root, proposals_root))
    end

    def latest
      proposal_dirs.first
    end

    def by_rank(rank)
      proposal_dirs.find do |dir|
        metadata = read_metadata(dir)
        metadata && metadata["rank"].to_i == rank.to_i
      end
    end

    def all
      proposal_dirs
    end

    private

    def proposal_dirs
      return [] unless Dir.exist?(@proposals_root)

      Dir.glob(File.join(@proposals_root, "*"))
         .select { |path| File.directory?(path) && File.exist?(File.join(path, "metadata.json")) }
         .sort_by { |path| File.basename(path) }
         .reverse
    end

    def read_metadata(dir)
      JSON.parse(File.read(File.join(dir, "metadata.json")))
    rescue StandardError
      nil
    end
  end
end
