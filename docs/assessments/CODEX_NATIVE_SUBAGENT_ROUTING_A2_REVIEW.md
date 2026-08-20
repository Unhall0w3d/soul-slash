# Codex Native Subagent Routing A2 Review

## Candidate

Name: Cost-aware Spark, Luna, Terra, and Sol routing

Risk class: Low — development workflow policy and documentation only

Status: `candidate_complete`

## Why the routing changed

The A1 policy correctly introduced bounded assignments and evidence-based
trust, but it treated Terra as the ordinary implementation worker and did not
define how to consume Spark's separate allowance. The Operator and primary Sol
revisited those assumptions after Spark's weekly pool was exhausted early and
the primary pool remained available.

Current OpenAI API rates were used only as relative-cost context. They do not
establish Codex subscription multipliers. At equal token volume, published
rates place Terra at ten times Luna and Sol at twenty-five times Luna across
input, cached input, and output. That makes automatic Terra or Sol re-review of
every Luna assignment economically self-defeating unless risk requires it.

## Representative bake-off

Identical read-only assignments were run against Project Wraith and Soul using
Luna Low, Luna High, and Terra Medium. No candidate changes were adopted.

- Project Wraith: Luna Low found the missing pawn-level lifecycle test class;
  Luna High found a touchdown teleport hidden from the existing transition
  metric; Terra Medium found a separate takeoff-readiness gate violation.
- Soul: Luna Low found that A3 proves intent matching but not the complete
  Chat/Voice path; Luna High and Terra Medium independently found that Incident
  Narrator performs a live Observatory refresh despite its retained-evidence
  contract. Luna High produced a deterministic injected-service proof.

The comparison established task-fit evidence, not universal benchmark results.
Exact subscription consumption could not be observed by the primary agent and
was not inferred from API prices.

## Adopted routing

```text
Spark Explorer while its separate mapping allowance is available
  -> Luna Low for mapping, deterministic checks, and mechanical work
  -> Luna High for bounded implementation and substantive review
  -> Terra Medium for unresolved integration ambiguity
  -> primary Sol for architecture, sensitive authority, and final integration
```

Expensive review is risk-triggered rather than automatic. Evidence-trusted and
change-trusted results receive proportionate primary review. Independently
verified categories remain unchanged.

## Files changed

```text
docs/CURRENT_STATE.md
docs/assessments/CODEX_NATIVE_SUBAGENT_ROUTING_A2_REVIEW.md
docs/guides/CODEX_SUBAGENTS.md
```

Owner-local policy changed outside the public repository:

```text
~/.codex/AGENTS.md
```

## Validation

```text
git diff --check
documentation link and terminology checks
```

## Known weaknesses

- Codex subscription accounting and exact per-task quota deltas are not visible
  to the primary agent.
- API pricing is a relative-cost proxy, not a subscription conversion table.
- Native model availability, allowance reporting, and model override fidelity
  remain runtime capabilities outside this repository.
- Representative findings qualify this workflow for these repositories; model
  or runtime changes require a fresh comparison.

## Persistence and authority

```text
Persistent service added: no
Scheduler or background worker added: no
Repository or shell authority broadened: no
Human approval gate weakened: no
Required validation waived: no
Merge authority delegated: no
```

## Human review

```text
[ ] Spark remains the preferred mapping worker while its separate pool exists
[ ] Luna High is the default bounded implementation/review worker
[ ] Terra Medium is escalation rather than automatic second-pass review
[ ] API pricing is not presented as Codex subscription accounting
[ ] Independently verified categories remain primary-owned
```

Outcome: pending
