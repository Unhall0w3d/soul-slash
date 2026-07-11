# Conversational Soul Phase 7 Maintenance Note

## Slice

Generic deterministic evidence follow-up routing.

## Prerequisite

Phase 6 bounded host evidence and routing repair are complete and verified.

## Added

- `ConversationEvidenceFollowupRouter`
- generic follow-up-language detection
- evidence-record relevance scoring
- generic claim-level focus
- focused `not_collected` rendering
- deterministic follow-up rendering independent of model availability
- Phase 7 assessor and verifier
- CLI assessment route

## Changed

- `ConversationOrchestrator` delegates recent-evidence follow-up routing to the new router.
- `ConversationRuntime` delegates evidence follow-up rendering to the new router and records focused evidence metadata.
- The roadmap identifies Phase 7 as the active conversational slice.

## Preserved boundaries

- No model synthesis is used for evidence follow-ups.
- The router does not execute tools.
- The router does not mutate host or repository state at runtime.
- Missing capabilities remain explicit rather than inferred.
- Existing Phase 4, Phase 5, and Phase 6 verification remains regression coverage.

## Acceptance examples

```text
Which disks were you referring to?
Which files were flagged?
What about SMART health?
Tell me more about that skill catalog result.
```

The first three should select and focus the relevant persisted evidence. An unrelated prompt should continue through normal conversational planning.
