# Conversational Soul Phase 8 Maintenance Note

## Slice

Declared deterministic capability boundaries.

## Prerequisite

Phase 7 generic evidence follow-up routing is complete and verified.

## Added

- `ConversationCapabilityRegistry`
- stable capability IDs for host diagnostics
- available, conditional, and unavailable states
- deterministic capability catalog rendering
- capability-specific gap rendering
- Phase 8 assessor and verifier
- CLI assessment route

## Changed

- `ConversationOrchestrator` delegates capability questions and unavailable host requests to the registry.
- `ConversationRuntime` renders capability catalog, information, and gap responses from registry data.
- the host tool catalog recognizes direct Linux MD RAID requests as bounded host-status requests;
- the single aggregate `host.system_status.extended` gap is removed;
- the roadmap is rebased so the inserted routing and capability slices have unique phase numbers.

## Preserved boundaries

- recent persisted evidence is considered before the registry;
- available action requests still pass through the registered deterministic tool catalog;
- the registry does not execute commands or call a model;
- unavailable capabilities do not produce synthetic evidence;
- deeper host checks remain unavailable until separately declared and tested.

## Acceptance examples

```text
What host checks can you perform?
Do you support host system status?
Check host system status.
Check Linux MD RAID state.
Can you inspect SMART health?
Inspect scheduled jobs.
```

The first two render registry information. The next two reach `host.system_status`. The final two return capability-specific deterministic boundaries.
