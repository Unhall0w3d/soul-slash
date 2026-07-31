# frozen_string_literal: true

require "json"

module SoulCore
  class OperatorBackupManifestPolicy
    PROFILE_ID = "operator"
    SNAPSHOT_TAG = "operator-state"
    ASSET_MANIFEST = File.join("config", "operator_recovery_assets.json")

    USER_DATA_DIRECTORIES = %w[
      Anbernic
      ComSource
      Desktop
      Documents
      Knowledge
      Music
      Obsidian
      OneDrive
      Pictures
      Projects
      Public
      PyCharmMiscProject
      PycharmProjects
      Scripts
      Servers
      Templates
      Tools
      Videos
    ].freeze

    CONFIG_DIRECTORIES = %w[
      MangoHud
      SoulSlash
      alacritty
      autostart
      btop
      cachyos
      dconf
      fastfetch
      fish
      gh
      goverlay
      gtk-3.0
      gtk-4.0
      hypr
      kitty
      lact
      libfm
      micro
      mpv
      noctalia
      obsidian
      pcmanfm
      pipewire
      qBittorrent
      qt5ct
      qt6ct
      systemd
      uwsm
      vkSumi
      vlc
      winboat
      xsettingsd
      yay
    ].freeze

    CONFIG_FILES = %w[
      QtProject.conf
      arkrc
      baloofileinformationrc
      dolphinrc
      kdeglobals
      kiorc
      mimeapps.list
      trashrc
      user-dirs.dirs
      user-dirs.locale
    ].freeze

    HOME_FILES = %w[
      .bash_history
      .bash_logout
      .bash_profile
      .bashrc
      .gitconfig
      .p10k.zsh
      .profile
      .viminfo
      .zprofile
      .zsh_history
      .zshenv
      .zshrc
    ].freeze

    def initialize(root: Dir.pwd, home: Dir.home, system_root: "/")
      @root = File.expand_path(root)
      @home = File.expand_path(home)
      @system_root = File.expand_path(system_root)
    end

    def sources
      source_candidates.map { |path| File.expand_path(path) }.uniq.select do |path|
        File.exist?(path) && !File.symlink?(path) && File.readable?(path)
      end.sort
    end

    def exclusions
      [
        "*.lock", "*.part", "*.pid", "*.sock", "*.tmp", ".DS_Store",
        "**/.cache/**", "**/.gradle/**", "**/.mypy_cache/**",
        "**/.pytest_cache/**", "**/.ruff_cache/**", "**/.tox/**",
        "**/.venv/**", "**/__pycache__/**", "**/build/**", "**/dist/**",
        "**/node_modules/**", "**/target/**", "**/venv/**",
        File.join(@home, "Knowledge", "soul-vault", "**"),
        File.join(@home, "Music", "soul-music", "**"),
        File.join(@home, "Projects", "soul", "**"),
        File.join(@home, ".codex", "sessions", "**"),
        File.join(@home, ".local", "state", "noctalia", "clipboard", "**"),
        File.join(@home, ".local", "state", "noctalia", "notification_history_assets", "**"),
        File.join(@home, ".local", "state", "noctalia", "plugin-cache", "**"),
        File.join(@home, ".local", "state", "noctalia", "plugins", "**"),
        File.join(@home, ".local", "state", "noctalia", "screen_recorder", "**"),
        File.join(@home, ".winboat", "*.log"),
        File.join(@home, ".winboat", "oem", "*.exe"),
        File.join(@home, ".winboat", "oem", "*.zip")
      ].sort
    end

    def summary
      assets = recovery_assets
      {
        "profile_id" => PROFILE_ID,
        "snapshot_tag" => SNAPSHOT_TAG,
        "raw_model_weights_included" => false,
        "reproducible_asset_count" => assets.length,
        "reproducible_asset_bytes" => assets.sum { |asset| asset.fetch("bytes") },
        "reproducible_assets" => assets.map do |asset|
          asset.slice("filename", "bytes", "sha256", "repository", "revision")
        end,
        "explicit_manual_review_gaps" => [
          "browser profiles and session stores",
          "Downloads and recovered-file holding areas",
          "WinBoat container disk images",
          "root-only NetworkManager connection profiles",
          "cloud-synchronized password-vault contents"
        ]
      }
    end

    private

    def source_candidates
      candidates = USER_DATA_DIRECTORIES.map { |name| File.join(@home, name) }
      candidates.concat(CONFIG_DIRECTORIES.map { |name| File.join(@home, ".config", name) })
      candidates.concat(CONFIG_FILES.map { |name| File.join(@home, ".config", name) })
      candidates.concat(HOME_FILES.map { |name| File.join(@home, name) })
      candidates.concat([
        File.join(@home, ".codex", "AGENTS.md"),
        File.join(@home, ".codex", "auth.json"),
        File.join(@home, ".codex", "config.toml"),
        File.join(@home, ".codex", "agents"),
        File.join(@home, ".codex", "rules"),
        File.join(@home, ".codex", "skills"),
        File.join(@home, ".config", "VSCodium", "User"),
        File.join(@home, ".config", "credstore.encrypted"),
        File.join(@home, ".config", "vkBasalt", "vkBasalt.conf"),
        File.join(@home, ".cline", "data", "globalState.json"),
        File.join(@home, ".continue", ".continueignore"),
        File.join(@home, ".continue", ".continuerc.json"),
        File.join(@home, ".continue", "config.ts"),
        File.join(@home, ".continue", "config.yaml"),
        File.join(@home, ".gnupg"),
        File.join(@home, ".icons"),
        File.join(@home, ".pki"),
        File.join(@home, ".ssh"),
        File.join(@home, ".winboat"),
        File.join(@home, ".local", "bin"),
        File.join(@home, ".local", "share", "applications"),
        File.join(@home, ".local", "share", "flatpak"),
        File.join(@home, ".local", "share", "fonts"),
        File.join(@home, ".local", "share", "icons"),
        File.join(@home, ".local", "share", "keyrings"),
        File.join(@home, ".local", "share", "Larian Studios"),
        File.join(@home, ".local", "share", "qBittorrent", "BT_backup"),
        File.join(@home, ".local", "share", "qalculate"),
        File.join(@home, ".local", "share", "Steam", "userdata"),
        File.join(@home, ".local", "share", "user-places.xbel"),
        File.join(@home, ".local", "share", "vlc"),
        File.join(@home, ".local", "state", "noctalia"),
        File.join(@home, ".local", "state", "soul"),
        File.join(@home, ".local", "state", "wireplumber"),
        File.join(@home, ".var", "app", "dev.vencord.Vesktop", "config"),
        system_path("boot/limine.conf"),
        system_path("etc/fstab"),
        system_path("etc/hostname"),
        system_path("etc/hosts"),
        system_path("etc/kernel/cmdline"),
        system_path("etc/lact/config.yaml"),
        system_path("etc/mkinitcpio.conf"),
        system_path("etc/mkinitcpio.d"),
        system_path("etc/modprobe.d"),
        system_path("etc/modules-load.d"),
        system_path("etc/pacman.conf"),
        system_path("etc/pacman.d/hooks"),
        system_path("etc/systemd/system"),
        system_path("etc/sysctl.d"),
        system_path("etc/udev/rules.d"),
        system_path("var/lib/pacman/local")
      ])
      candidates
    end

    def system_path(relative)
      File.join(@system_root, relative)
    end

    def recovery_assets
      path = File.join(@root, ASSET_MANIFEST)
      return [] unless File.file?(path) && !File.symlink?(path) && File.size(path) <= 256 * 1024

      parsed = JSON.parse(File.binread(path))
      assets = parsed.fetch("assets")
      raise "operator recovery asset manifest is invalid" unless assets.is_a?(Array) && assets.length <= 64

      assets.map do |asset|
        raise "operator recovery asset entry is invalid" unless asset.is_a?(Hash)
        filename = asset.fetch("filename").to_s
        bytes = Integer(asset.fetch("bytes"))
        sha256 = asset.fetch("sha256").to_s
        repository = asset.fetch("repository").to_s
        revision = asset.fetch("revision", "main").to_s
        unless filename.match?(/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,199}\z/) &&
               bytes.positive? &&
               sha256.match?(/\A[a-f0-9]{64}\z/) &&
               repository.match?(/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/) &&
               revision.match?(/\A[A-Za-z0-9_.-]{1,128}\z/)
          raise "operator recovery asset entry is invalid"
        end
        {
          "filename" => filename,
          "bytes" => bytes,
          "sha256" => sha256,
          "repository" => repository,
          "revision" => revision
        }
      end
    rescue JSON::ParserError, KeyError, ArgumentError
      raise "operator recovery asset manifest is invalid"
    end
  end
end
