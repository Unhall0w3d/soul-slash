# Soul Character Identity and Palette Review

## Candidate

```text
Name: Soul character identity and portrait-derived palette
Risk class: Class 1 - local visual assets and presentation only
Branch/checkpoint: main working candidate
Date: 2026-07-18
Status: approved
```

## Implementation summary

The reviewed masked, unmasked, and full-body Soul character images are tracked
byte-for-byte and served from explicit same-origin routes. The Chat presence
chamber shows the masked portrait in a subdued idle state and crossfades to a
brighter unmasked portrait while the existing request lifecycle reports active
work. No timer, polling loop, inference, or new lifecycle state drives this
presentation.

The dashboard palette now derives from the character art's graphite, indigo,
ice-blue, and aged-bronze materials. Destructive crimson remains distinct. The
existing Soul slash favicon and compact mark retain identical geometry with
only their paint palette changed.

## Files changed

```text
- Makefile
- assets/brand/character/soul-full-body.png
- assets/brand/character/soul-portrait-masked.png
- assets/brand/character/soul-portrait-unmasked.png
- assets/brand/soul-slash-micro-mark.svg
- assets/dashboard/dashboard.css
- assets/dashboard/dashboard.js
- assets/dashboard/index.html
- docs/assessments/CHARACTER_IDENTITY_AND_PALETTE_REVIEW.md
- docs/soul/CHARACTER_IDENTITY_AND_PALETTE_BRIEF.md
- lib/soul_core/dashboard_http_application.rb
- lib/soul_core/phase12c_foreground_dashboard_assessor.rb
- scripts/verify-character-identity-palette.rb
```

## Commands run

```text
- make verify-character-identity
- ruby scripts/verify-phase12c-foreground-dashboard.rb
- ruby scripts/verify-gemma-core-dashboard.rb
- ruby scripts/verify-core-orchestration.rb
- make verify-music-studio-a3
- node --check assets/dashboard/dashboard.js
- ruby -c lib/soul_core/dashboard_http_application.rb
- git diff --check
```

## Deterministic test results

```text
Character asset hashes and PNG dimensions: passed
Same-origin route bytes and MIME types: passed
Idle/active portrait state contract: passed
No portrait timer or polling primitive: passed
Palette and text contrast contract: passed
Favicon geometry preservation: passed
Phase 12C foreground dashboard behavior: passed
Gemma Core dashboard identity: passed
Core orchestration regression: passed
Music Studio A3 regression: passed
JavaScript and Ruby syntax: passed
Whitespace check: passed
```

The Phase 12C aggregate verifier initially reported repository curation because
the new verifier was intentionally untracked during implementation. Its
functional dashboard checks passed; the candidate includes that verifier.

## Local LLM eval results

```text
Eval command or method: not applicable
Model/endpoint: none
Result: not run
Notes: this slice contains deterministic static presentation and asset routing;
       an LLM would not provide meaningful validation.
```

## Memory keys

```text
Reads: none
Writes/updates: none
Forget behavior: not applicable
```

## Lifecycle states touched

```text
- Existing request-scoped Chat data-state values are read for presentation.
- No state is added, changed, persisted, or allowed to remain running.
```

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
```

## Known weaknesses

```text
- Human desktop/ultrawide review is required after the dashboard reloads.
- Phone-width portrait cropping remains pending later physical-device review.
- The three lossless source images add approximately 6.8 MiB to tracked assets.
- Full-body art is tracked for later reviewed use but is not placed in a cramped
  dashboard surface by this slice.
```

## Human review checklist

```text
[x] Masked idle portrait reads as present but subdued
[x] Active unmasked portrait is clearly brighter without becoming glaring
[x] Crossfade is clean during a real Chat request
[x] Portrait does not obscure transmission titles or controls
[x] Palette feels coherent on Chat, Music Studio, and Self Improvement
[x] Favicon remains recognizable at tab and bookmark scale
[x] Text remains readable on desktop and ultrawide layouts
[x] No approved interaction or confirmation gate has changed
```

## Human review outcome

```text
Outcome: approved
Reviewer: repository owner
Date: 2026-07-18
Decision summary: Dashboard visual appearance approved after live review.
Required changes: none
```
