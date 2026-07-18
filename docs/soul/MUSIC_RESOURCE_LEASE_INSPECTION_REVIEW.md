# Music Resource Lease Inspection Review

Status: candidate-complete for human review

## What was implemented

- Made music resource inventory and other inspection paths strictly
  non-revoking when process identity is stale or unobservable.
- Restricted stale lease cleanup to lease acquisition, where cleanup is an
  explicit prerequisite mutation before new foreground work.
- Preserved the active music and cross-runtime lease when a sandboxed observer
  cannot see the dashboard-owned process namespace.

## Incident evidence

During a live 180-second generation, a sandboxed CLI inventory call could not
observe the dashboard process and classified the lease as stale. The inspection
removed both lease records. ACE-Step completed the FLAC, but MP3 derivation
failed closed because the active lease no longer matched. The partial candidate
remained quarantined and was not published.

## Files changed

- `lib/soul_core/music_resource_coordinator.rb`
- `scripts/verify-music-studio-a2.rb`
- `docs/soul/MUSIC_RESOURCE_LEASE_INSPECTION_REVIEW.md`

## Commands and deterministic results

- `ruby scripts/verify-music-studio-a2.rb` — pass
- `ruby -c lib/soul_core/music_resource_coordinator.rb` — pass
- `ruby scripts/verify-dashboard-click-approvals.rb` — pass
- `node --check assets/dashboard/dashboard.js` — pass
- `git diff --check` — pass

## Local LLM eval results

None. Lease ownership is deterministic safety infrastructure.

## Known weaknesses

- Inventory may conservatively display a genuinely stale lease until a bounded
  acquisition attempts cleanup. This can temporarily block work but cannot
  interrupt an active generation.
- The quarantined failed candidate from the incident requires a fresh preview;
  it is never auto-resumed or published.

## Memory keys added or used

None.

## Task lifecycle states touched

- `failed` for the interrupted publication path.
- `blocked_for_human_review` while an observed lease remains active or uncertain.

## Risk classification

Medium safety correction. The change favors conservative blocking over revoking
possibly active foreground work. No background cleanup, polling, or retry is
introduced.

## Human review checklist

- [ ] Inventory cannot remove a lease when process visibility is unavailable.
- [ ] A new acquisition can still clean a positively stale lease.
- [ ] Active work continues to block model switching and project deletion.
- [ ] Failed partial candidates remain unpublished.
