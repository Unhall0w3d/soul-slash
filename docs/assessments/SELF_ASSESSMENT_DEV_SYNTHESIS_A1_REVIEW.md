# Self Assessment Dev Synthesis A1 Review

## Candidate status

`candidate_complete` pending live Operator review

## Implementation summary

This candidate adds one foreground, digest-bound local GPT-OSS review action to
Self Assessment. It reuses the existing Soul Dev Worker boundary, accepts only
the latest successful in-process evidence for one selected deterministic
assessment scope, and creates an immutable owner-private review packet.

Allowed output is limited to a summary, evidence-cited observations, explicit
unknowns, and navigation hints. The result cannot modify evidence, severity,
recommendations, plans, approvals, skills, models, services, packages, or host
state, and it cannot invoke a follow-on operation.

## Files changed

```text
assets/dashboard/dashboard.css
assets/dashboard/dashboard.js
assets/dashboard/index.html
docs/CURRENT_STATE.md
docs/SKILLS.md
docs/assessments/SELF_ASSESSMENT_DEV_SYNTHESIS_A1_REVIEW.md
docs/guides/SELF_ASSESSMENT.md
docs/soul/DEV_CORE_GPT_OSS_INTEGRATION_BRIEF.md
docs/soul/SELF_ASSESSMENT_DEV_SYNTHESIS_A1_BRIEF.md
lib/soul_core/application_contract.rb
lib/soul_core/application_facade.rb
lib/soul_core/self_assessment_dev_synthesis_service.rb
lib/soul_core/self_improvement_service.rb
scripts/verify-self-assessment-dev-synthesis-a1.rb
```

## Deterministic verification

```text
ruby scripts/verify-self-assessment-dev-synthesis-a1.rb
ruby scripts/verify-phase12d3-self-improvement-dashboard.rb
node --check assets/dashboard/dashboard.js
```

The focused verifier proves:

- evidence must already exist and is returned defensively;
- preview invokes no model and discloses the authority boundary;
- changed evidence blocks before model invocation;
- valid output creates one `0600` immutable private packet;
- invalid evidence citations fail without partial artifacts; each atomic
  observation carries one exact primary source path;
- identical output is an idempotent replay;
- the application facade exposes a bounded inventory;
- the dashboard preserves preview-before-execute, safe rendering, and no
  polling.

All focused commands passed. The legacy Phase 13C aggregate was also invoked.
Its curation chain classified the new verifier after staging, but the aggregate
is not a current release gate: later nested checks still assert obsolete global
conditions such as a timer-free Dashboard and the historical tab inventory.
Those pre-existing assumptions conflict with already accepted Dashboard jobs
and navigation. The focused Self Assessment, navigation, click-gate,
authentication, Dev Worker, and Dev Core checks passed independently.

## Local LLM evaluation

Live environment-scope acceptance completed on 2026-08-01 through the reviewed
GPT-OSS 20B digest. Two initial candidates were rejected by the independent
schema boundary and wrote no packet. Narrowing observations to one exact
primary source made the third request schema-valid:

```text
duration: 21.278 seconds
starting Core: Soul-Lite
Dev placement: AMD Vulkan, 12,748,786,236 bytes in VRAM
terminal lifecycle: complete
review: assessment_review_3d9b303ef3c18f7b35c6
post-run Qwen service: active
post-run Dev service: inactive
```

The accepted model prose was useful but imperfect: several statements bundled
facts beyond their cited scalar. The candidate therefore exposes the exact
source value beside every observation and records this as a known weakness.
This eval validates runtime interoperability and review usefulness only; it is
not safety or authorization evidence.

## Memory keys

Reads: none

Writes/updates: none
Forget behavior: not applicable

The latest eligible assessment evidence is process-local operational state, not
durable memory. Completed reviews are owner-private operational evidence covered
by existing backup sources.

## Lifecycle states touched

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

## Risk classification

Class 2: owner-private advisory artifact creation after an explicit,
digest-bound foreground model invocation. No external publication, privilege,
destructive action, or host mutation.

## Known weaknesses

- Evidence eligibility is intentionally cleared by a Dashboard restart.
- Observations can still be mistaken or shallow; the cited deterministic
  evidence remains authoritative.
- Evidence path citations prove provenance linkage, not that the prose is a
  logically correct interpretation. The live GPT-OSS acceptance run bundled
  extra facts into some atomic observations, so the dashboard now displays the
  exact cited scalar beside every statement to make overreach reviewable.
- The Dev runtime may take several minutes to transition, run, and restore.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
Background continuation added: no
Safety gate weakened: no
Host mutation added: no
Shared memory changed: no
```

## Human review checklist

- [ ] Run a Self Assessment scope and preview Dev synthesis.
- [ ] Confirm scope, evidence time, SHA-256, model, and advisory boundary.
- [ ] Execute the exact pre-filled gate.
- [ ] Confirm observations cite visible source evidence.
- [ ] Confirm unknowns are explicit and useful.
- [ ] Confirm no suggested surface is invoked automatically.
- [ ] Confirm the prior Core is restored after the bounded run.
- [ ] Approve, request repair, or reject the candidate.
