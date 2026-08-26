# AletheiaUC Vault to Dev Worker Context A5 Review

## Candidate status

```text
candidate_complete
```

## Implementation summary

Soul can now build one bounded Dev Worker context packet from the reviewed local
Knowledge Vault instead of requiring primary Codex to copy three notes into a
request manually. Preview selects and digests the current note bytes; execute
repeats selection and therefore fails closed if the note set or content changed.

The feature remains foreground, local-only, read-only, and tool-less from the
model's perspective. It grants no new repository, command, test, Git, approval,
or merge authority.

## Files changed

```text
lib/soul_core/dev_worker_vault_context_service.rb
lib/soul_core/dev_worker_vault_context_command.rb
lib/soul_core/app.rb
docs/soul/ALETHEIAUC_VAULT_DEV_CONTEXT_A5_BRIEF.md
docs/soul/schemas/dev_worker_vault_request.schema.json
docs/guides/DEV_WORKER.md
scripts/verify-dev-worker-vault-context-a5.rb
Makefile
docs/assessments/ALETHEIAUC_VAULT_DEV_CONTEXT_A5_REVIEW.md
```

## Deterministic checks

```text
make verify-dev-worker-vault-context
PASS - 16 checks

make verify-codex-soul-dev-worker
PASS - 32 checks

ruby -c lib/soul_core/dev_worker_vault_context_service.rb
ruby -c lib/soul_core/dev_worker_vault_context_command.rb
ruby -c scripts/verify-dev-worker-vault-context-a5.rb
ruby -c lib/soul_core/app.rb
PASS

git diff --check
PASS
```

The A5 verifier covers deterministic three-note/48-KiB selection, router
preference, exact context digesting, content-free receipts, changed-note
invalidation, insufficient context, secret rejection, symlink and traversal
protection, private-path exclusion, JSON CLI behavior, and absence of a new
model/network/process/persistence surface.

## Local model evaluation

The preceding A4 qualification ran three AletheiaUC tasks through the existing
host Dev Core. All receipts reported `starting_core_id: dev` and
`selected_dev_core: true`. The results were useful and project-specific, while
also demonstrating that plausible suggested paths and tests still require
current-repository verification.

A5 does not rerun those model calls merely to test deterministic context
assembly. The live A5 preview selected the Dev Core task router, implementation
reconciliation register, and collector workflow: three notes totaling 25,140
rendered context bytes. The receipt exposed only their relative paths, byte
counts, and SHA-256 values. Its exact context digest was
`f83682282acccf1f66dd18033d809c0f7b07a8696610f584f67905ad864ee43e`.
Execution is unnecessary because model behavior and Core lifecycle were already
qualified in A4.

## Memory and lifecycle

```text
Shared memory reads: none
Shared memory writes: none
Knowledge Vault reads: at most 3 complete reviewed project notes
Skill-private memory: none
Lifecycle states: complete, failed, awaiting_input, canceled,
  blocked_for_human_review
Mutation: none
```

## Known limits

- Retrieval is bounded lexical ranking, not semantic equivalence.
- Private-path and secret detection are defense in depth, not a substitute for
  keeping private evidence out of the reviewed vault.
- Full notes larger than the remaining context budget are skipped rather than
  truncated.
- The assembler does not validate whether a note remains synchronized with the
  current repository or vendor documentation.
- A sandbox unable to observe host user-systemd may still misreport Core
  eligibility; that separate runtime-message defect is not weakened or bypassed
  here.

## Human review checklist

- [x] Approved brief is implemented without authority expansion.
- [x] Existing Dev Worker confirmation and digest gates are retained.
- [x] No note content appears in preview or execution receipts.
- [x] No service, watcher, timer, listener, queue, or retry loop was added.
- [x] Existing and focused deterministic checks pass.
- [x] Review one live AletheiaUC vault preview.
- [ ] Approve merge.
