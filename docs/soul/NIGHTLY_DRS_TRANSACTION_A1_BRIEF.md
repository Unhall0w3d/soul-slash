# Nightly DRS Transaction A1 Brief

Status: Operator-approved implementation on 2026-07-29; human review required before merge

## Objective

Build the bounded transaction that a later reviewed 3:00 AM scheduler may
invoke: create one verified encrypted local snapshot, record deletion-aware
retention evidence, copy missing snapshot lineage to Crucible, verify the
off-device repository, and retain one terminal parent receipt.

A1 is a supervised transaction slice. It must not install or enable a
credential, service, timer, scheduler, daemon, watcher, retry loop, or
background process.

## Approved behavior

- Reuse `BackupAdministrationService` and its existing owner allow-list,
  exclusions, repository validation, metadata checks, retention ledger,
  nonblocking operation lock, fixed Crucible target, and redacted receipts.
- Add one manual DRS preview and one exact execution gate.
- Bind preview to the exact local capture scope, current Crucible preflight
  result, deletion-ledger policy, no-prune policy, no-remote-delete policy,
  and no-retry policy.
- Require the repository password only for the current Dashboard page request.
  A1 must not retain it.
- Revalidate the complete DRS preview before starting.
- Run local capture first. If it succeeds, attempt a fresh exact Crucible
  preview and copy.
- Treat local success plus unavailable or failed Crucible replication as an
  explicit partial result. Preserve the valid local snapshot and record enough
  lineage evidence for a later invocation to reconcile missing copies.
- Require the final Crucible inventory to include the exact newly captured
  local snapshot lineage before declaring the DRS transaction complete.
- Reuse the current fixed `~/.ssh/config` path explicitly. Default OpenSSH
  configuration is not trusted while the system fragment
  `/etc/ssh/ssh_config.d/20-systemd-ssh-proxy.conf` remains rejected for unsafe
  ownership or mode.
- Expose the supervised transaction and last terminal DRS evidence in
  Administration → Backup & Recovery.

## Active-work and concurrency boundary

- Existing accepted/running Music jobs block local capture.
- Every active model-runtime lease blocks local capture. Music, Visual,
  conversation, voice, and other model-backed work use this shared lease
  layer.
- The shared nonblocking backup operation lock rejects overlap with capture,
  retention, restore, replication, manifest reconciliation, and credential
  rotation.
- A1 adds no waiting loop and no retry. An invocation returns one terminal
  lifecycle result.

## Retention boundary

The verified local capture advances the existing deletion ledger:

- a newly detected source deletion protects its preceding snapshot for 30
  full days;
- source-root removal or replacement remains blocked;
- source-root additions require the existing separately reviewed policy;
- A1 never calls Restic `forget`, `prune`, or any remote deletion command.

Nightly automatic retention remains prohibited unless a later human-approved
brief explicitly adds it.

## Credential boundary

- A1 accepts the password from the existing page-session field.
- The password may reach only bounded Restic child environments.
- It must not appear in argv, `.env`, browser storage, receipts, logs, model
  context, Git, or project state.
- Host-bound encrypted systemd credential enrollment belongs to A2 and is not
  authorized here.

## Lifecycle

Every preview or execution terminates as one of:

- `complete`
- `awaiting_input`
- `canceled`
- `blocked_for_human_review`
- `failed`

Execution receipts distinguish:

- no mutation because local capture did not complete;
- local snapshot complete but Crucible copy incomplete;
- local snapshot and exact Crucible lineage complete.

## Bounded operation

- Existing local capture and verification limits remain unchanged.
- Existing Crucible copy and verification limits remain unchanged.
- One invocation performs at most one local capture and one Crucible
  reconciliation attempt.
- No detached continuation, automatic retry, polling, or scheduler is added.

## Deterministic verification

Fixtures must prove:

- exact preview and confirmation binding;
- wrong confirmation and stale digest perform no mutation;
- active Music work and active shared model leases block capture;
- concurrent backup work fails without waiting;
- successful local capture advances its manifest and deletion ledger;
- successful copy proves the new snapshot's original lineage on Crucible;
- remote failure preserves local success and records a terminal partial
  receipt;
- no password is persisted or placed in argv;
- no local or remote retention command is run;
- the Dashboard keeps preview and execution separate;
- A1 contains no credential persistence, unit, timer, scheduler, watcher,
  daemon, sleep, or retry primitive.

## Human review gate

Passing tests makes A1 candidate-complete only. Before merge, the Operator
reviews the exact scope, lifecycle evidence, Dashboard wording, partial-failure
behavior, credential transport, and the absence of persistence or pruning.
