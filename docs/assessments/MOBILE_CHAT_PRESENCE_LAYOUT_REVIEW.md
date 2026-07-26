# Mobile Chat Presence Layout Review

Status: candidate-complete; human phone review pending

## What changed

- Removed the 360-pixel height cap that forced the transmission header, list,
  Soul presence card, and local footer into the same undersized mobile rail.
- Gave the mobile transmission list its own bounded vertical scroll region.
- Kept the presence card in normal document flow and reduced its portrait,
  spacing, and minimum height on narrow screens.
- Suppressed accidental horizontal scrolling in the transmission list.
- Left desktop and tablet grid layouts unchanged.

## Files changed

- `assets/dashboard/dashboard.css`
- `scripts/verify-mobile-chat-presence-layout.rb`
- `docs/assessments/MOBILE_CHAT_PRESENCE_LAYOUT_REVIEW.md`

## Commands and deterministic results

- `ruby -c scripts/verify-mobile-chat-presence-layout.rb` — PASS
- `ruby scripts/verify-mobile-chat-presence-layout.rb` — PASS (4 checks)
- `git diff --check` — PASS
- `git diff --exit-code -- scripts/verify-responsive-chat-and-web-research.rb`
  — PASS (the existing broad verifier remains unchanged)
- Live dashboard at a 390 × 844 viewport — PASS; the heading, transmission
  list, presence card, and footer have distinct non-overlapping bounds, and
  the transmission list scrolls vertically.

## Local LLM eval results

None. This is a deterministic responsive-layout correction.

## Known weaknesses

- Conversation archives remain intentionally bounded to 240 pixels on phones;
  long lists require scrolling inside that region.
- Device browser chrome and text scaling can alter the visible amount of the
  rail, so final acceptance remains a real-phone review.

## Memory keys added or used

None.

## Task lifecycle states touched

None.

## Risk classification

Low. CSS layout only; no persistence, privilege, network, model, skill, or data
behavior changes.

## Human review checklist

- [ ] Presence card does not cover the transmission heading or list.
- [ ] Transmission list scrolls vertically without a horizontal scrollbar.
- [ ] Presence portrait and status text remain readable.
- [ ] Conversation header and composer remain reachable below the rail.
- [ ] Desktop three-column Chat remains unchanged.
