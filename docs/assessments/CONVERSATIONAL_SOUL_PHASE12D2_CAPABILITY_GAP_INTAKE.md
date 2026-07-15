# Conversational Soul Phase 12D.2: Capability-Gap Intake

## Candidate status

```text
status: candidate_complete_for_human_review
human_review_required: yes
human_merge_review_required: yes
automatic_cloud_use: no
automatic_implementation: no
```

## What was implemented

- Conservative deterministic classification of explicit model-reported missing capabilities.
- Direct intake for capabilities already declared unavailable by Soul's capability registry.
- Production and runnable-Beta coverage checks before proposal creation.
- Deduplication by stable gap fingerprint.
- Local proposal intake packets under `Soul/proposals/skills/`.
- Bounded occurrence history capped at 1,000 events and 1 MiB.
- Local-private registration of the proposal brief as a conversation artifact.
- Automatic delivery to the originating chat's dashboard inbox.
- Automatic visibility in Skill Studio with origin chat, classification, intake state, and occurrence count.
- Explicit conversation messaging explaining creation, reuse, production coverage, or available Beta coverage.

The intake never calls Mistral, invokes Codex, builds a Beta, registers a production skill, promotes a candidate, or passes either human gate.

## Files changed

```text
docs/CONVERSATIONAL_SOUL_ROADMAP.md
docs/soul/PHASE12D2_CAPABILITY_GAP_INTAKE_BRIEF.md
docs/assessments/CONVERSATIONAL_SOUL_PHASE12D2_CAPABILITY_GAP_INTAKE.md
lib/soul_core/capability_gap_classifier.rb
lib/soul_core/capability_gap_intake_service.rb
lib/soul_core/conversation_runtime.rb
lib/soul_core/skill_studio_service.rb
assets/dashboard/dashboard.js
scripts/verify-phase12d2-capability-gap-intake.rb
```

## Commands run

```text
ruby -c lib/soul_core/capability_gap_classifier.rb
ruby -c lib/soul_core/capability_gap_intake_service.rb
ruby -c lib/soul_core/conversation_runtime.rb
node --check assets/dashboard/dashboard.js
ruby scripts/verify-phase12d2-capability-gap-intake.rb
```

## Deterministic test results

PASS:

- task-shaped explicit inability becomes a gap candidate;
- ordinary discussion, configuration failure, approval boundary, and safety refusal do not;
- one local proposal intake is created with every required artifact;
- no cloud provider or implementation process is invoked;
- proposal brief is private and delivered to the originating chat;
- equivalent declared gaps reuse the existing proposal;
- repeated occurrences are recorded without rewriting the approved proposal revision;
- Skill Studio exposes origin and occurrence metadata;
- matching production coverage suppresses duplicate intake;
- declared capability gaps integrate through the real conversation runtime;
- explicit local-model inability integrates after deterministic validation;
- runtime and dashboard remain free of polling, background continuation, and unsafe DOM rendering.

Complete candidate results:

```text
Phase 12D.2 capability-gap intake: PASS
Phase 12D Skill Studio lifecycle: PASS
Phase 12C foreground dashboard and security: PASS
Phase 12B and earlier application regressions: PASS
working-tree and staged whitespace checks: PASS
```

## Local LLM eval results

No live LLM eval was needed. Model-gap integration uses a deterministic fixture response, and safety authority remains deterministic. A future conversational eval may tune usefulness and phrasing, but cannot validate safety classification or either human gate.

## Known weaknesses

- Model-reported gap classification is intentionally conservative and may miss indirect or unusually phrased inability responses.
- Coverage matching uses bounded token overlap. It may identify a routing problem instead of creating a proposal when skill descriptions are unusually broad.
- This slice does not expose the optional Mistral drafting action in Skill Studio yet.
- A production-skill match suppresses intake and reports a routing/execution problem, but automated troubleshooting-record creation remains future work.
- A runnable Beta match is offered conversationally but is never executed automatically.
- Proposal intake text is local-private conversation content and therefore unavailable to cloud providers unless a later human-disclosed action explicitly permits it.

## Memory keys

No memory keys were added or used.

## Task lifecycle states touched

```text
complete
failed
awaiting_input
canceled (preserved by contract)
blocked_for_human_review
```

## Risk classification

```text
gap classification: Class 1 local computation
coverage lookup: Class 1 local read
proposal/event creation: Class 2 bounded local write
artifact registration/inbox delivery: Class 2 bounded local append
cloud use: none
implementation or promotion: none
```

## Human review checklist

- [ ] Soul creates an intake only for a genuine missing capability.
- [ ] Configuration, permission, policy, ambiguity, and transient failures remain distinct.
- [ ] Production and runnable-Beta coverage are checked first.
- [ ] Repeated gaps reuse the existing proposal.
- [ ] Originating request and chat provenance are useful in Skill Studio.
- [ ] Current-chat artifact and inbox delivery are clear in the dashboard.
- [ ] No cloud provider is contacted during intake.
- [ ] No implementation or promotion begins automatically.
- [ ] Human Gate 1 and Human Gate 2 remain unchanged.
- [ ] Candidate is approved for merge only after human review.

## Human behavioral review outcome

```text
reviewed_at: 2026-07-15
reviewer: human owner
outcome: approved_for_merge
```

The owner approved the live Phase 12D.2 behavior and explicitly authorized merge after reviewing the capability-gap intake flow through the local dashboard.
