# Perception A2 Screen Understanding Review

## Candidate outcome

Chat can explicitly capture one focused monitor, active window, or selected
region, display the immutable PNG as a removable preview, and send it through
the existing bounded Daily-Core Picture Understanding path.

Opening the capture panel takes no screenshot. Capture does not invoke Gemma or
append a chat message. There is no automatic recapture, watcher, screen polling,
or computer-control surface.

## Files changed

- `lib/soul_core/screen_capture_service.rb`
- `lib/soul_core/dashboard_http_application.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-perception-a2.rb`
- perception guide, README, current state, roadmap, brief, and this review

## Deterministic results

- focused-monitor resolution and one exact `grim` command: PASS
- active-window geometry resolution: PASS
- selected-region validation and capture: PASS
- bounded foreground region timeout: PASS
- canceled selection terminal state: PASS
- missing dependency safe block: PASS
- timeout terminal state: PASS
- oversized PNG rejection and cleanup: PASS
- authenticated route: PASS
- same-origin CSRF requirement: PASS
- menu-open without capture: PASS
- removable preview before inference: PASS
- existing picture stream reuse: PASS
- monitor/window/region dashboard choices: PASS
- no observation or computer-control loop: PASS
- Perception A1 regression: PASS

## Commands

- `ruby scripts/verify-perception-a2.rb` - PASS
- `ruby scripts/verify-perception-a1.rb` - PASS
- `ruby -c lib/soul_core/screen_capture_service.rb` - PASS
- `ruby -c lib/soul_core/dashboard_http_application.rb` - PASS
- `node --check assets/dashboard/dashboard.js` - PASS
- `git diff --check` - PASS

## Memory, lifecycle, and risk

- Shared memory keys: none.
- Soul Vault writes: none.
- Lifecycle: `complete`, `failed`, `canceled`, `awaiting_input`,
  `blocked_for_human_review`.
- Risk: local-private read-only capture of potentially sensitive pixels.
- Mutation: ephemeral capture preview, followed only by the separately requested
  existing chat exchange.
- Persistence: none unless the Operator explicitly checks the existing retain
  control before sending.

## Known weaknesses

- A2 supports Hyprland through its installed `hyprctl`, `grim`, and `slurp`
  tools; other compositors fail closed.
- Active-window capture resolves whichever window is active when the server
  processes the request. The preview is the review boundary.
- Region selection temporarily occupies the foreground request until the
  selection is completed, canceled, or reaches its timeout.
- Gemma remains the qualified vision model and still requires Daily Core.

## Live host result

The production service captured one 3420×1382 active-window PNG (2.68 MiB),
returned it as an ephemeral dashboard preview, and removed its owner-private
staging directory before return. Through the authenticated Dashboard, opening
the Screen panel left the preview empty; pressing **Capture preview** displayed
the exact active-window source label; pressing **Remove** cleared the pixels
without adding a message or invoking Gemma.

## Human checklist

- [x] Open **Screen** and confirm no screenshot is taken.
- [x] Capture an active window and remove the preview without sending.
- [ ] Capture an active window and ask Soul to identify one visible UI detail.
- [ ] Cancel one region selection and confirm Chat remains usable.
- [ ] Capture a region and confirm the preview matches the selected geometry.
- [ ] Confirm non-Daily Core preserves the question and preview for retry.
- [ ] Confirm visible commands do not trigger skills or screen interaction.
- [ ] Confirm explicit retention and permanent conversation deletion still work.
