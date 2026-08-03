# Dev Review Bounded Jobs A3 Review

## Candidate status

Live runtime validation complete; the Core lock-recursion repair remains a
candidate requiring pull-request review and merge.

## Implemented

- Neutral bounded-job HTTP alias with legacy music compatibility.
- Operation-specific subject validation and owner-private persisted receipts.
- Safe provider/runtime failure messages retained through the application
  envelope instead of becoming an empty Dashboard error.
- Retired the overlapping Arch improvement-plan card, application operations,
  service, and schema; Guided Maintenance is now the sole active host-update
  execution and verification surface.
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
- `lib/soul_core/core_orchestration_service.rb`
- `scripts/verify-core-orchestration.rb`
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
- `ruby scripts/verify-core-orchestration.rb`
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

The Operator's later completed environment synthesis also exposed a useful
quality defect: several bullets cited one scalar while asserting additional
facts from sibling fields (package-manager capabilities, Git branch, automatic
collection, and system architecture). This is suitable Self Augmentation
evidence for an atomic citation contract: every factual clause must cite its
exact evidence scalar or be explicitly labeled as inference.

An initial standalone attempt correctly failed closed because model runtime
control was not present in that process environment. Repeating with the normal
reviewed local configuration completed and restored the Core.

The human-gate acceptance session then used that synthesis defect as a real
augmentation proposal (`aug_fa3752f59e227938`). Its bounded GPT-OSS critique
completed after navigating away from Self Augmentation. Gate A1 created
`exp_e1e6434f4fccdf00` with six exact allowed paths and did not invoke Codex.
The implementation handoff survived a full page refresh, reattached to the
same running job, and completed once. The untouched worktree produced a
blocked dossier with zero changed files; both dossier and Gate A2 reported
`candidate must contain a committed change`.

On 2026-08-03 the remaining live Core matrix was exercised through the exact
`bin/soul-noctalia` and `bin/soul dev-worker` production gates:

- Soul-Lite → Creative Core initially exposed a false `model runtime control
  is busy` blocker. No lease or lock owner existed. Shared Core-intent
  execution was re-reading Dev status while holding the same non-reentrant
  model-runtime lock used by the Dev lease store.
- The candidate repair captures bounded Dev status before entering that lock
  and reuses the same observation only while committing the shared intent.
  A lock-aware deterministic fixture now reproduces the production topology.
- After repair, Creative Core activated without restarting Qwen. One exact Dev
  Worker request returned `awaiting_input` in 0.04 seconds with the expected
  Creative-Core blocker; GPT-OSS remained inactive and Creative Core remained
  selected.
- From Soul-Lite, one exact scoped request completed in 14.912 seconds with
  `starting_core_id: amd-free`, no chat transition, and reviewed GPT-OSS digest
  `17052f91...e376f7`. GPT-OSS stopped at terminal return, Qwen stayed active,
  and Soul-Lite remained selected.
- From Soul Core, one exact scoped request completed in 11.285 seconds. Its
  receipt records `daily → amd-free`, one GPT-OSS request, and
  `amd-free → daily`. The exact `amd-gemma` profile and
  `soul-model-gemma.service` were active after restoration; Qwen and GPT-OSS
  were inactive.
- Explicit Dev Core activation pinned the reviewed GPT-OSS model. Two
  consecutive exact requests completed in 1.971 and 2.106 seconds with
  `starting_core_id: dev` and `selected_dev_core: true`. The service remained
  active under the same PID `894004` and the model remained resident between
  requests. Leaving Dev Core stopped GPT-OSS, retained Qwen, and restored the
  initial Soul-Lite state.

The model summaries were treated only as untrusted candidate output. Core,
service, PID, placement digest, lease, and restoration evidence came from the
deterministic orchestration receipts and independent service observations.

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

- [x] Start each Dev review action and navigate to another Dashboard page.
- [x] Refresh during a test job and confirm current/terminal state is retained.
- [x] Complete one real scoped GPT-OSS job and confirm prior Core restoration.
- [x] Confirm Creative Core blocks scoped Dev work rather than being preempted.
- [x] Confirm Soul Core and Soul-Lite restore their prior runtime state.
- [x] Confirm selected Dev Core retains GPT-OSS between two requests.
- [x] Confirm no review result changes evidence or approves a gate.
