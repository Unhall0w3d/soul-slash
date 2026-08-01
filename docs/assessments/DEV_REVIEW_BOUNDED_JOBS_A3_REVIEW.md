# Dev Review Bounded Jobs A3 Review

## Candidate status

Candidate-complete; human review required before merge and production use.

## Implemented

- Neutral bounded-job HTTP alias with legacy music compatibility.
- Operation-specific subject validation and owner-private persisted receipts.
- Safe provider/runtime failure messages retained through the application
  envelope instead of becoming an empty Dashboard error.
- Progress propagation for Self Assessment synthesis, proposal critique, and
  post-Gate A1 implementation handoff.
- Dashboard stream/reconnect behavior without polling or automatic retry.
- Deterministic regression coverage for accepted, duplicate, concurrent,
  terminal, and interrupted jobs.

## Files changed

- `lib/soul_core/dashboard_music_job_manager.rb`
- `lib/soul_core/dashboard_http_application.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/dev_worker_service.rb`
- `lib/soul_core/self_assessment_dev_synthesis_service.rb`
- `lib/soul_core/self_augmentation_dev_critique_service.rb`
- `lib/soul_core/self_augmentation_dev_handoff_service.rb`
- `assets/dashboard/dashboard.js`
- `scripts/verify-dev-review-bounded-jobs-a3.rb`
- Existing focused verifier compatibility assertions, Makefile, and operator
  documentation.

## Deterministic evidence

Passed:

- `ruby scripts/verify-dev-review-bounded-jobs-a3.rb`
- `ruby scripts/verify-music-job-continuity.rb`
- `ruby scripts/verify-self-assessment-dev-synthesis-a1.rb`
- `ruby scripts/verify-self-augmentation-dev-critique-a1.rb`
- `ruby scripts/verify-self-augmentation-dev-handoff-a2.rb`
- `ruby scripts/verify-dev-core-skill-build.rb`
- Ruby and JavaScript syntax checks; `git diff --check`

The focused verifier covers all three operation identities, malformed subject
rejection, owner-private persistence, terminal follow, authenticated neutral
status/follow routes, operation allowlisting, UI routing, and restart recovery
without re-execution. Existing music continuity retains duplicate reattachment
and distinct concurrent-job rejection coverage for the shared manager.

## Local LLM evidence

A real environment-scope Self Assessment synthesis completed through the new
persisted manager in 21.332 seconds:

```text
operation: self_improvement.dev_synthesis.execute
job: job_62101fd40b637a8d
terminal lifecycle: complete
starting/restored Core: Soul-Lite
post-run Qwen service: active
post-run Dev service: inactive
```

An initial standalone attempt correctly failed closed because model runtime
control was not present in that process environment. Repeating with the normal
reviewed local configuration completed and restored the Core. No eligible
local augmentation proposal or Gate A1 experiment currently exists, so live
critique and handoff transport remain explicit production acceptance items
rather than fabricated fixtures. Their model behavior already has focused live
evidence in the A1/A2 review artifacts; this slice's shared persistence and
transport behavior is covered deterministically.

## Lifecycle, memory, and risk

- Lifecycle: `awaiting_input` → persisted `accepted`/`running` → one retained
  terminal application lifecycle; interrupted Dashboard work becomes `failed`.
- Retry: none. A human must obtain a fresh preview before trying again.
- Memory keys: none added or changed.
- Risk: medium transport/recovery change; authority remains review-only.
- Known weakness: the shared manager retains its legacy internal
  `Soul/music/jobs` storage directory for migration compatibility even though
  its authenticated API is now named `bounded-job`.

## Safety boundary

This changes transport and recovery semantics only. It grants no new model,
Core, file, gate, Git, host, memory, or follow-on authority.

## Human checklist

- [ ] Start each Dev review action and navigate to another Dashboard page.
- [ ] Refresh during a test job and confirm current/terminal state is retained.
- [x] Complete one real scoped GPT-OSS job and confirm prior Core restoration.
- [ ] Confirm Creative Core blocks scoped Dev work rather than being preempted.
- [ ] Confirm Soul Core and Soul-Lite restore their prior runtime state.
- [ ] Confirm selected Dev Core retains GPT-OSS between two requests.
- [ ] Confirm no review result changes evidence or approves a gate.
