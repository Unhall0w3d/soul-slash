# Changelog

## Unreleased

### Conversational Soul

- Completed Phase 1 architecture and acceptance contracts.
- Completed Phase 2 provider and model capability foundation.
- Began Phase 3 multi-turn conversation runtime.
- Added bounded recent-turn context construction.
- Added provider-backed OpenAI-compatible and Ollama chat execution.
- Added per-chat runtime conversation state.
- Preserved deterministic skill and approval routes inside chat.
- Added truthful fallback behavior for missing or failed providers.
- Updated ChatCommand to store model, deterministic, and fallback response metadata.
- Added the `multiturn-conversation-runtime` assessment.

### Milestones completed

- Completed the controlled advisory skill-development loop.
- Completed terminal chat, session, intent-routing, and skill-planning foundations.
- Completed the usability foundation and Safe Local Action milestone.
- Added approval-gated Downloads cleanup preview, dry-run, and move-to-trash execution.
- Closed the legacy usability sequence at Phase 63.

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
- provider-backed multi-turn chat when a local provider is configured
- `reflect`
- reflection approve and reject
- legacy `do`
- legacy `respond`

### Development direction

The active milestone is Conversational Soul. Phase 3 provides the first real multi-turn model conversation loop. Phase 4 will add conversation-aware skill orchestration rather than granting the model direct execution authority.
