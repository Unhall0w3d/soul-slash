# Phase 13B Local Model and Dashboard Acceptance Brief

## Objective

Validate conversational usefulness against the owner's configured local provider and verify the already-approved dashboard composition without treating model output as safety approval.

## Approved scope

- Run a bounded synthetic twenty-turn conversation against a configured local-only provider.
- Use a temporary chat/runtime root and omit credentials, private memory, private chats, and repository content from prompts.
- Cap turns, request timeout, input size, output size, and retained evidence.
- Record only redacted pass/fail observations, provider identifier, model identifier, latency totals, and known weaknesses in the repository review artifact.
- Verify dashboard markup and JavaScript expose Chat, Skill Studio, Self Improvement, Review Center, authentication, system-status refresh, and no polling primitives.
- Leave final visual and product judgment to the owner.

## Boundaries

- No cloud fallback.
- No transcript, token, credential, private endpoint, or private runtime data is committed.
- No model output authorizes mutation, safety, promotion, merge, or milestone completion.
- No background process, polling loop, watcher, or service change.
- Provider absence or failure produces a bounded blocked result rather than a fabricated pass.

## Acceptance

The local provider completes twenty synthetic turns with usable continuity observations, deterministic routes remain inspectable, dashboard structural checks pass, and the review artifact clearly separates automated evidence from pending human judgment.
