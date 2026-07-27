# Maintenance, Reboot, and Session Restore A1 Review

Status: candidate-complete; human review required

## Implementation summary

- added typed maintenance plan, rehearsal journal, window snapshot, and restore
  registry schemas;
- added a bounded read-only service that combines fresh package assessment,
  Flatpak installation-scope discovery, and structured Hyprland inventories;
- plans normal `yay -Syu` or explicitly selected `yay -Syyu` as inert argument
  arrays;
- plans system Flatpak update through the same future non-interactive sudo
  ticket so the one-authentication contract remains inspectable;
- omits window titles, URLs, raw process commands, terminal contents,
  environment values, and credentials from the snapshot;
- maps only exact allowlisted application identities with fixed absolute
  executable paths and bounded instance counts;
- detects allowlisted tray-only applications from process names alone and marks
  them `launch_if_absent` so normal autostart cannot be duplicated;
- exposes unsupported windows and missing executables instead of guessing;
- added a Dashboard preview and lifecycle rehearsal under Administration; and
- added Invocation Guide and Project Timeline metadata without adding Chat
  execution authority.

## Files changed

- `lib/soul_core/maintenance_rehearsal_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `config/maintenance_restore_registry.json`
- `config/invocation_catalog.yaml`
- `config/project_tracker_seed.json`
- `docs/soul/schemas/maintenance_*.schema.json`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `lib/soul_core/dashboard_capability_guide.rb`
- `lib/soul_core/voice_screen_understanding_service.rb`
- `scripts/verify-dashboard-self-improvement-navigation.rb`
- `scripts/verify-maintenance-rehearsal-a1.rb`
- `Makefile`
- `README.md`
- `docs/guides/SELF_ASSESSMENT.md`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/ROADMAP.md`
- `docs/soul/MAINTENANCE_REBOOT_RESTORE_A0_BRIEF.md`
- `docs/assessments/MAINTENANCE_REBOOT_RESTORE_A1_REVIEW.md`

## Commands run

```text
ruby -c lib/soul_core/maintenance_rehearsal_service.rb
ruby -c lib/soul_core/application_facade.rb
ruby -c lib/soul_core/application_contract.rb
node --check assets/dashboard/dashboard.js
ruby scripts/verify-maintenance-rehearsal-a1.rb
ruby scripts/verify-self-augmentation-host-improvement-a1-a3.rb
ruby scripts/verify-phase12d3-self-improvement-dashboard.rb
ruby scripts/verify-dashboard-self-improvement-navigation.rb
ruby scripts/verify-invocation-catalog-a1.rb
ruby scripts/verify-project-timeline-a1.rb
ruby scripts/verify-private-memory-separation.rb
```

The focused verifier and listed Self Assessment, navigation, invocation,
timeline, and private-state regressions pass. `git diff --check` and the
JavaScript syntax check pass.

The live read-only rehearsal on 2026-07-27 completed with five restorable
applications and zero unsupported applications after adding exact mappings for
the currently observed Opera GX, Obsidian, Codex Desktop, and Vesktop windows
plus tray-only qBittorrent. qBittorrent was reported as
`background_no_window` with `launch_if_absent`.
It requested no password, executed no planned command, wrote no state, launched
no application, and requested no reboot.

The older post-usability repository-hygiene verifier still reports its
pre-existing stale README/MILESTONES expectations. Its read-only curation scan
correctly classified this new verifier as a commit candidate before staging;
neither finding is an A1 runtime failure.

## Deterministic test results

The focused verifier proves:

- `-Syu` and explicit forced-refresh `-Syyu` produce distinct exact plans;
- system Flatpak planning reuses a non-interactive existing sudo ticket;
- window titles and other sensitive launch context never enter snapshots;
- qBittorrent-style tray-only applications are captured without raw process
  arguments, and unmatched background processes are discarded;
- unknown applications and games are skipped visibly;
- all lifecycle states are simulated and terminate;
- password requests, command execution, state writes, application launches, and
  reboot requests remain zero;
- the command runner receives only read-only inventory commands;
- invalid input and symbolic-link registries fail closed;
- a snapshot with no safely restorable application blocks;
- only preview and rehearsal are available through the typed API; and
- the Dashboard adds no scheduler or polling loop.

## Local LLM evaluation

None. Package command construction, privilege boundaries, snapshot privacy,
application allowlisting, and reboot authority are deterministic safety
behavior and must not be evaluated by a model.

## Known weaknesses

- the public registry intentionally covers only a few conservative desktop
  applications plus qBittorrent and needs live owner review before A2;
- application identity and session behavior can change across package versions;
- browser-internal session restoration remains the browser's responsibility;
- A1 does not yet inspect package locks, disk space, active Soul jobs, logind
  inhibitors, boot identity, or unsaved document state required by later gates;
- A1 does not authenticate, run updates, persist a journal, install a unit,
  launch or move a window, or reboot;
- exact workspace restoration has not been live-tested.

## Memory keys

None. Maintenance plans and operational journals are not conversational memory.
A1 writes no owner-local maintenance state.

## Lifecycle states touched

- `complete`;
- `awaiting_input`;
- `failed`;
- `blocked_for_human_review`.

No operation remains running after return.

## Risk classification

Class 5 design, read-only A1 implementation. The future operation is privileged
and reboots the host, but this candidate has no execution path. The primary
current risks are misleading plans or accidental privacy leakage; both are
covered by deterministic fixtures and visible unsupported states.

## Safety and persistence check

```text
Password requested or stored: no
sudo/pacman/yay/flatpak update executed: no
Application launched or moved: no
Operational journal or snapshot written: no
Reboot requested: no
Persistent service added: no
Daemon, watcher, timer, or scheduler added: no
Background loop or polling added: no
Confirmation gate weakened: no
```

## Human review checklist

- [ ] Confirm normal `yay -Syu` remains portable default.
- [ ] Confirm this host may explicitly choose `yay -Syyu`.
- [ ] Confirm system Flatpak planning must reuse the same authorization.
- [ ] Confirm titles, URLs, raw commands, and environments remain excluded.
- [ ] Review every default restore-registry application and executable path.
- [ ] Confirm unknown applications and games remain unsupported by default.
- [ ] Run the live Dashboard preview and rehearsal.
- [ ] Confirm Guided Maintenance appears under Administration rather than Self Improvement.
- [ ] Approve A1, request repair, or reject it.
- [ ] Do not authorize A2 or A3 solely because A1 tests pass.
