# Self Augmentation Dev Critique A1 Review

## Candidate status

Candidate implementation complete; human review required before merge.

## What was implemented

- Exact proposal lookup through the existing Self Augmentation source.
- Digest-bound GPT-OSS critique preview and execute operations.
- A closed advisory schema for strengths, concerns, unknowns, and revision
  questions.
- Independent citation and size validation after model output.
- Immutable proposal-local review packets with owner-only file permissions.
- A Self Augmentation Dashboard card with proposal selection, click authority,
  foreground progress, review inventory, and exact cited source values.
- Focused regression corrections so older augmentation verifiers inspect their
  own UI surface instead of unrelated later Dashboard timers.

## Files changed

- `lib/soul_core/self_augmentation_service.rb`
- `lib/soul_core/self_augmentation_dev_critique_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `scripts/verify-self-augmentation-dev-critique-a1.rb`
- `scripts/verify-self-augmentation-a4-a5.rb`
- `scripts/verify-self-augmentation-host-improvement-a1-a3.rb`
- `Makefile`
- relevant documentation and this review artifact

## Deterministic evidence

- `make verify-self-augmentation-dev-critique` — passed.
- `ruby scripts/verify-self-augmentation-a4-a5.rb` — passed.
- `ruby scripts/verify-self-augmentation-host-improvement-a1-a3.rb` — passed.
- `ruby scripts/verify-dashboard-self-improvement-navigation.rb` — passed.
- `ruby scripts/verify-dashboard-click-approvals.rb` — passed.
- `node --check assets/dashboard/dashboard.js` — passed.
- Local rendered UI smoke — card, progress state, live-region semantics, and
  horizontal layout passed with no visible script-error text.

## Local model evidence

One bounded live GPT-OSS critique completed against a non-secret fixture
proposal in 68.134 seconds from Soul-Lite Core. The receipt bound the reviewed
`gpt-oss:20b` digest, returned twelve review elements, released the scoped Dev
runtime, left `llama-server.service` active, and created no worktree.

The strengths and unknowns were useful. Several concerns nevertheless cited
fields that did not support the complete claim—for example, a rollback concern
cited only the proposal's `risk_class`. The Dashboard's exact source-value
projection made this semantic overreach immediately visible. This is behavioral
evidence for the workflow and for retaining human review; it is not safety or
release approval.

## Memory and persistence

- Shared memory keys added: none.
- Knowledge Vault reads or writes: none.
- New service, daemon, timer, watcher, listener, or scheduler: none.
- Critique packets are owner-local augmentation review evidence covered by the
  existing backup source.

## Lifecycle states touched

- `complete`
- `failed`
- `awaiting_input`
- `canceled`
- `blocked_for_human_review`

## Risk classification

Review-only model synthesis. The deterministic proposal and existing human
gates remain authoritative. The model has no mutation or approval surface.

## Known weaknesses

- Exact-field citations prove provenance, not that model prose is a sound
  interpretation of the cited scalar. The live run demonstrated this directly.
- The critique cannot inspect repository code, a later experiment, or a
  candidate dossier in this slice.
- Proposal revision remains human-authored; the critique does not rewrite the
  source packet.

## Human review checklist

- [ ] Select a proposal and inspect the exact digest-bound preview.
- [ ] Confirm the critique card clearly remains separate from Gate A1.
- [ ] Verify every strength and concern against its displayed source value.
- [ ] Confirm unknowns and revision questions are useful without becoming an
  implementation plan.
- [ ] Confirm no experiment or worktree was created.
- [ ] Approve or reject the candidate for merge independently.
