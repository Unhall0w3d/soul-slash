# Evidence Follow-up Routing

Conversational Soul Phase 7 introduces a generic deterministic router for questions that refer to recently persisted evidence.

## Purpose

Before Phase 7, follow-up behavior lived partly in the grounding policy and accumulated profile-specific focus rules. That worked for the bounded host assessment, but every new evidence-producing skill risked requiring another conversational branch.

Phase 7 separates four responsibilities:

1. detect language that refers to a prior result;
2. select the most relevant persisted evidence record;
3. select matching claims or `not_collected` boundaries;
4. render the focused result without model synthesis.

## Boundary

The router never executes a skill, changes host state, calls a model, or invents missing facts. It works only with evidence records already persisted by deterministic skill execution.

A message is routed as an evidence follow-up only when it contains referential or result-oriented language such as:

```text
Which disks were you referring to?
Which files were flagged?
What about SMART health?
Tell me more about that result.
```

A semantically related but independent request is not enough by itself. This prevents recent evidence from hijacking unrelated conversation.

## Selection

Evidence records are scored using their label, tool ID, evidence profile, scope, claims, `not_collected` entries, and structured collected data. Recency breaks ties. When a focused follow-up has no positive evidence match, the router declines the route rather than attaching the question to the newest record.

Claim focus is generic token overlap with bounded topic expansion. It is not a registry of hardcoded skills. A future skill can participate by producing clear evidence labels and claims.

## Rendering

Follow-up rendering includes:

```text
heading
skill label and tool ID
evidence ID
scope
status
focused collected claims
focused not-collected boundaries, when relevant
```

The output remains deterministic even when the configured conversation provider is unavailable.

## Capability gaps

Direct requests for capabilities that have not been declared still use the explicit capability-gap route. A referential follow-up such as `What about SMART health?` may instead quote the prior evidence boundary that SMART health was not collected.

## Extension rule

New skills should improve their evidence records before adding router code. Prefer:

```text
clear label
stable tool ID
descriptive evidence profile
bounded scope
atomic claims
explicit not_collected entries
structured collected data
```

Do not add a skill-specific orchestrator branch merely to support ordinary evidence follow-ups.
