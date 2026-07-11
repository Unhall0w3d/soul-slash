# Changelog

## Unreleased

### Conversational Soul

- Completed Phase 1 architecture and acceptance contracts.
- Began Phase 2 provider and model capability foundation.
- Added provider-neutral request and response envelopes.
- Added local OpenAI-compatible and Ollama provider definitions.
- Added a disabled cloud OpenAI-compatible provider shape.
- Added normalized provider capability and privacy metadata.
- Added bounded provider health checks with available, unavailable, and timeout results.
- Added the `conversation-provider-foundation` assessment.

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
- `reflect`
- reflection approve and reject
- legacy `do`
- legacy `respond`

### Development direction

The active milestone is Conversational Soul. Phase 2 establishes the model-provider boundary required before model-backed multi-turn chat is introduced.
