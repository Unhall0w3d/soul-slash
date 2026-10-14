# Pre-migration source preservation checkpoint

October 14, 2026. Source preservation only; not model, skill, service or release
promotion. The operator approved publishing source/tests and public-safe
summaries while committing detailed operational history on a local-only branch.

## Scope

The candidate is based on `1725a4bd4fcc0577fa3884250fe2a9eb823d3e50` and
preserves the previously untracked Continuity Lab A0-A25 and optional AMD
reviewer M0-M3C implementation, synthetic fixtures, approved briefs and result
summaries. Existing failures, qualification limits and human gates remain.
Generic Proxmox diagnostic collection source is included without its local
operational report. This checkpoint does not execute that collector.

Two shared source changes are included with their existing checks:

- AMD admission accepts an otherwise idle foreign allocation below 1 GiB;
  exactly 1 GiB and larger remain blocked. Independent compute/free-memory
  checks remain. This affects shared device admission, not only experiments.
- Quiescent-admission lease inspection retains and validates stale entries
  instead of pruning them. Expiration is not proof a provider call completed.

The complete five-file local desktop updater recipe is preserved byte-for-byte
under [tools/codex-desktop-local](../../tools/codex-desktop-local/PRESERVATION.md),
with provenance, source digests, generated-output exclusions and the
[restricted CachyOS bootstrap handoff](../guides/CACHYOS_CODEX_BOOTSTRAP.md).
It repackages the official binary; it does not compile the desktop app source.

## Validation performed for this checkpoint

- Pinned Ruby 4.0.7 syntax: 142 candidate source/test files passed.
- Node syntax: `scripts/verify-continuity-lab-librechat-client-a22.cjs` passed.
- Bash syntax: `scripts/collect-pve-lockup.sh` and the updater's three shell
  scripts passed. Updater parser tests passed without network/build/install.
- Seventeen bounded deterministic verifier commands passed: Continuity core
  A0 and recovery A0; A22 gateway, HTTP fixture and integration; A24 activation;
  A25 cases, protocol and runner; reviewer M1 and M1 recovery; reviewer M2, M3,
  M3B, M3C and M3C cases; shared AMD device admission.
- Test limits were 120 seconds per command and 600 seconds overall. No live
  model, GPU, service, backup or deployment actions were performed by this run.
- Git's whitespace check reports one existing extra blank line at EOF in the
  historical A16 qualifier. It is retained to avoid cosmetically changing that
  experiment source; the check passes with only `blank-at-eof` disabled.

A22's real loopback-listener lifecycle verifier was not rerun under this
checkpoint's no-listener validation scope. Its prior result remains historical.
The checks above are representative syntax/fixture checks, not a new complete
live qualification of every historical stage. Do not convert them into claims
of model accuracy, runtime acceptance or release approval.

## Publication and preservation boundaries

Public candidate paths were classified separately from host/fleet recovery
records. Credential-pattern scanning found only environment placeholders and
synthetic fixture tokens among the flagged candidate values. That scan is not
a general privacy proof; detailed infrastructure/history records remain local.
The synthetic evaluation summaries do not include private conversations or raw
runtime journals. Runtime/private data and generated binary packages remain
excluded by Git policy and require the later approved encrypted backup.

Use an explicit public branch push, never `--all`. The local-only operational
branch is not to be merged or pushed to the public remote. Local commits do not
protect against erasing the system disk; off-device backup remains pending.

## Migration hold

Experimental/model work is paused. A24's historical UI trial and activation
results remain recorded, while A25 has no scored comparison result. Its first
window failed in the harness and was cleaned up; a calibration-budget decision
is deferred until post-migration resumption. Source commit/push is not authority
to restart trials, activate a persistent adapter, change models or tune hardware.

Backup captures, package inventories, disk/mount changes, CachyOS installation,
and broader restore execution are not part of this source-preservation action.
