{ config, lib, pkgs, ... }:

let
  helper = pkgs.writeShellApplication {
    name = "soul-nixos-maintenance";
    runtimeInputs = with pkgs; [
      coreutils
      nix
      nixos-rebuild
      systemd
    ];
    text = builtins.readFile ./soul-nixos-maintenance;
  };
  fixedCommands = map (operation: {
    command = "/run/current-system/sw/bin/soul-nixos-maintenance ${operation}";
    options = [ "NOPASSWD" ];
  }) [
    "self-check"
    "generation-match"
    "upgrade"
    "reboot"
  ];
in
{
  environment.systemPackages = [ helper ];

  security.sudo.extraRules = [
    {
      users = [ "soul-maintenance" ];
      runAs = "root";
      commands = fixedCommands;
    }
  ];

  assertions = [
    {
      assertion = lib.hasAttrByPath [ "users" "users" "soul-maintenance" ] config;
      message = "Soul's NixOS maintenance module requires users.users.soul-maintenance.";
    }
  ];
}
