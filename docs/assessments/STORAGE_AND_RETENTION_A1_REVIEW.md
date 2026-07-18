# Storage and Retention A1 Review

## Candidate

```text
Name: Storage and Retention A1
Risk class: Class 2 — read-only private metadata inspection
Branch/checkpoint: main working tree; not committed
Date: 2026-07-18
Status: candidate_complete; blocked_for_human_review
```

## Implementation summary

Added a fifth, manual Self Assessment scope for Storage & Retention. It reports
metadata-only size and lifecycle classifications for Soul's private music state,
production and legacy music runtimes, accepted Vulkan pilots, transcription,
finished exports, logs, shared memory, and Soul-prefixed temporary residue.

The same scope reports the existing dashboard service's current and peak memory
as a point-in-time observation. It creates no sampler, timer, monitor, or
background process.

Three cleanup categories can prepare exact, digest-bound, read-only previews:

```text
known Soul review residue older than 24 hours
regular project logs older than 30 days
failed music quarantine directories older than 24 hours
```

A1 intentionally registers no cleanup execution operation. Accepted pilots,
projects, exports, shared memory, production models, unknown temporary paths,
and legacy runtimes cannot enter these previews.

## Files changed

```text
- CHANGELOG.md
- assets/dashboard/dashboard.css
- assets/dashboard/dashboard.js
- assets/dashboard/index.html
- docs/CURRENT_STATE.md
- docs/assessments/STORAGE_AND_RETENTION_A1_REVIEW.md
- docs/soul/STORAGE_AND_RETENTION_A1_BRIEF.md
- lib/soul_core/application_contract.rb
- lib/soul_core/application_facade.rb
- lib/soul_core/self_improvement_service.rb
- lib/soul_core/storage_retention_assessor.rb
- scripts/verify-phase12d3-self-improvement-dashboard.rb
- scripts/verify-storage-retention-a1.rb
```

## Commands run and deterministic results

```text
ruby -c lib/soul_core/storage_retention_assessor.rb                 PASS
ruby -c lib/soul_core/self_improvement_service.rb                  PASS
ruby -c scripts/verify-storage-retention-a1.rb                     PASS
ruby scripts/verify-storage-retention-a1.rb                        PASS (17 checks)
ruby scripts/verify-phase12d3-self-improvement-dashboard.rb        PASS
ruby scripts/verify-phase12b-in-process-application-api.rb         PASS
ruby scripts/verify-phase12c-foreground-dashboard.rb               PASS; human visual review boundary retained
ruby scripts/verify-dashboard-self-improvement-navigation.rb       PASS
git diff --check                                                   PASS
```

After staging, the aggregate Phase 12B and Phase 12C gates passed all earlier
regressions and repository curation. Phase 12C terminates at its designed human
visual-review boundary rather than self-approving the dashboard.

## Live read-only result

The real post-reboot host assessment completed in 4.1 seconds with no writes:

```text
observed classified storage: 25,470,033,920 bytes
protected storage: 10,394,656,768 bytes
private Music Studio state: 977,149,952 bytes
production native Vulkan runtime: 8,761,794,560 bytes
legacy Python/CUDA music runtime: 15,074,873,344 bytes
accepted/diagnostic Vulkan pilots: 75,120,640 bytes
transcription runtime: 504,422,400 bytes
finished exports: 76,144,640 bytes
current cleanup candidates: 0
dashboard memory current: 85,811,200 bytes
dashboard memory peak since reboot: 115,920,896 bytes
```

The pre-reboot `/tmp` residue no longer exists after reboot. This validates why
temporary storage should be inventoried rather than deleted reactively. The
15 GB retired Python/CUDA runtime remains the largest manual cleanup opportunity,
but A1 does not authorize its removal.

## Local LLM eval results

```text
Not applicable. Storage classification and authority are deterministic and may
not be validated or authorized by model output.
```

## Memory keys

```text
Reads: none (file metadata only; shared-memory content is not read)
Writes/updates: none
Forget behavior: not applicable
```

## Lifecycle states touched

```text
- complete
- awaiting_input
- blocked_for_human_review
- failed (bounded timeout path)
```

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
Long-running background loop added: no
Background polling or sampling added: no
Network listener added: no
Cleanup execute operation added: no
Confirmation or destructive gate weakened: no
Skill-private memory store added: no
Private file content read: no
```

## Known weaknesses

```text
- Directory sizes use bounded local `du` metadata and may differ from apparent
  file size on sparse, compressed, or deduplicated filesystems.
- Category totals intentionally overlap neither parent music roots nor unknown
  paths, so "observed" is a classified subtotal rather than whole-disk usage.
- Dashboard memory is a manual point-in-time current/peak reading. It can reveal
  growth across repeated inspections but does not identify request attribution.
- `/tmp` eligibility is intentionally narrow. New Soul prefixes remain protected
  until explicitly classified in a later reviewed revision.
- A later cleanup executor must re-discover and re-bind every candidate; this A1
  digest must never be accepted as deletion authority.
```

## Human review checklist

```text
[x] Storage scope is visually clear and readable
[x] Protected versus reviewable classification is understandable
[x] Dashboard current/peak memory wording is not misleading
[x] Cleanup preview clearly communicates that execution is unavailable
[x] No desired storage category is missing from the inventory
[x] The three proposed future cleanup categories are appropriately narrow
[x] No unapproved persistence, deletion, movement, or scope expansion
[x] Deterministic and aggregate regressions pass
```

## Human review outcome

```text
Outcome: approved
Reviewer: repository owner
Date: 2026-07-18
Decision summary: Storage & Retention A1 approved after live visual review.
Required changes: none
```
