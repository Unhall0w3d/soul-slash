# Changelog

## Unreleased

### Conversational Soul

- Completed Phase 1 architecture and acceptance contracts.
- Completed Phase 2 provider and model capability foundation.
- Completed Phase 3 multi-turn conversation runtime.
- Began Phase 4 conversational orchestrator.
- Added a bounded informational conversation-tool catalog.
- Added direct-model, deterministic, skill-only, skill-then-model, and fallback decisions.
- Added conversation-aware single-skill and two-skill execution.
- Added deterministic skill-result synthesis through the configured conversation provider.
- Preserved approval, mutation, and history-control routes as deterministic.
- Added unrelated-skill avoidance checks.
- Added safe preservation of deterministic results when model synthesis fails.
- Added memory-request and artifact-request intent flags for later phases.
- Added the `conversational-orchestrator` assessment.

### Development direction

The active milestone is Conversational Soul. Phase 4 lets conversation invoke bounded informational skills without granting the model execution authority. Phase 5 adds layered memory.
