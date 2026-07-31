# Operator Backup A0 Brief

## Approved objective

Add a separately selectable Operator continuity profile for the workstation's
human-owned data, dotfiles, selected application state, and host-rebuild
evidence. Reuse the existing bounded Backup & Recovery administration model
without changing the approved Soul nightly DRS schedule.

## Required behavior

- Keep Soul and Operator manifests, tags, ledgers, receipts, and restore
  staging separate.
- Share one cross-profile mutation lock.
- Default to the existing encrypted local repository and Crucible destination;
  allow explicit non-secret Operator location overrides.
- Require preview, exact digest, profile-specific confirmation, foreground
  execution, verification, and visible lifecycle results.
- Keep Operator execution manual only in A0. Add no timer, scheduler, daemon,
  watcher, automatic retry, pruning, remote deletion, or live-tree restore.
- Include existing readable personal folders and a reviewed, selective set of
  dotfiles, application configuration, private recovery credentials, and
  host-rebuild evidence.
- Exclude reproducible raw AI model weights and retain exact reacquisition
  metadata and checksums in a tracked manifest.
- Disclose ambiguous and privileged recovery gaps instead of implying they are
  covered.

## Human review boundary

Manifest configuration is candidate-complete only after the generated exact
source and exclusion lists are reviewed. Backup coverage is not proven until a
fresh Operator snapshot and its exact Crucible lineage both verify. Staged
restore never promotes files into the live home or system tree.
