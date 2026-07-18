# Private Memory Separation Review

## Candidate

```text
Name: Private Memory Separation
Risk class: Class 2 — bounded local private-state copy and compatibility cutover
Branch/checkpoint: main working tree; not committed
Date: 2026-07-18
Status: approved; live migration verified
```

## Implementation summary

Added an ignored owner-private memory root and a compatibility resolver. Existing
installations keep using the legacy paths until an exact-gated migration copies
and verifies all allowlisted files and writes a cutover marker. Fresh clones
without legacy memory write directly to private storage. No legacy source is
moved, edited, or deleted.

## Files changed

```text
- .gitignore
- CHANGELOG.md
- Makefile
- Soul/memory/.public_seed_v1
- Soul/memory/aliases.yaml
- Soul/memory/approved_lessons.md
- Soul/memory/approved_rules.md
- Soul/memory/lessons.md
- Soul/memory/projects.yaml
- Soul/memory/user.yaml
- Soul/skills/downloads/inspect.rb
- docs/ARCHITECTURE.md
- docs/CURRENT_STATE.md
- docs/LAYERED_CONVERSATION_MEMORY.md
- docs/MEMORY_REFLECTION_BRIDGE_AND_EXPORT.md
- docs/assessments/PRIVATE_MEMORY_SEPARATION_REVIEW.md
- docs/overlays/README_REFLECTION_REVIEW.md
- docs/soul/PRIVATE_MEMORY_SEPARATION_BRIEF.md
- lib/soul_core/conversation_memory_snapshot.rb
- lib/soul_core/conversation_memory_store.rb
- lib/soul_core/memory_paths.rb
- lib/soul_core/phase9_memory_reflection_and_export_closeout_assessor.rb
- lib/soul_core/private_memory_migration.rb
- lib/soul_core/reflection_review.rb
- lib/soul_core/storage_retention_assessor.rb
- scripts/soul-private-memory-migration
- scripts/verify-private-memory-separation.rb
```

## Deterministic results

```text
ruby scripts/verify-private-memory-separation.rb                 PASS (12 checks)
ruby scripts/verify-phase9-memory-reflection-and-export-closeout.rb PASS
ruby scripts/verify-storage-retention-a1.rb                     PASS (17 checks)
Ruby syntax checks                                               PASS
git diff --check                                                 PASS
```

The older nested Phase 9 aggregate verifiers still report their pre-existing
cascading Phase 4–8 regression chain as failed even though their own Phase 9
assessments pass. The directly affected Phase 9 closeout and Storage A1 suites
pass; this candidate does not claim the unrelated historical chain as green.

## Live migration result

The repository owner supplied the exact `COPY_PRIVATE_MEMORY_STATE`
confirmation for preview digest
`e56be9a20e3d67e445c0a91bec51f8950f6f3dc92289efd643c0c9cd59dfc453`.

```text
Files copied and verified: 7
Bytes copied and verified: 6,336
Destination file mode: 0600
Private root mode: 0700
Cutover marker written last: yes
Private hashes rechecked after public sanitization: pass
Dashboard-only restart: active; HTTP 200
Model/Core service changes: none
```

After verification, the six Git-tracked owner-state files were replaced with
schema-valid neutral public seeds. The tracked `.public_seed_v1` marker ensures
fresh clones read those defaults while all mutable writes go to ignored private
storage. The original owner state remains byte-identical under the ignored
private root. The ignored legacy conversation ledger was not deleted.

## Local LLM eval results

```text
Not applicable. Path selection, digests, copy integrity, and authority gates
are deterministic and must not be validated or authorized by model output.
```

## Memory keys

```text
Reads: existing shared owner memory files during preview/copy
Writes: byte-identical private copies and one verified cutover marker, only after Gate 2
Forget behavior: none
```

## Lifecycle states touched

```text
- complete
- failed
- awaiting_input
- blocked_for_human_review
```

## Safety and persistence check

```text
Persistent service added: no
Daemon/watcher/schedule/background loop added: no
Network listener added: no
Confirmation gate weakened: no
Legacy source mutation or deletion added: no
Skill-private memory store added: no; this is the shared Soul memory layer
Automatic migration added: no
```

## Known weaknesses

```text
- The first live migration copies state but deliberately leaves tracked legacy
  files unchanged. Public sanitization is Gate 4 after copy verification.
- Git history is not rewritten; previously published content remains historical
  until a separate risk-reviewed remediation is chosen.
- Approved lessons/rules remain Markdown append logs; this slice changes their
  privacy boundary, not their data model.
```

## Human review checklist

```text
[x] Preview contains all expected legacy files and no unknown paths
[x] File counts, byte totals, and hashes are plausible
[x] Source retention and rollback boundary are understood
[x] Exact live copy is approved
[x] Post-copy verification succeeds before public sanitization
[x] No unapproved persistence, deletion, or semantic memory change
```

## Human review outcome

```text
Outcome: approved
Reviewer: repository owner
Date: 2026-07-18
Decision summary: Exact private-state copy authorized, verified, sanitized, and approved with the completed slice.
Required changes:
```
