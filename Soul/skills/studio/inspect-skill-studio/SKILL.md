---
name: inspect-skill-studio
description: Inspect Soul's current Skill Studio proposal queue, proposal stages, Beta inventory and evidence, or production skill registry when the Operator explicitly asks what is in Skill Studio, requests one exact proposal or Beta, or asks which production skills are registered. Do not trigger for casual discussion of skills or for requests to approve, build, run, promote, close, reject, or delete Studio material.
---

# Inspect Skill Studio

Use the deterministic Skill Studio and production registry projections. Never
infer current state from conversation history or model memory.

1. Treat an unqualified Skill Studio request as an overview of proposal, Beta,
   and production counts plus pending proposal stages.
2. List proposals with exact IDs, current stage, Gate 1 state, and whether a
   Beta exists.
3. List Betas with exact IDs, maturity, run eligibility, current test state,
   and promotion state.
4. List production entries from the current registry without invoking them.
5. Resolve proposal details only by exact proposal ID or exact title and Beta
   details only by exact Beta ID. If the target is absent, return the overview
   and ask for an exact current identifier.
6. End every successful inspection with `complete` and `mutation: none`.

Never prepare or execute proposal approval, Beta preparation, Dev drafting,
Beta trials, promotion, closeout, rejection, or deletion. Direct those requests
to the exact reviewed action in Skill Studio and terminate as
`blocked_for_human_review`.

Read [authority.md](references/authority.md) before changing the inspection or
human-gate boundary.
