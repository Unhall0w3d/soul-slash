# Maintenance Package Freshness A9 Brief

```text
date: 2026-07-30
human_authorization: approved in the active development conversation
implementation_authorized: yes
risk: Class 1 bounded read-only package-status refresh
```

## Outcome

Make Atelier's per-device **Refresh** action query current pacman repository
metadata instead of merely rereading the host's existing sync database. Keep
the result truthful when a platform cannot safely refresh metadata through its
read-only status channel.

## Contract

- Atelier's pacman channel uses `/usr/bin/checkupdates --nocolor`.
- `checkupdates` may download current sync metadata only into its isolated
  temporary database. It must not change pacman's live sync database, install
  packages, invoke sudo, or create a partial-upgrade path.
- Exit `0` means available updates and exit `2` means a successful no-updates
  result.
- The command has a 90-second hard bound and the existing output cap.
- If `checkupdates` is not installed, Atelier may fall back to
  `/usr/bin/pacman -Qu`, but the evidence must remain explicitly labeled
  cached.
- If a present `checkupdates` command fails, the pacman channel is unavailable;
  stale cached evidence must not silently replace the failed fresh query.
- Atelier's existing AUR and Flatpak checks remain bounded and on-demand.
- DNF5's current on-demand query remains labeled fresh.
- APT status remains explicitly cached. Refreshing APT metadata requires a
  privileged `apt-get update` mutation and is not added to an ordinary
  read-only status click.

## Dashboard behavior

The update summary identifies fresh/live evidence as **fresh** and retained
APT or fallback pacman evidence as **cached metadata**. A count of zero still
means the corresponding query completed successfully.

## Prohibited

- `pacman -Sy`, `pacman -Syy`, `yay -Sy`, or `yay -Syy`;
- package installation or upgrade;
- sudo or broader remote maintenance authority;
- background refresh, polling, retry, or a new state store;
- presenting cached or failed evidence as fresh.

## Acceptance

- [x] Fresh pacman evidence uses `checkupdates`.
- [x] No-update exit `2` is accepted.
- [x] Missing tooling falls back explicitly to cached evidence.
- [x] Failed fresh evidence does not silently fall back.
- [x] Dashboard labels fresh and cached results.
- [x] Existing platform-specific channels and mutation gates remain unchanged.
- [x] One configured live Atelier backend refresh completed without manually
  synchronizing pacman's live database.
- [ ] Operator confirms the resulting fresh label and count in the Dashboard.
