# Guided Maintenance Collapsible Cards A1 Review

## Candidate

SSH-integrated and rich inventory cards now start in the same compact visual
rhythm as status-only devices while retaining their complete evidence and
action surface behind an explicit disclosure gesture.

## What was implemented

- Rich cards default to IP, display name, semantic state, and a **Details**
  control.
- Clicking the non-interactive portion of a card or choosing **Details**
  expands its existing platform, update, kernel, service, security, Refresh,
  Maintain, and Reboot content.
- **Collapse** returns the card to its compact view.
- The disclosure control is keyboard accessible and exposes `aria-controls`
  and `aria-expanded`; existing buttons, links, inputs, and details elements do
  not accidentally toggle the containing card.
- Expanded device IDs survive bounded fleet rerenders for the current page
  session and are pruned when a device leaves the rendered fleet.
- Status-only cards retain their existing compact, non-expandable design.
- Documentation now distinguishes the fixed-address legacy Cisco card from the
  reviewed MAC-tracked status-only enrollment path.

## Files changed

- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-maintenance-local-topology-a1.rb`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `config/project_tracker_seed.json`
- `docs/assessments/GUIDED_MAINTENANCE_COLLAPSIBLE_CARDS_A1_REVIEW.md`

## Deterministic checks

Run:

```text
node --check assets/dashboard/dashboard.js
ruby -c scripts/verify-maintenance-local-topology-a1.rb
make verify-maintenance-local-topology
make verify-maintenance-fleet-status
make verify-maintenance-fleet-dhcp-identity
make verify-project-timeline
git diff --check
```

## Local LLM evaluation

Not applicable. This is deterministic presentation state over existing fleet
evidence and controls; model output is not involved.

## Known weaknesses

- Expansion is intentionally page-session state, not durable user preference.
- The legacy optional Cisco card remains fixed-address configuration. Automatic
  MAC retargeting requires the already-reviewed status-only enrollment flow and
  must not be represented simultaneously by both paths.

## Memory and lifecycle

- Shared memory keys added or used: none.
- Private state changed by this public candidate: none.
- Lifecycle states changed: none.
- No service, timer, watcher, daemon, listener, or background process was added.

## Risk classification

Low-risk presentation and documentation change. Existing collection,
authorization, mutation, and destructive-action gates are unchanged.

## Human review checklist

- [ ] Integrated cards initially align in a compact three-column grid.
- [ ] Clicking card whitespace expands and collapses only that card.
- [ ] **Details** and **Collapse** work by mouse and keyboard.
- [ ] Refresh, management links, Wazuh details, Maintain, and Reboot do not
  collapse the card or bypass their existing gates.
- [ ] Status-only cards remain compact and unchanged.
- [ ] Expanded content remains readable at desktop, ultrawide, and mobile
  widths.
