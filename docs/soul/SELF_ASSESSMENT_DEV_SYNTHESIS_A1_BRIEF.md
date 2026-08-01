# Self Assessment Dev Synthesis A1 Brief

Status: human-approved implementation brief
Approved by the human owner: 2026-08-01

## Objective

Add one explicit, bounded Dev Core review action to Self Assessment. The action
may synthesize only the latest successful deterministic assessment evidence for
one selected scope. It produces an advisory summary, evidence-linked
observations, explicit unknowns, and suggestions for which existing Soul
surface the Operator may inspect next.

This action does not collect replacement evidence, alter the source evidence,
assign or change severity, generate recommendations or host-mutation plans, or
authorize any follow-on work.

## Approved vertical slice

1. `SelfImprovementService` retains the latest successful evidence envelope for
   each assessment scope in process memory. A dashboard/service restart clears
   this cache; the Operator must run that assessment again.
2. A preview binds one selected scope, evidence identity, and exact evidence
   SHA-256 to a bounded Soul Dev Worker request.
3. Execute requires the unchanged preview digest and exact confirmation phrase.
4. GPT-OSS 20B receives only the bounded evidence envelope supplied by the
   parent service. It receives no shell, repository, network, Git, approval, or
   mutation authority.
5. A valid result is written once as an immutable, owner-private review packet
   beneath `Soul/private/self_assessment/dev_reviews/`.
6. The dashboard displays the review as advisory evidence beside the existing
   deterministic assessment controls.

## Allowed output

The structured result may contain only:

- one concise summary;
- up to twelve atomic observations, each citing one exact evidence path from the
  bound evidence envelope;
- up to twelve explicit unknowns and why the evidence cannot answer them;
- up to five routing suggestions selected from existing review surfaces.

Allowed routing suggestions are:

- `self_assessment`
- `skill_studio`
- `self_augmentation`
- `guided_maintenance`
- `none`

Routing suggestions are navigation hints, not recommendations, approvals, or
permission to execute an operation.

## Prohibited behavior

This slice must not:

- start a background job, watcher, daemon, service, timer, or polling loop;
- persist routine assessment evidence or create a private memory system;
- modify deterministic evidence, recommendation records, severity, proposals,
  plans, skills, models, packages, services, files outside its review root, or
  host state;
- let model text choose safety classification, authorization, confirmation,
  persistence, promotion, or follow-on execution;
- automatically invoke Self Augmentation, Skill Studio, Guided Maintenance, or
  any other operation;
- reuse Self Augmentation critique semantics for this action.

## Evidence and privacy boundary

Only the latest successful in-process evidence for the selected scope is
eligible. The service applies bounded recursive projection, rejects oversized
evidence, removes credential-like fields, and binds the exact projected JSON to
a SHA-256 digest. No secrets, credentials, private memory, chat history, project
content, or untracked repository content may be supplied to the model.

The immutable result packet is operational review evidence, not shared memory.
It is ignored by Git and covered by the existing owner-private backup source.

## Lifecycle and bounds

The action is foreground and terminates as one of:

- `complete`
- `failed`
- `awaiting_input`
- `canceled`
- `blocked_for_human_review`

The Dev Worker retains its existing five-minute hard ceiling. Evidence, schema,
candidate arrays, strings, review inventory, and stored artifacts have explicit
size/count limits. Cancellation or provider failure writes no partial packet.

## Review gates

Preview must disclose:

- scope and evidence generation time;
- evidence SHA-256;
- request digest;
- exact confirmation phrase;
- Dev model identity;
- advisory-only and no-follow-on-execution boundaries.

Execute must re-read the current in-process evidence and fail closed if its
digest or request changed. Candidate-complete output remains subject to human
review and does not certify its own accuracy.

## Acceptance criteria

- Deterministic tests prove evidence caching only after successful collection.
- Missing or changed evidence blocks execution without invoking the model.
- Invalid evidence citations or output shape write no packet.
- A valid result creates one immutable owner-private packet with source/model
  receipts and a human review checklist.
- The dashboard uses safe text-node rendering, has no new polling, and clearly
  distinguishes deterministic evidence from Dev synthesis.
- Existing Self Assessment, proposal, storage, host-plan, and maintenance gates
  remain unchanged.
