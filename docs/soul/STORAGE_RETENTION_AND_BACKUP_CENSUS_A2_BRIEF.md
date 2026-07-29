# Storage, Retention, and Backup Census A2 Brief

Status: human-approved for implementation on 2026-07-29

## Outcome

Extend the existing read-only Storage assessment into a complete, portable
artifact-class census. Every active Soul workflow class must identify:

- its owning subsystem;
- its generic local path or path family;
- whether it is protected, lifecycle-owned, age-reviewable,
  capacity-bounded, disposable, reproducible, or manual-review material;
- what event may remove it;
- whether it is covered by the configured encrypted Restic source manifest,
  deliberately excluded, independently replicated, or currently uncovered;
- whether finished exports or other independently retained descendants must
  survive deletion of the owning project.

The local Knowledge Vault must be part of the default Restic source scope even
when it also has independently managed private Git history.

## Included

- Metadata-only census of Chat, Voice, Perception, workspace/inbox, Music,
  Visual, Skill Studio, Self Improvement, Self Augmentation, maintenance,
  backup state, Knowledge Vault, finished exports, runtime ledgers, logs,
  caches, models, helper environments, and known temporary residue.
- Coverage comparison against owner-local `sources.txt` and `excludes.txt`.
- Verification of the latest retained backup manifest when one is available,
  without requiring or accepting the Restic password.
- Portable default backup sources for durable continuity paths introduced
  after Backup Administration A2.
- Explicit exclusions for request-private staging, sessions, approval tokens,
  active leases, and reproducible maintenance caches.
- A genuine non-mutating public-repository hygiene check mode.
- Deterministic tests, documentation, and one human review artifact.

## Safety and privacy boundaries

- A2 reads filesystem metadata and backup path inventories only. It does not
  read project content, chats, memory bodies, credentials, Vault notes, media,
  prompts, model responses, or generated lyrics.
- Repository and backup reports expose generic/display paths and coverage
  states, not secret values or remote private-repository URLs.
- Symlinks and unsafe ancestry are reported and never followed.
- No cleanup execute operation is added.
- No file, project, candidate, proposal, chat, log, model, cache, snapshot, or
  export is deleted or moved.
- No backup, restore, replication, retention, or Git network operation runs.
- Passing coverage checks is evidence, not authorization to remove material.

## Backup contract

- The Restic source manifest is the authoritative local encrypted-backup
  allowlist.
- Private Git for the Knowledge Vault is supplementary history, not a
  substitute for a recoverable workstation snapshot.
- Durable owner state absent from the source manifest is reported as
  `uncovered`.
- Request-private or reproducible state deliberately matched by an exclusion
  is reported as `excluded`, not missing.
- A configured source is not considered proven in a backup until the latest
  retained manifest inventories that source or a descendant.
- Existing owner manifests are never silently replaced by portable setup.

## Explicitly deferred

- Cleanup execution and Trash movement.
- Automatic expiry, scheduled cleanup, startup cleanup, polling, watchers, or
  background reconciliation.
- Model/runtime removal.
- Restic snapshot creation or pruning.
- Automatic edits to an existing owner backup manifest.
- Full restore rehearsal for every artifact class.

## Deterministic acceptance

- The census contains every class named in this brief and each record has one
  owner, retention class, deletion boundary, and backup expectation.
- Default backup configuration includes the local Knowledge Vault, Music and
  Visual projects, chats, owner-private state, finished exports, and newer
  durable continuity paths.
- Ephemeral staging, sessions, approvals, leases, and reproducible package
  caches remain excluded.
- Coverage distinguishes configured, excluded, independently replicated,
  latest-snapshot verified, and uncovered states.
- The latest manifest can prove Vault/project/chat/export coverage without a
  password or content read.
- `repo-public-hygiene-cleanup.sh --check` cannot mutate the working tree.
- Existing Storage, Backup Administration, Knowledge Vault, Dashboard, and
  repository-hygiene regressions pass.
