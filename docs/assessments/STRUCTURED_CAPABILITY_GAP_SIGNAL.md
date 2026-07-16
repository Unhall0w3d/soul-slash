# Structured Capability-Gap Signal Review

## Candidate

```text
name: structured local capability-gap fallback
risk class: Class 1 — local review-artifact nomination only
date: 2026-07-16
status: candidate_complete
```

## Implementation summary

Soul now retains deterministic capability-gap classification as the first path.
When a task-shaped request receives ambiguous denial wording that passes all
non-gap exclusions, the runtime may issue exactly one schema-constrained request
to the same `local_only` provider. Exact validation either nominates a local,
review-gated Skill Studio intake or fails closed to no intake.

The structured result is not authorization. It cannot execute a tool, build or
approve a skill, promote memory, use cloud fallback, or cross a human gate.

## Files changed

```text
- docs/soul/STRUCTURED_CAPABILITY_GAP_SIGNAL_BRIEF.md
- docs/assessments/STRUCTURED_CAPABILITY_GAP_SIGNAL.md
- lib/soul_core/capability_gap_classifier.rb
- lib/soul_core/structured_capability_gap_classifier.rb
- lib/soul_core/conversation_runtime.rb
- lib/soul_core/alternate_model_acceptance_harness.rb
- scripts/verify-structured-capability-gap-signal.rb
```

## Commands run

```text
ruby scripts/verify-structured-capability-gap-signal.rb
ruby scripts/verify-alternate-amd-model-acceptance.rb
ruby scripts/run-alternate-amd-model-acceptance.rb --server <pinned> --model <pinned> --server-sha256 <digest> --model-sha256 <digest>
ruby scripts/verify-phase12d2-capability-gap-intake.rb
ruby scripts/verify-phase13a-integrated-acceptance.rb
ruby scripts/verify-phase13b-local-model-dashboard-acceptance.rb
ruby scripts/verify-phase13c-conversational-soul-closeout.rb
git diff --check
```

## Deterministic test results

```text
valid exact structured candidate: pass
one call / 20-second timeout / 128 output tokens / temperature zero: pass
tools and tool choice absent: pass
4,096-character input caps: pass
inconsistent fields fail closed: pass
extra fields fail closed: pass
Markdown-wrapped or invalid JSON fails closed: pass
overlong reason fails closed: pass
cloud and non-structured provider rejection before call: pass
hypothetical/configuration/permission/safety/ordinary exclusions: pass
ambiguous runtime response creates one review-gated intake: pass
known deterministic gap skips second model request: pass
retry, background, and execution primitives absent: pass
```

## Local LLM evaluation results

```text
model: Ministral 3 14B Instruct 2512 Q4_K_M
endpoint: temporary 127.0.0.1:18082
result: pass
```

The fixed ambiguous response was:

```text
No spectrometer, synthetic or otherwise, is available here.
```

The real local model returned a bare schema-valid object that classified it as
`missing_capability`. Soul normalized that result to:

```text
classification: model_structured_missing_capability
source: structured_local_review
attempted: true
lifecycle_state: blocked_for_human_review
```

The expanded alternate AMD acceptance harness passed every check and returned
`candidate_ready_for_human_review`. Production health stayed HTTP 200 before,
during, after evaluation, and after cleanup. The temporary candidate terminated
and port `18082` closed.

## Memory keys

Reads:

```text
- none
```

Writes/updates:

```text
- none by the classifier
- an accepted signal may invoke the existing shared proposal-intake service
```

Forget behavior:

```text
- no classifier-private memory exists
- synthetic evaluation state is removed with its temporary root
```

## Lifecycle states touched

```text
- complete: ineligible provider or valid non-gap
- failed: attempted classification with invalid/provider-failure output
- blocked_for_human_review: valid missing-capability nomination
```

Every path returns synchronously. There is no `awaiting_input` process or
background continuation.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
Launch agent added: no
Windows service added: no
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Skill-private memory store added: no
Cloud fallback added: no
Tool execution added: no
Automatic skill build or approval added: no
```

## Known weaknesses

- Classification remains probabilistic. False positives can create proposal
  review noise, but cannot execute or approve work.
- The fallback adds one local inference and up to 20 seconds of latency only on
  eligible ambiguous denials.
- Deterministic prefilters are still English-language oriented.
- A future dashboard diagnostic may expose whether an intake came from direct
  deterministic classification or structured local review.

## Human review checklist

```text
[ ] Matches the approved structured-signal brief
[ ] Local-only provider restriction is correct
[ ] Schema and candidate/classification consistency checks are sufficient
[ ] Non-gap exclusions remain intact
[ ] Proposal and promotion human gates remain intact
[ ] No private classifier memory or background behavior exists
[ ] Local LLM evidence is treated as behavioral validation only
```

## Human review outcome

```text
Outcome: pending
Reviewer: repository owner
Date:
Decision summary:
Required changes:
```
