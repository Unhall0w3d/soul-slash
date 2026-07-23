# Music Studio Dashboard Concurrency Review

Status: candidate-complete for human review

## What was implemented

- Raised the dashboard's hard concurrent-request ceiling from 24 to 48 after
  native visual rendering and concurrent audio/video controls outgrew the
  earlier Music-Studio-only allowance.
- Preserved request-scoped threads, the immediate HTTP 429 overload response,
  bounded request parsing, and joined shutdown.
- Added enough bounded headroom for visible candidate audio/video range
  requests and one foreground render stream to coexist with Operator API
  actions.

## Files changed

- `lib/soul_core/dashboard_server.rb`
- `lib/soul_core/phase12c_foreground_dashboard_assessor.rb`
- `scripts/verify-music-studio-a3.rb`
- `scripts/verify-phase12c-foreground-dashboard.rb`
- `docs/soul/MUSIC_STUDIO_A3_DASHBOARD_BRIEF.md`
- `docs/soul/MUSIC_STUDIO_DASHBOARD_CONCURRENCY_REVIEW.md`

## Commands and deterministic results

- `ruby scripts/verify-music-studio-a3.rb` — passed, including bounded
  authenticated ranges, stream cleanup, and capped/joined concurrency.
- `ruby scripts/verify-phase12c-foreground-dashboard.rb` — its dashboard,
  timer-free browser, bounded-concurrency, and max-request checks passed; the
  aggregate exited nonzero only at the repository-curation regression because
  the current approved music candidate intentionally has uncommitted review
  files in the working tree.
- `ruby -c lib/soul_core/dashboard_server.rb` — syntax checked separately.
- `ruby -c lib/soul_core/phase12c_foreground_dashboard_assessor.rb` — syntax
  checked separately.
- `git diff --check` — checked separately.

## Local LLM eval results

None. This is deterministic HTTP resource behavior.

## Known weaknesses

- A sufficiently large burst can still receive HTTP 429 by design.
- Audio and video controls continue to request ranges independently; this
  change does not introduce caching, queues, retries, or client-side polling.

## Memory keys added or used

None.

## Task lifecycle states touched

None. HTTP admission occurs before application task dispatch.

## Risk classification

Low. The maximum remains explicit and bounded. No persistent worker, queue,
scheduler, watcher, or background continuation is added.

## Human review checklist

- [ ] Music Studio loads without starving API actions.
- [ ] The generation preview remains human-gated.
- [ ] The server still rejects traffic above its hard ceiling.
- [ ] Shutdown closes and joins active request threads.
