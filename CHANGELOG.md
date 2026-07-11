# Changelog

## Unreleased

### Conversational Soul

- Completed Phases 1 through 4.
- Began Phase 5 grounded evidence lifecycle.
- Added persistent per-chat deterministic evidence records.
- Added explicit tool scope and evidence-profile metadata.
- Added collected versus not-collected evidence boundaries.
- Added evidence-aware conversation context.
- Added deterministic resolution of referential tool-result follow-ups.
- Changed `system.status` to evidence-only conversational rendering.
- Added an explicit host-environment capability-gap response.
- Added rejection of unsupported environmental claims and metrics in synthesized tool explanations.
- Added grounding and evidence IDs to runtime conversation state.
- Updated the Phase 4 assessor to preserve its synthesis coverage while testing grounded runtime status separately.
- Extended the Conversational Soul milestone to Phase 11.
- Reserved Phase 6 for a bounded `host.system_status` skill.

### Development direction

Phase 5 prevents conversational prose from outrunning collected evidence. Phase 6 will add an actual read-only host assessment rather than permitting the language model to populate an imaginary server room.
