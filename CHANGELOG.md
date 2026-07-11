# Changelog

## Unreleased

### Milestones completed

- Completed the controlled advisory skill-development loop.
- Completed terminal chat, session, intent-routing, and skill-planning foundations.
- Completed the usability foundation and Safe Local Action milestone.
- Added approval-gated Downloads cleanup preview, dry-run, and move-to-trash execution.
- Closed the legacy usability sequence at Phase 63.

### Added

- Execution adapter registry.
- Read-only and review-only skill execution gates.
- Chat execution history, filters, export, clear, and pruning controls.
- Runtime-only approval token store with expiry, scope binding, revocation, and single-use enforcement.
- Chat controls for approval, pending-token listing, revocation, and dry-run.
- Trash-only Downloads executor with explicit confirmation and execution reporting.
- Usability milestone closeout and manual acceptance documentation.
- Controlled Codex handoff, fixture, review, and implementation-package surfaces.
- Cloud-assisted skill proposal drafting and review.
- New milestone tracking for Conversational Soul.

### Current local functionality

- `system.status`
- `downloads.inspect`
- `downloads.cleanup_plan`
- `downloads.move_to_trash`
- `assistant-skill-catalog`
- execution-history summary and controls
- approval-token controls
- terminal `chat`
- persistent chat sessions
- `reflect`
- reflection approve and reject
- legacy `do`
- legacy `respond`

### Development direction

The next milestone is Conversational Soul, beginning again at Phase 1. Its purpose is to add natural multi-turn conversation, conversational tool orchestration, layered memory, artifact-aware interaction, and context-sensitive personality.
