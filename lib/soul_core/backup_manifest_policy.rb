# frozen_string_literal: true

module SoulCore
  class BackupManifestPolicy
    def initialize(root: Dir.pwd, home: Dir.home)
      @root = File.expand_path(root)
      @home = File.expand_path(home)
    end

    def sources
      source_candidates.map { |path| File.expand_path(path) }.uniq.select do |path|
        File.exist?(path) && !File.symlink?(path) && File.readable?(path)
      end.sort
    end

    def exclusions
      [
        "*.lock", "*.part", "*.tmp", ".DS_Store", "__pycache__", ".pytest_cache",
        "#{File.join(@root, "Soul", "private", "backup", "restores")}/**",
        "#{File.join(@root, "Soul", "private", "creative-inspection")}/**",
        "#{File.join(@root, "Soul", "private", "host_maintenance", "checkupdates_db")}/**",
        "#{File.join(@root, "Soul", "private", "perception", "screen_capture")}/**",
        "#{File.join(@root, "Soul", "private", "perception", "staging")}/**",
        "#{File.join(@root, "Soul", "runtime", "approvals")}/**",
        "#{File.join(@root, "Soul", "runtime", "dashboard_auth", "sessions")}/**",
        "#{File.join(@root, "Soul", "runtime")}/**/approval_tokens/**",
        "#{File.join(@root, "Soul", "runtime", "model_runtime", "leases")}/**",
        "#{File.join(@root, "Soul", "runtime", "music")}/**"
      ].sort
    end

    private

    def source_candidates
      [
        File.join(@root, ".env"),
        File.join(@root, "Soul", "private"),
        File.join(@root, "Soul", "config", "cloud_providers.yaml"),
        File.join(@root, "Soul", "config", "model_runtime_profiles.local.yaml"),
        *%w[memory artifacts identity improvement host_improvement proposals reflection workflows logs].map { |name| File.join(@root, "Soul", name) },
        File.join(@root, "Soul", "augmentation", "proposals"),
        File.join(@root, "Soul", "augmentation", "experiments"),
        *%w[application artifact_inbox chats conversation_evidence conversation_state creative_flows executions exports youtube_auth youtube_description_sync].map { |name| File.join(@root, "Soul", "runtime", name) },
        File.join(@root, "Soul", "runtime", "dashboard_auth", "credentials.json"),
        File.join(@root, "Soul", "runtime", "model_runtime", "core_selection.json"),
        File.join(@root, "Soul", "runtime", "model_runtime", "selected_profile.json"),
        File.join(@root, "Soul", "music", "jobs"),
        File.join(@root, "Soul", "music", "projects"),
        File.join(@root, "Soul", "music", "references"),
        File.join(@root, "Soul", "visual", "projects"),
        File.join(@home, "Music", "soul-music"),
        File.join(@home, "Knowledge", "soul-vault"),
        File.join(@home, ".config", "soul"),
        File.join(@home, ".local", "share", "soul", "blender-visual", "runs"),
        File.join(@home, ".local", "share", "soul", "music", "vulkan-pilot-runs"),
        File.join(@home, ".local", "share", "soul", "visual-motion", "runs"),
        *Dir.glob(File.join(@home, ".config", "systemd", "user", "soul-*.service")).sort,
        File.join(@home, ".local", "share", "caddy")
      ]
    end
  end
end
