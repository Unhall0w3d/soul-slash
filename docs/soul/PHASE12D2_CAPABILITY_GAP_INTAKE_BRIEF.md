# Phase 12D.2 Approved Brief: Capability-Gap Intake and Dashboard Delivery

```text
brief_status: approved from human direction dated 2026-07-15
implementation_authorized: yes
human_review_required: yes
human_merge_review_required: yes
```

## Purpose

When Soul cannot satisfy a task natively and neither a production skill nor a runnable Beta covers it, Soul should create one bounded local proposal intake, attach it to the originating chat, deliver it to the dashboard inbox, and expose it in Skill Studio for human review.

This is a bounded self-skilling intake path, not an autonomous implementation loop.

## Trigger classes

An intake may be created only when:

- the deterministic capability registry identifies a declared unavailable capability; or
- a configured conversation model returns an explicit inability response to a task-shaped request, and deterministic coverage checks find no matching production or runnable Beta skill.

An intake must not be created for:

- missing provider configuration, credentials, or connectivity;
- an approval or permission boundary;
- a safety refusal or prohibited action;
- an ambiguous request that needs clarification;
- a transient skill failure that should be diagnosed;
- ordinary discussion, questions, or model uncertainty;
- a request already covered by a production or runnable Beta skill.

## Required flow

```text
user task
→ native/tool lookup
→ production skill lookup
→ runnable Beta lookup
→ bounded gap classification
→ deduplicate against open gap intakes
→ create or reuse local proposal intake
→ register proposal brief as local-private chat artifact
→ deliver to current-chat inbox
→ show in Skill Studio
→ stop at proposal review
```

## Proposal intake

The intake is written under `Soul/proposals/skills/` and contains:

```text
metadata.json
proposal.md
review_checklist.md
sources.md
studio_state.json
gap_events.jsonl
delivery.json
```

It records the originating chat, bounded request summary, gap classification, coverage checks, local-only provenance, deduplication fingerprint, and questions still requiring human or model-assisted development.

The intake is not a completed skill brief. Optional Mistral drafting/review remains a separate disclosed action initiated from Skill Studio.

## Deduplication and bounds

- At most one intake attempt may occur per conversation response.
- Equivalent open gaps reuse the existing proposal.
- Repeated occurrences append at most one bounded event per request.
- Event history is capped at 1,000 records and 1 MiB.
- User request text is capped at 4 KiB.
- No retry, polling, watcher, scheduled work, or background continuation is allowed.

## Human gates

The Phase 12D gates remain unchanged:

1. Human approves the exact proposal revision before Beta implementation.
2. Human approves the exact tested Beta revision before a later promotion workflow.

Gap detection, model output, repeated demand, or successful drafting cannot pass either gate.

## Terminal behavior

Every intake attempt terminates as:

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

## Explicit prohibitions

- No silent cloud call.
- No automatic Mistral drafting.
- No automatic Codex invocation.
- No patch application, Beta build, registration, promotion, merge, or release.
- No recursive proposal generation from proposal failures.
- No proposal spam for configuration, permission, policy, or transient failures.
