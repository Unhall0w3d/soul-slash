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
- Permit one separately qualified hardened Operator systemd oneshot at 2:00 AM
  local time. It must use its own host-encrypted credential, timer, state, and
  receipts. Add no retry, pruning, remote deletion, or live-tree restore.
- Include existing readable personal folders and a reviewed, selective set of
  dotfiles, application configuration, private recovery credentials, and
  host-rebuild evidence.
- Exclude reproducible raw AI model weights and retain exact reacquisition
  metadata and checksums in a tracked manifest.
- Disclose ambiguous and privileged recovery gaps instead of implying they are
  covered.
- Preserve outbound recovery material including SSH configuration, known-host
  evidence, private/public client keys, GnuPG, keyrings, GitHub CLI state, and
  encrypted credential stores inside the encrypted snapshot.
- Preserve selected migration-critical workstation state: Codex memories,
  archived sessions and generated images; the Opera GX profile without caches
  or live singleton artifacts; selected creator-tool settings; Lutris state;
  Ollama identity, history, and model manifests without model blobs; and the
  named non-Steam game configuration paths.
- Keep Downloads, recovered-file holding areas, WinBoat disks, Unreal project
  and engine bulk data, and Trellis bulk data outside the automatic Operator
  allow-list until separately reviewed or copied to migration media.

## Human review boundary

Manifest configuration is candidate-complete only after the generated exact
source and exclusion lists are reviewed. Backup coverage is not proven until a
fresh Operator snapshot and its exact Crucible lineage both verify. Staged
restore never promotes files into the live home or system tree.

The 2026-09-01 migration-readiness extension was explicitly authorized by the
Operator. It changes tracked policy only; it does not authorize live manifest
reconciliation, a backup capture, retention, restore, or deletion.
