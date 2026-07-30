# Temper NixOS deployment

This directory contains the portable part of Soul's NixOS maintenance
laboratory. It deliberately excludes LAN addresses, SSH keys, SSH host keys,
Proxmox IDs, and owner-private fleet records.

## Reference VM

The accepted reference deployment uses:

- NixOS 26.05 minimal x86_64 ISO;
- QEMU/KVM with Q35, two vCPUs, 4 GiB memory, and a 32 GiB SCSI disk;
- VirtIO networking;
- QEMU guest agent;
- a BIOS boot partition plus an ext4 root;
- a flake pinned to `github:NixOS/nixpkgs/nixos-26.05`; and
- key-only SSH for a locked-password `soul-maintenance` user.

The host configuration must import `./soul-maintenance.nix`, include
`qemu-guest.nix`, enable OpenSSH and `services.qemuGuest`, and define the
dedicated account:

```nix
{
  imports = [
    ./soul-maintenance.nix
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  services.qemuGuest.enable = true;

  users.mutableUsers = false;
  users.users.soul-maintenance = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPassword = "!";
    openssh.authorizedKeys.keys = [
      "REPLACE_WITH_ONE_REVIEWED_PUBLIC_KEY"
    ];
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.autoUpgrade.enable = false;
  nix.gc.automatic = false;
}
```

Copy `soul-maintenance.nix` and `soul-nixos-maintenance` beside the host's
`configuration.nix`, then rebuild the pinned flake. Verify the generated sudo
policy before enabling Soul's local Temper control setting:

```text
sudo -n /run/current-system/sw/bin/soul-nixos-maintenance self-check
sudo -n /run/current-system/sw/bin/soul-nixos-maintenance generation-match
```

An invalid operation and a generic command such as `sudo -n true` must both be
rejected. Establish the SSH host-key trust independently, add one exact
literal `Host temper` entry, enroll it through Guided Maintenance, and only
then opt into control through ignored `.env` settings.

Run `make verify-nixos-maintenance` before deployment or review.
