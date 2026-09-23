# Astra workflow migration

Authority: Operator approved the outlined instruction, routing-document and
operational task-pack recommendation updates on 2026-09-05. No application API
migration, model invocation, publication, merge or deployment was requested.

## Scope and acceptance

Preserve explicit confirmations, privacy boundaries, human review, proposal-local
generation and legacy fixture compatibility. Apply scoped follow-through and
verification guidance to the machine policy and Soul templates. Retain Astra
Medium as primary, Sol above Terra as a delegated tier, and bounded Luna/Spark
work. Keep historical articles, assessments and Sol-era downloads unchanged;
add a separately dated generic blog download. Do not regenerate live task packs.

Current task-pack recommendations: Astra Medium for generic orchestration and
the overall Codex boundary; Luna High for bounded implementation proposals;
Luna Low for the documentation-only starter. These are metadata, not automated
execution or model/effort changes. The review gate recognizes current advice
and legacy gpt-5.5 medium without granting any additional authority. Unknown
advice remains a warning. Schema and privacy/approval semantics stay unchanged.

## Instructions changed

- Machine-wide `~/.codex/AGENTS.md`: approved-group continuity, concrete blockers,
  existing-path inspection, user/skill precedence within actual permissions,
  proportionate verification and direct reporting.
- Soul `AGENTS.md` and cloud append template: distinguish advisory provider
  ingestion from authorized Codex candidate editing, preserving data boundaries.
- Skill task template: align the explicit persistence exception with the brief
  rule and report unfinished work at the eight-iteration limit.
- Subagent guide: current hierarchy and historical qualification labels;
  removed stale price multipliers and unverified allowance assumptions.
- Blog: new `codex-astra-multi-agent-workflow` download; no publishing or changes
  to the dated Sol-era articles/download packages.

## Verification plan

Run the affected generation verifiers in isolation, inspect generated role
recommendations, and run `scripts/verify-codex-routing-migration.rb` to test
recognized/legacy/unknown recommendations and unchanged rollback, execution,
production-write and promotion boundaries. Inspect scoped diffs and run
`git diff --check`. Record exact outcomes below before completion.

No local LLM eval is required to approve security behavior. This task does not
claim benchmarked Astra/Luna superiority or that new prose guarantees future
adherence. It is not complete voice acceptance, a real recovery operation, or
an API provider migration. Representative ongoing tasks remain behavioral
qualification evidence. No memory keys were added or changed.

Reference: [official Astra guidance](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6-astra).

## Completion evidence

Implemented and verified as a review candidate. Luna High edited the five
recommendation-producing Ruby modules and four matching verifiers. Astra
inspected their diff and independently implemented/tested the gate compatibility
change and reviewed instruction authority. No model role was promoted through
an API or a live generator invocation.

Worker checks passed in an isolated `git archive HEAD` copy with `.git` and the
nine current owned files overlaid:

```text
ruby scripts/verify-first-bounded-codex-task-phase33.rb
ruby scripts/verify-alpha-implementation-task-pack-phase29.rb
ruby scripts/verify-codex-handoff-contract-phase27.rb
ruby scripts/verify-model-suitability-policy-phase26.rb
```

All four reported `Verification complete.` All nine edited Ruby files passed
syntax checks. A separate temporary-root audit verified the starter report's
key set, both implementation-pack recommendations, generic handoff/policy
recommendations and completion-summary wording. Curation passed only in the
isolated copy; this does not qualify the dirty live repository for commit. The
worker removed its disposable test copy after completion; its results are
reported evidence rather than a retained test-log artifact.

Primary checks passed:

```text
ruby scripts/verify-codex-routing-migration.rb
ruby -c lib/soul_core/alpha_implementation_review_gate.rb
git diff --check
git -C /home/bhones/Projects/blog/UnHall0w3d.github.io diff --check
```

The new isolated test proves recognized and historical recommendations do not
grant execution or promotion, unknown advice remains a warning, and missing
Codex/write restrictions or rollback documentation still block. The original
dry-run fixture generator still retains `gpt-5.5 medium` intentionally.

Current command guides and the human-review checklist were synchronized as
well. The approved global policy edit completed before an initial blog-directory
creation failure; an explicit directory creation and file-only retry completed
the blog work without repeating the global edit. The blog initially had a clean
worktree and now contains only the new versioned download directory as this
task's changes. Nothing was published or committed.

Risk: instruction scope and review compatibility; independently reviewed by
the primary agent. Lifecycle: candidate work complete; merge/publication and
real-world workflow qualification remain human review activities. No runtime
services, provider endpoints, local models, secrets or memory stores changed.

Human checklist:
- Review the cloud-provider/Codex scope distinction and persistence exception.
- Confirm advisory routing matches the intended primary/worker responsibilities.
- Review the new blog version before publication; historical packages stay intact.
- Use subsequent real tasks to assess fewer redundant pauses, successful bounded
  delegation and correct recovery gates; fixture success alone is not that proof.

## Curation correction — 2026-09-23

New bounded implementation and documentation task packs now recommend the
callable GPT-6 Luna High and Low IDs, respectively. The review gate still
accepts historical GPT-5.6 and GPT-5.5 recommendations as advisory metadata;
that compatibility does not make them defaults for new work. Deterministic
routing and task-pack verifiers must pass before this candidate is reviewed.
