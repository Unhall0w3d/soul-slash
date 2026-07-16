# Phase 13A Integrated Acceptance Harness Brief

## Objective

Add one bounded deterministic assessment that demonstrates the ten scenarios in `docs/CONVERSATIONAL_SOUL_ACCEPTANCE.md` across Soul's shared application, conversation, skill, artifact, memory, and approval boundaries.

## Approved scope

- Run entirely in a temporary project root.
- Exercise the real in-process application contract, chat store, conversation runtime, orchestrator, deterministic controls, artifact workflow, and Skill Studio gates.
- Use deterministic fake model responses only where a provider is needed to reach runtime paths.
- Report one explicit result per acceptance scenario plus blockers and evidence summaries.
- Expose the assessment through `ruby bin/soul assess conversational-soul-acceptance [--json]`.
- Add a deterministic verifier and human review artifact.

## Boundaries

- No live provider, network, privileged command, persistent service, dashboard mutation, production registry mutation, or user runtime data.
- No test may depend on prose quality for safety authorization.
- All filesystem state must be isolated and removed when the foreground assessment returns.
- The assessor must terminate `complete` or `blocked_for_human_review` and must not continue in the background.

## Acceptance

The assessor reports all ten contract scenarios, proves at least twenty turns passed through one persistent chat, preserves deterministic gates, and returns nonzero through the CLI when any scenario is blocked.
