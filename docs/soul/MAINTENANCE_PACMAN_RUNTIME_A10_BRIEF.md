# Maintenance Pacman Runtime A10 Brief

```text
date: 2026-07-30
human_authorization: requested in the active development conversation
implementation_authorized: yes
risk: Class 1 bounded read-only package-status refresh
```

## Outcome

Repair Atelier's fresh official-repository package count inside the hardened
Dashboard service while retaining a separate AUR-only count.

## Root cause

A9 used the distribution `checkupdates` wrapper. Soul's Dashboard runs with
`PrivateTmp=true`, `ProtectSystem=strict`, and `UMask=0077`. Pacman's configured
unprivileged `alpm` downloader cannot change ownership inside that user-service
temporary mount, so `checkupdates` exits `1` before fetching metadata.

## Contract

- Official repository updates use a new temporary database created with
  `Dir.mktmpdir`.
- The installed package database is represented only by a symlink to
  `/var/lib/pacman/local`.
- One bounded `fakeroot pacman -Sy` targets only that temporary database,
  passes `--disable-sandbox`, and writes no pacman log.
- `--disable-sandbox` disables pacman's inner downloader sandbox only because
  the entire command already runs inside Soul's stricter outer systemd
  namespace. It does not weaken the Dashboard unit.
- One subsequent `pacman -Qu --dbpath <temporary>` supplies the official
  repository count.
- The temporary database is deleted when the foreground block terminates.
- `yay -Qua` remains the AUR-only query. Its rows are never added to the
  official pacman count.
- Flatpak remains a separately assessed channel.
- Missing temporary-sync tooling may fall back to cached `pacman -Qu` evidence
  with an explicit cached label.
- A failed fresh sync remains unavailable and must not silently substitute
  cached evidence.

## Bounds

- One official metadata sync, at most 90 seconds.
- One official update query, at most 20 seconds.
- One AUR-only query, at most 30 seconds.
- Existing 256 KiB output cap per command.
- No retry, polling, background worker, privilege prompt, package download, or
  installation.

## Prohibited

- synchronizing pacman's live `/var/lib/pacman` sync database;
- `pacman -Syy`, `yay -Sy`, or `yay -Syy`;
- omitting `--dbpath` from the isolated `pacman -Sy` command;
- merging official and AUR counts;
- sudo, package mutation, or changes to the Dashboard systemd sandbox.

## Acceptance

- [x] Root cause reproduced inside the exact Dashboard systemd sandbox.
- [x] Isolated sync and query pass inside that sandbox.
- [x] Official pacman, AUR, and Flatpak counts remain independent.
- [x] The live pacman database is never a sync target.
- [x] Temporary metadata is removed after the query.
- [x] Missing-tool fallback and failed-sync behavior are deterministic.
- [ ] Operator confirms normal Dashboard Refresh no longer shows pacman
  unavailable.
