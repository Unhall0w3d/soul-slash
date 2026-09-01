# Operator Migration Readiness A1 Brief

Status: human-approved policy implementation on 2026-09-01; manifest review
and fresh DRS qualification remain separate gates.

## Objective

Extend the existing Soul and Operator continuity allow-lists for a possible
workstation reinstall without turning either profile into a whole-home or
runtime-cache backup.

## Operator profile additions

- Codex memories, archived sessions, and generated images. Active Codex
  sessions remain excluded.
- The Opera GX profile. Browser caches, crash reports, shader caches, service
  worker cache storage, and live singleton/socket artifacts remain excluded.
- Existing selected creator and workstation configuration for JetBrains,
  Blender, Kate, Codex Desktop, GPU Screen Recorder, CoreCtrl, Soul, Raspberry
  Pi tooling, and Unreal Engine. The Unreal 5.8 `DefaultEngine.ini` is selected
  exactly; project trees and engine installations are not added by this slice.
- The existing local scripts directory, Applications and Cisco owner folders,
  Lutris configuration/database/game manifests, Ollama identity/history/model
  manifests, and the named Ascension WTF and AddOns trees.
- Ollama model blobs and `~/ai_models` remain reproducible and excluded.

## Soul profile additions

Only retained outputs that are not already in the repository-owned Soul
continuity tree are selected from `~/.local/share/soul`:

- `blender-visual/runs`
- `music/vulkan-pilot-runs`
- `visual-motion/runs`

The parent tree is intentionally not selected. Model weights, source checkouts,
helper environments, binaries, caches, and build products remain reproducible.

## Manual migration ledger

Before reinstall, the Operator will separately review Downloads and Recovered
and copy the required WinBoat, Unreal, and Trellis bulk state to dedicated
migration media. Project Wraith also requires a cold working-tree archive and
a verified private Git remote because modified or untracked work is not
protected by a later push. Those cold copies do not replace the final encrypted
DRS capture and exact second-copy verification.

## Authority and safety boundary

This brief authorizes tracked policy, deterministic verification, documentation,
and read-only reconciliation previews. It does not authorize changing either
live manifest, starting Restic, capturing a snapshot, copying private bulk
trees, changing retention, restoring data, deleting data, adding persistence,
or committing unrelated worktree changes. Existing digest and exact-confirmation
gates remain unchanged.

## Acceptance criteria

- Deterministic policy tests prove the new selected roots and exclusions.
- The whole `~/.local/share/soul` and model-weight trees are not selected.
- Reconciliation previews are add-only and report zero removals.
- Repository checks pass and a human review artifact records remaining manual
  work and qualification boundaries.
