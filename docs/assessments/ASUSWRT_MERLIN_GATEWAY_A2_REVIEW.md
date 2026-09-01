# ASUSWRT-Merlin Gateway A2 Human Review

## Candidate scope

The existing read-only adapter now projects bounded Entware, swap, USB storage,
firmware-check, toolbox, and diagnostic evidence into Guided Maintenance and
Local Topology. The router remains inventory-only. No router command performs a
mutation and no Dashboard Maintain or Reboot action is available.

## Files changed

- `lib/soul_core/asuswrt_merlin_inventory_adapter.rb`
- `lib/soul_core/maintenance_fleet_status_service.rb`
- `assets/dashboard/dashboard.js`
- `scripts/verify-asuswrt-merlin-inventory-a1.rb`
- `scripts/verify-asuswrt-merlin-gateway-a2.rb`
- `docs/soul/ASUSWRT_MERLIN_GATEWAY_A2_BRIEF.md`
- `docs/assessments/ASUSWRT_MERLIN_GATEWAY_A2_REVIEW.md`
- `Makefile`

## Deterministic checks

- Adapter fixtures cover successful parsing, incomplete evidence, unsafe SSH
  aliases, empty optional directories, and inventory-only fleet projection.
- The A2 verifier checks bounds, privacy, uninterpreted firmware state,
  mutation exclusions, and Dashboard presentation.
- Existing fleet and Local Topology verification must pass before merge.

Executed successfully on 2026-09-01:

- `ruby scripts/verify-asuswrt-merlin-gateway-a2.rb`
- `ruby scripts/verify-maintenance-local-topology-a1.rb`
- `ruby scripts/verify-maintenance-fleet-status-b1.rb`
- `/usr/lib/chatgpt/resources/cua_node/bin/node --check assets/dashboard/dashboard.js`
- `git diff --check`

The system `/usr/bin/node` could not start because its current dynamic-library
set lacks `libada.so.3`; the installed ChatGPT runtime's Node binary performed
the same syntax check successfully. This external package-state issue is not
masked as a system-Node pass.

## Live qualification

One reviewed foreground SSH probe and one Dashboard-equivalent device refresh
verified the aggregates in the A2 brief, returned healthy, persisted the
inventory-only snapshot, and terminated. Private addresses, aliases, hostnames,
and live values are not recorded in this tracked artifact.

The Notification Center/Voice Presence collision test also completed against
the live application. A synthetic spoken query produced a 44-second reply; a
priority reboot-required test event delivered its cue during speech, suppressed
its own spoken phrase, and did not interrupt Soul's reply. The temporary audio
sink and generated files were removed afterward.

## Known weaknesses

- `webs_state_*` firmware signals are intentionally displayed as raw vendor
  state. The adapter does not infer update availability from them.
- Entware upgrade count is based on locally cached metadata; the adapter does
  not refresh package lists.
- Aggregate storage capacity does not assert filesystem health or media SMART
  health.

## Memory and lifecycle

- Shared memory keys added or used: none.
- Lifecycle: one bounded foreground collection ending complete or failed.
- No service, timer, watcher, listener, retry, or continuation is introduced.

## Risk and review checklist

Risk classification: Class 2 read-only private-infrastructure evidence.

- [ ] Expanded router card is accurate and readable.
- [ ] No Maintain or Reboot control is shown.
- [ ] Local Topology identifies the reviewed gateway from live route evidence.
- [ ] No path, package name, client identity, credential, or raw output appears.
- [ ] Live refresh terminates and leaves no SSH process.
