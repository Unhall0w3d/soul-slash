# Conversational Soul Phase 11C Readiness

## Outcome

This maintenance candidate aligns the Ruby runtime, isolates improvement-pipeline verifier output from shared proposal state, corrects Phase 11 roadmap wording, and supplies a bounded Phase 11C candidate brief for human review.

It does not implement artifact creation or revision.

## Candidate status

```text
candidate_complete
phase11c_implementation: authorized
```

## Implementation summary

- tracks the local Ruby 4.0.5 runtime in `.ruby-version`;
- lets `ruby/setup-ruby` consume the checked-in version instead of pinning conflicting CI Ruby 3.3;
- permits normal improvement proposals only at their existing root and verifier overrides only below `Soul/runtime/verification/`;
- moves Phase 14–19 generated proposal tests and Phase 29–30 fixtures out of the shared proposal directory;
- corrects the roadmap to state that Phase 11 is in progress;
- adds a Codex-drafted Phase 11C brief with implementation explicitly unauthorized pending human review.

## Files changed

```text
.ruby-version
.github/workflows/ruby-smoke.yml
docs/CONVERSATIONAL_SOUL_ROADMAP.md
docs/soul/PHASE11C_BOUNDED_ARTIFACT_CREATION_REVISION_BRIEF.md
docs/assessments/CONVERSATIONAL_SOUL_PHASE11C_READINESS.md
lib/soul_core/improvement_proposal_paths.rb
lib/soul_core/improvement_proposal_generator.rb
lib/soul_core/proposal_locator.rb
scripts/verify-phase11c-readiness.rb
scripts/verify-improvement-proposals-phase14.rb
scripts/verify-alpha-skill-generator-phase15.rb
scripts/verify-alpha-skill-plan-generator-phase16.rb
scripts/verify-alpha-behavior-scaffold-phase17.rb
scripts/verify-alpha-review-phase18.rb
scripts/verify-alpha-review-phase18-latest-repair.rb
scripts/verify-alpha-promotion-gate-phase19.rb
scripts/verify-alpha-implementation-task-pack-phase29.rb
scripts/verify-alpha-implementation-review-gate-phase30.rb
```

## Commands run

```text
ruby scripts/verify-phase11c-readiness.rb
ruby scripts/verify-improvement-proposals-phase14.rb
ruby scripts/verify-alpha-skill-generator-phase15.rb
ruby scripts/verify-alpha-skill-plan-generator-phase16.rb
ruby scripts/verify-alpha-behavior-scaffold-phase17.rb
ruby scripts/verify-alpha-review-phase18.rb
ruby scripts/verify-alpha-review-phase18-latest-repair.rb
ruby scripts/verify-alpha-promotion-gate-phase19.rb
ruby scripts/verify-alpha-implementation-task-pack-phase29.rb
ruby scripts/verify-alpha-implementation-review-gate-phase30.rb
ruby scripts/verify-phase11-bounded-artifact-inspection.rb
ruby bin/soul assess repo-curation --json
git diff --check
```

## Deterministic test results

```text
Phase 11C readiness verifier: passed
Phase 14 through 19 isolated improvement regressions: passed
Phase 29 and 30 isolated fixture regressions: passed
Phase 11B and Phase 11A regressions: passed
Repository curation: passed
Whitespace checks: passed
```

## Local LLM eval results

```text
Not applicable. No conversational or model-backed behavior is implemented by this readiness candidate.
```

The Phase 11C brief lists the local LLM evals required after implementation is separately authorized.

## Memory keys

```text
Reads: none
Writes or updates: none
Forget behavior: not applicable
```

## Lifecycle states touched

```text
readiness candidate: complete
Phase 11C implementation: blocked_for_human_review
```

## Risk classification

```text
maintenance: Class 0 / test-local Class 2
Phase 11C proposal: Class 2, not implemented
```

Verifier writes are restricted to ignored `Soul/runtime/verification/` paths and cleaned up synchronously. No user proposal path is removed or overwritten.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
launch agent added: no
Windows service added: no
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Skill-private memory store added: no
Artifact creation implemented: no
Artifact revision implemented: no
```

## Known weaknesses

- Ruby 4.0.5 CI availability is validated only when the GitHub workflow runs.
- The verifier-root override intentionally supports only the fixed production root or an ignored verification subtree.
- Other historical verifiers may still refresh tracked snapshots or local runtime state; this candidate addresses the documented proposal-directory risk.
- The Phase 11C brief is a candidate and may require human revision before implementation.

## Human review checklist

```text
[x] Ruby 4.0.5 is the intended project runtime
[x] CI should consume .ruby-version
[x] Shared improvement proposals remain untouched by verifiers
[x] Verification output restriction is sufficiently narrow
[x] Phase 11C risk class is correct
[x] Phase 11C no-overwrite revision model is acceptable
[x] Phase 11C supported formats and artifacts/ root are acceptable
[x] Local-only/local-network provider boundary is acceptable
[x] Approval-token and literal-confirm flow is acceptable
[x] Implementation may begin under the candidate brief
```

## Human review outcome

```text
Outcome: approved
Reviewer: human owner
Date: 2026-07-14
Decision summary: The human owner approved the Phase 11C brief as written and instructed Codex to proceed.
Required changes: none
```
