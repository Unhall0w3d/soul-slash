# frozen_string_literal: true
module SoulCore
  # Owner-approved October 26 workday extension; exact UID/path pairs only.
  # This does not alter allocation limits or authorize other Electron clients.
  module DesktopGpuAllowances
    WORKDAY_PATHS = %w[/opt/Webex/bin/CiscoCollabHost /opt/Webex/bin/CiscoCollabHostCef /opt/teams-for-linux/teams-for-linux /opt/google/chrome/chrome /usr/bin/spectacle].freeze
    # Post-maintenance reboot: the historical capture had pre-update deleted
    # Plasma executables and an older Codex generation. Never glob runtime paths.
    # 2026-10-29: current Codex artifact runtime verified byte-for-byte against
    # the app-provided dependency bundle; prior exact generation replaced.
    REBOOT_PATHS = %w[
      /usr/bin/kwin_wayland
      /usr/bin/plasmashell
      /usr/lib/xdg-desktop-portal-kde
      /home/bhones/.config/Codex/artifact-sessions/runtime-generations/generation-0HlJhs/runtime/bin/node
    ].freeze
    def self.holders(uid: Process.uid)
      (WORKDAY_PATHS + REBOOT_PATHS + ["/usr/lib/kscreenlocker_greet"]).map { |path| [uid, path] }
    end
  end
end
