# Music Studio candidate ordering review

## Candidate status

`candidate_complete` — awaiting Operator review.

## Implementation summary

Project inspection now returns generated candidates newest-first using the
immutable `created_at` receipt timestamp and candidate ID as a deterministic
tie-breaker. The dashboard renders that authoritative order directly instead of
reversing a candidate-ID-sorted collection, and defensively applies the same
timestamp/ID ordering before rendering.

## Files changed

```text
- lib/soul_core/music_generation_service.rb
- assets/dashboard/dashboard.js
- scripts/verify-music-studio-a2.rb
```

## Verification

```text
ruby scripts/verify-music-studio-a2.rb PASS
node --check assets/dashboard/dashboard.js PASS
git diff --check PASS
```

- Local LLM eval: not applicable.
- Memory keys: none.
- Lifecycle behavior: unchanged.
- Risk class: read-only presentation ordering.
- Persistent/background behavior added: no.

## Human review checklist

```text
[ ] Newest candidate appears first
[ ] Older linked versions still collapse correctly
[ ] Candidate review and generation gates are unchanged
[ ] Approve candidate for commit/merge
```
