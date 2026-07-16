# Structured Capability-Gap Signal Brief

## Brief status

```text
brief_status: approved from human direction dated 2026-07-16
implementation_authorized: yes
human_review_required: yes
live_provider_cutover_authorized: no
```

## Purpose

Repair the self-skilling intake blind spot demonstrated by the alternate AMD
model acceptance runs. When an otherwise task-shaped request receives ambiguous
natural-language denial wording, Soul may ask the same configured local model
for one schema-constrained classification. Deterministic validation decides
whether the result may create a review-gated proposal intake.

This is a bounded classification fallback, not a model-authorized action and
not an autonomous skill-development loop.

## Required flow

```text
task-shaped user request
→ normal local conversation response
→ deterministic capability-gap classification
→ deterministic structured-review eligibility check
→ at most one local schema-constrained classification request
→ exact shape and consistency validation
→ create/reuse proposal intake or stop
→ human proposal review
```

## Deterministic preconditions

The structured fallback may run only when all are true:

- the original request is task-shaped;
- the request is not hypothetical or meta-discussion;
- the assistant response contains a bounded denial cue;
- the response is not a configuration, credential, connectivity, permission,
  safety, ambiguity, or transient-failure response;
- the normal deterministic classifier did not already accept the gap;
- the selected provider is `local_only` and declares structured-output support.

Failure or ineligibility defaults to no intake.

## Structured response

The local model must return one JSON object with exactly:

```text
candidate: boolean
classification: missing_capability | not_a_capability_gap
reason: bounded string
```

`candidate` and `classification` must agree. Invalid JSON, extra keys, missing
keys, an overlong reason, timeout, provider error, or inconsistent fields
produce a non-candidate diagnostic result.

## Bounds

```text
maximum structured classification calls per conversation response: 1
maximum user request characters supplied: 4,096
maximum assistant response characters supplied: 4,096
maximum output tokens: 128
timeout: 20 seconds
temperature: 0
retries: 0
tools: none
cloud fallback: prohibited
background continuation: prohibited
```

## Authority and safety

- Model output may only nominate a local proposal intake for human review.
- It cannot execute a tool, build a skill, approve a proposal, promote memory,
  mutate host state, change provider configuration, or cross either Skill
  Studio human gate.
- Existing production/Beta coverage checks and proposal deduplication remain in
  force.
- No transcript beyond the already-bounded proposal intake is persisted by the
  classifier.

## Terminal behavior

Every fallback attempt terminates as one of:

```text
complete
failed
blocked_for_human_review
```

There is no waiting process, retry loop, watcher, timer, or scheduled work.

## Deterministic tests required

- ambiguous `No spectrometer ... is available` wording reaches one structured
  local request and creates a review-gated intake when valid;
- hypothetical, configuration, permission, safety, and ordinary responses do
  not invoke structured classification;
- cloud and non-structured providers are rejected before network use;
- malformed, inconsistent, and overlong structured responses create no intake;
- exact schema, input, token, timeout, retry, and tool bounds are enforced;
- existing deterministic gap phrases still create at most one intake without a
  second model request;
- Phase 12D.2 and Phase 13 regressions remain passing.

## Completion artifact

Create or update:

```text
docs/assessments/STRUCTURED_CAPABILITY_GAP_SIGNAL.md
```

## Human authorization

```text
Outcome: approved
Reviewer: repository owner
Date: 2026-07-16
Decision summary: proceed with the recommended structured capability-gap repair
```
