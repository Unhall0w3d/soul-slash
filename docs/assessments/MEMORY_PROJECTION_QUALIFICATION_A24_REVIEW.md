# Memory Projection Qualification A24 Review

Status: candidate-complete and foreground live-qualified; no production
threshold or conversational route is approved.

## Implemented

- Closed owner-private positive/negative case schema.
- Deterministic local-versus-projection comparison.
- Fixed projection threshold sweep from 0.50 through 0.80.
- Recall, precision, reciprocal-rank, forbidden-hit, returned-result, and abstention
  evidence without query or memory content.
- Fail-closed rejection when A23 used local fallback rather than the active
  remote projection.
- Foreground CLI and Make targets; no Dashboard or conversational routing.

## Deterministic validation

`scripts/verify-memory-projection-qualification-a24.rb` covers threshold
behavior, positive and negative cases, content withholding, no automatic
selection, no mutation, bounded collaborators, fallback rejection, path
containment, symlink rejection, owner-private file permissions, exact A23
projection identity, explicit result arrays and scores, correct positive-case
decisions, an overall deadline, and absence of persistence/background work.
The deterministic verifier passes 28 checks. An independent bounded review
identified the malformed-envelope, scoring, file-trust, identity, and timeout
gaps; each is now covered by the service and verifier.

## Known weaknesses

- Meaningful qualification depends on a human-reviewed private corpus.
- Cosine thresholds are model- and corpus-specific; deterministic fixtures do
  not authorize a live value.
- The output does not yet combine local lexical components with remote scores.
- Chat and Voice remain on their existing local retrieval path.

## Private live qualification

The ignored owner-private corpus contains 16 reviewed cases: 11 positive and 5
negative. The live run completed against the active projection without
fallback. No query or memory content was copied into the repository.

- Local retrieval preserved `1.000000` positive recall and achieved `0.866667`
  positive reciprocal rank, but abstained on only 2 of 5 negative cases.
- Projection threshold `0.65` preserved `1.000000` positive recall, abstained
  on all 5 negative cases, and improved positive precision from `0.227273` to
  `0.285714`, while reducing positive reciprocal rank to `0.748485`.
- Threshold `0.70` further improved precision but reduced positive recall to
  `0.977273`; `0.75` and `0.80` caused larger recall loss.
- No threshold produced a reviewed forbidden-memory hit.

`0.65` is therefore the leading remote admission candidate on this corpus, but
the local path orders known answers better. The evidence supports a subsequent
bounded hybrid-fusion qualification rather than replacing local ranking or
routing the raw remote result directly into Chat/Voice.

## Human review checklist

- [x] Create and review the private qualification corpus.
- [x] Run the foreground live qualification.
- [x] Inspect positive recall and negative abstention tradeoffs.
- [x] Retain `0.65` only as a candidate for hybrid-fusion evaluation.
- [ ] Qualify hybrid fusion in a separate candidate slice.
- [ ] Do not approve Chat/Voice routing solely from deterministic fixtures.
