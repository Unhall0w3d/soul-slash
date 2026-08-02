# Maintenance AUR Review Gate A11 — Human Review

## Candidate summary

A11 separates trusted repository maintenance from AUR execution. Routine
maintenance now runs pacman repository updates and Flatpak only. Pending AUR
updates remain visible and require a separate, single-use, digest-bound,
interactive terminal review.

## Files and surfaces

- root authority, transaction planning, validation, and desktop handoff;
- bounded interactive AUR runner and deterministic verifier;
- Dashboard review control, receipt display, API contract, and URI handler;
- Guided Maintenance, current-state, README, and tracker documentation.

## Deterministic commands

```text
make verify-maintenance-aur-review-gate
make verify-maintenance-passwordless-authority
make verify-maintenance-rehearsal
make verify-maintenance-foreground-execution
make verify-maintenance-desktop-handoff
make verify-maintenance-reboot-restore
git diff --check
```

## Expected evidence

- root helper contains no `yay`, `makepkg`, pacman bridge, or AUR operation;
- zero-prompt transaction accepts only fixed pacman repository, Flatpak, and
  separately reviewed reboot vectors;
- AUR vector forces clean/diff/edit menus and unsets predetermined answers;
- changed package evidence blocks before execution;
- the review URI is owner-private, expiring, digest-bound, and single-use;
- every runner outcome invalidates the sudo ticket and returns a bounded state;
- receipts contain package names and lifecycle evidence, not terminal output.

## Known weaknesses

- `yay` and the AUR remain a community trust surface; this gate provides review,
  not a guarantee that reviewed build instructions are benign.
- Human review quality determines whether suspicious sources, checksum changes,
  install scripts, or diffs are rejected.
- The initial mutation adapter supports `yay` only. A detected `paru` package
  set remains read-only and cannot cross the review gate.
- The exact A11 v1 helper was installed on Atelier on 2026-08-02. The native
  passwordless self-check returned the reviewed version and helper digest.
- Atelier had no pending AUR updates at acceptance time. The first organic
  interactive cancel/install observation remains deferred; no fake update or
  weakened package-set gate was introduced to force that test.

## Memory and lifecycle

No Soul memory key is added. Owner-private reservations and receipts use the
existing host-maintenance state tree. Lifecycle states touched are `complete`,
`failed`, `canceled`, and `blocked_for_human_review`.

## Risk

Class 5. The change reduces existing privilege and automation scope. Human
review is still required before installing the replacement authority or
performing live AUR maintenance.

## Human checklist

- [x] Confirm routine Maintain excludes all AUR packages.
- [x] Confirm pending AUR count remains visible after routine maintenance.
- [x] Inspect the exact generated root helper and sudoers digest.
- [x] Install the reviewed A11 authority through the existing exact gate.
- [ ] Open one supervised AUR review and confirm all menus remain interactive.
- [ ] Decline or cancel once and confirm no AUR package is installed.
- [ ] Complete a separately reviewed benign AUR update and inspect its receipt.
