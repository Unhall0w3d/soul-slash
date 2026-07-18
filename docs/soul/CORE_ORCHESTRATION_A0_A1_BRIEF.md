# Core Orchestration A0-A1 Brief

```text
date: 2026-07-18
human_authorization: approved in the active development conversation
implementation_authorized: yes
live_core_transition_authorized: no
default_core_change_authorized: no
risk: Class 3 - manually controlled local runtime mutation
```

## Objective

Add a small, explicit Core control layer above Soul's reviewed model-runtime
controller. Present the active Core in the top bar and allow the Operator to
preview and activate a configured Core without rebooting, weakening existing
idle checks, or confusing chat-model placement with Music Studio generation.

The first host configuration exposes:

```text
Daily Core    -> AMD chat; NVIDIA remains available for ACE-Step on demand
AMD-Free Core -> NVIDIA chat; AMD is released for unrelated Operator work
```

Music Studio remains a bounded workload, not a third Core. Qwen fallback and
ACE-Step share the NVIDIA lane and must remain mutually exclusive.

## Authorized vertical slice

- Extend the existing reviewed `core_role` vocabulary with `reserve-chat`.
- Derive configured Cores from explicit profile roles; do not infer them from
  vendor names, profile IDs, or GPU labels.
- Add a bounded `CoreOrchestrationService` that delegates every service change
  to `ModelRuntimeControlService`.
- Preserve the runtime controller's lease, activity-observation,
  preview-digest, exact-confirmation, allowlist, and foreground bounds.
- Remember the last successfully used profile for each Core in one small
  owner-private coordination record so returning to Daily Core restores the
  Operator's last Daily profile. This is runtime selection state, not memory.
- Add authenticated application operations for Core status, activation
  preview, and activation execution.
- Add an event-driven top-bar Core selector beside Local and synchronize it
  after explicit status refreshes and runtime mutations.
- Update System Status and Model Runtime to distinguish Core, profile, chat
  engine, Music Studio engine, and resource conflict.
- Update tracked examples and current-state documentation without embedding
  host-specific paths, addresses, or credentials.
- Add deterministic tests and a human review artifact.

## Core derivation

```text
daily-chat   -> daily / Daily Core
reserve-chat -> amd-free / AMD-Free Core
music-chat   -> music / Music Core (recognized, not configured in this slice)
specialist   -> no Operator-selectable Core
```

Within a Core, the active profile is authoritative. When activating a different
Core, Soul uses the last profile it successfully observed or activated for that
Core. If none has been recorded, it uses the first configured profile with the
matching role. Profile order is therefore a deterministic fallback only.

## Activation lifecycle

```text
status
-> choose configured Core
-> resolve exact target profile
-> existing runtime load/switch preview
-> blocked_for_human_review
-> click-bound exact confirmation and unchanged digest
-> existing runtime load/switch execution
-> atomically record successful per-Core profile selection
-> complete
```

If the target Core is already active, activation returns `awaiting_input`
without mutation. If chat, research, transcription, Music Studio, or any other
Soul-owned lease is active, the existing controller blocks the transition.

AMD-Free and Music intentionally share the same NVIDIA Qwen chat profile. A
later repair permits a direct transition between those two operating intents:
it revalidates idle state and active leases, binds the exact source/target Core
and shared profile in a digest, requires exact confirmation, and atomically
changes only the owner-private Core-selection record. It does not stop or start
Qwen, touch Gemma, or load the foreground music engine.

## Hard boundaries

- No reboot, automatic switching, failover, preemption, idle unload, queue,
  watcher, scheduler, polling loop, or background continuation.
- No new service, unit, listener, package, model, model download, or provider.
- No Core becomes the default and Gemma is not promoted by this slice.
- No transition is performed merely by opening the dashboard or selecting a
  menu item. Execution still requires the existing authenticated preview gate.
- No attempt is made to run Qwen and ACE-Step concurrently on NVIDIA.
- No model output may select, approve, or execute a Core transition.
- No private Core state may be written outside the ignored Soul runtime root.

## Required evidence

- legacy v1-v3 profile compatibility and `reserve-chat` validation;
- deterministic Core grouping and fallback target selection;
- last-profile restoration with symlink, size, schema, and path protections;
- unchanged runtime confirmation and digest delegated through the Core gate;
- active lease, unavailable activity probe, stale digest, and conflict blockers;
- application contract and authenticated dashboard selector behavior;
- event-driven UI with no timer or polling primitive;
- System Status and Music Studio accurately disclose NVIDIA contention;
- no live Core transition during candidate implementation;
- completed review artifact following `docs/soul/HUMAN_REVIEW_GATE.md`.

## Human review outcome

```text
Outcome: implementation authorized; live transition remains a later Operator action
Reviewer: repository owner
Date: 2026-07-18
Decision summary: Proceed with the bounded Core orchestration candidate.
```
