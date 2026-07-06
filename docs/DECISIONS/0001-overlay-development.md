# Decision 0001: Use Overlay-Based Development

## Status

Accepted

## Context

Soul/ is evolving quickly through small experimental layers.

Large rewrites make it difficult to track what changed and why.

## Decision

Use overlay zip packages for early development.

Each overlay should be focused, reviewable, and include installation/test guidance.

## Consequences

Positive:

- easier review
- easier rollback
- easier handoff
- clearer iteration history

Negative:

- overlays can overwrite files if not reviewed
- eventually this should become normal branches/PRs
- manual extraction is clunky

## Future

Once the repo stabilizes, overlays can map cleanly to Git branches or PRs.
