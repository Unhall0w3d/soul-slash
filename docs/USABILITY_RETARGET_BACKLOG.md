# Usability Retarget Backlog

This document tracks the near-term usability backlog created by retargeting Soul toward practical local assistant behavior.

## Current major milestone

Soul is now in the usability foundation milestone.

The core path exists:

```text
chat
intent routing
skill planning
execution gate
adapter registry
read-only / review-only adapters
execution history
history controls
runtime privacy boundary
```

This means Soul has crossed from static scaffolding into a usable local assistant skeleton.

It is not yet at the mutation milestone.

## Completed usability foundation work

```text
terminal chat
chat sessions
skill catalog
intent router
skill invocation planner
read-only execution gate
first read-only adapter
second read-only adapter
chat execution history
history list/export/clear/filter/prune
adapter registry
downloads.inspect
downloads.cleanup_plan
```

## Remaining usability retarget backlog

### Phase 58

```text
downloads cleanup approval design
```

Status:

```text
in progress
```

### Phase 59

```text
approval token scaffold
runtime-only approval store
token preview binding
no mutation
```

### Phase 60

```text
approval token chat flow
approve preview command
show pending approvals
revoke approvals
no mutation
```

### Phase 61

```text
downloads.move_to_trash dry-run executor
requires approval token
reports exact would-move counts
still no mutation by default
```

### Phase 62

```text
downloads.move_to_trash real executor behind approval token
moves to trash, never permanent delete
records execution history
post-execution report
```

### Phase 63

```text
usability milestone closeout
run full verifier set
repo curation
docs index refresh
manual test script
```

## Clear stopping point

The clear stopping point is Phase 63.

At Phase 63, the usability retarget backlog is considered closed when:

```text
preview exists
approval design exists
approval token scaffold exists
approval chat controls exist
dry-run mutation path exists
real trash-only mutation path exists
history records all gated actions
repo curation is clean
docs are indexed
all phase verifiers pass
```

That is the first point where we are not merely between features, but actually done with the current usability retarget backlog.

## Major milestones

### Milestone A: Foundation

Status:

```text
complete
```

Meaning:

```text
repo structure
docs discipline
phase verifiers
doctor/curation surfaces
runtime privacy hygiene
```

### Milestone B: Chat and planning

Status:

```text
complete
```

Meaning:

```text
chat interface
sessions
intent routing
skill planner
non-mutating execution gate
```

### Milestone C: Usability foundation

Status:

```text
mostly complete
```

Meaning:

```text
adapter registry
read-only adapters
review-only cleanup preview
history controls
```

Remaining work:

```text
approval-token usability
safe mutation boundary
closeout
```

### Milestone D: Safe local action

Status:

```text
not complete
```

Entry requirement:

```text
approval token scaffold
explicit approve/revoke flow
dry-run executor
trash-only executor
```

### Milestone E: Broader assistant capability

Status:

```text
not started
```

Examples:

```text
provider-backed skills
local model integration
web UI/API
voice
Proxmox deployment profile
state backup/restore
```
