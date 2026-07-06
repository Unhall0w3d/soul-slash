# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module SoulCore
  class TaskLog
    def initialize(root: "Soul/logs/tasks")
      @root = root
      FileUtils.mkdir_p(@root)
    end

    def write(kind:, payload:)
      timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
      safe_kind = kind.gsub(/[^a-zA-Z0-9_.-]/, "_")
      path = File.join(@root, "#{timestamp}-#{safe_kind}.json")
      File.write(path, JSON.pretty_generate(payload))
      path
    end
  end
end
