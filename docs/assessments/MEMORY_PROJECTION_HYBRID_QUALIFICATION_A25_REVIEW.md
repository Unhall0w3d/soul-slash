# Memory Projection Hybrid Qualification A25 Review

Status: historical candidate-complete; superseded for production routing by
the environment-aligned A29 qualification.

## Implemented

- Exact validation and bounded consumption of a completed content-free A24
  envelope.
- Fixed `0.65` projection gate with projection baseline, projection-gated local
  ordering, and local-dominant weighted reciprocal-rank fusion profiles.
- Deterministic per-case and aggregate recall, precision, reciprocal-rank,
  forbidden-hit, and abstention evidence.
- Foreground CLI, Make targets, path containment, private-file checks, and
  fail-closed malformed-input handling.
- No profile selection, mutation, persistence, network, background behavior, or
  Chat/Voice routing.

## Deterministic validation

`ruby -c lib/soul_core/memory_projection_hybrid_fusion_qualification_service.rb`
and
`ruby -c scripts/verify-memory-projection-hybrid-qualification-a25.rb` pass.
The A25 verifier passes 19 checks covering exact A24 schema validation,
projection gating, local-dominant weighted RRF scoring, content withholding,
no selection, no mutation, malformed IDs, mutation-bearing input, case bounds,
and absence of persistence/background execution.

## Known weaknesses

- The result is rank qualification only; it does not establish semantic quality
  beyond the reviewed A24 corpus.
- RRF constants are fixed candidate values and require human review before any
  future routing decision.
- A25 does not alter local retrieval or expose the profiles to Chat or Voice.

## Historical private qualification

The ignored 16-case A24 evidence envelope completed through all three fixed
profiles. `projection_gate_local_order_a25` preserved all 11 positive hits, all
5 negative abstentions, zero forbidden hits, and positive reciprocal rank
`0.866667`. Projection order reached `0.748485`; weighted RRF reached `0.821212`.
All three retained positive recall `1.000000` and positive precision `0.285714`.
This run used a diagnostic command path that did not load the production `.env`
configuration. Its ranking comparison remains retained A25 evidence, but its
`0.65` hit count is not production-parity evidence and must not be used to
justify the current route. A29 corrected the command environment, repeated the
closed threshold study, and selected the distinctly named A29 policy at `0.55`.

## Human review checklist

- [x] Consume only the exact content-free A24 envelope.
- [x] Keep the projection threshold fixed at `0.65`.
- [x] Compare all three closed profiles without selecting a winner.
- [x] Verify local-dominant weighted RRF constants and deterministic ties.
- [x] Verify malformed input fails closed and output withholds content.
- [x] Review the private live A25 run and corpus-specific tradeoffs.
- [x] Retain A25 unchanged as historical evidence rather than rewriting it.
- [x] Supersede its production inference with the environment-aligned A29 run.
- [ ] Complete human Voice review before production closure.
