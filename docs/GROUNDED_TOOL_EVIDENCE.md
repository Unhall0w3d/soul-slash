# Grounded Tool Evidence

Phase 5 adds an evidence lifecycle between deterministic skills and conversational language generation.

## Problem

A skill result that exists only inside one model request cannot safely support later questions.

Without persistent evidence, a follow-up such as:

```text
Further details about what you checked, please.
```

may cause the model to expand its own prior prose instead of the original deterministic result.

That is how a modest runtime check becomes an imaginary RAID estate with excellent thermals.

## Evidence record

Each informational tool invocation now records:

```text
evidence_id
chat_id
tool_id
label
scope
evidence_profile
risk_class
status
collected
claims
not_collected
source
created_at
```

Evidence is stored under:

```text
Soul/runtime/conversation_evidence/
```

The path is generated, private, and gitignored.

## Collected versus not collected

Positive factual claims may use only:

```text
collected
claims
```

`not_collected` means unknown.

It does not mean:

```text
healthy
absent
configured
passing
unused
optimal
```

## Soul runtime status scope

The current `system.status` route is explicitly scoped as:

```text
Soul application and registered-runtime status only
```

It does not inspect:

```text
CPU
memory
disk utilization
filesystem type
block devices
RAID
SMART
temperature
network
firewall
host services
authentication logs
scheduled jobs
```

Because this result is easy to misinterpret, it is returned as deterministic evidence without model synthesis.

## Follow-up resolution

Referential follow-ups such as:

```text
further details
what did you check
which disk
where did that number come from
```

resolve to recent persisted evidence.

They do not ask the model to reconstruct the check from conversational prose.

## Grounding guard

For synthesis-capable informational skills, model output is checked for unsupported environmental terms and metrics.

When unsupported claims appear:

```text
model prose is rejected
deterministic evidence is returned
grounding errors are recorded
conversation continues
```

This is a guardrail, not a universal proof system. Deterministic evidence and clear capability boundaries remain the primary defense.
