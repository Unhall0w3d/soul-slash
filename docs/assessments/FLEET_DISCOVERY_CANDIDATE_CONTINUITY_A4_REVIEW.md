# Fleet Discovery Candidate Continuity A4 Review

```text
date: 2026-07-28
candidate_state: live-accepted
risk: Class 1 Dashboard session-state correction
human_review: accepted by the Operator
```

## What was implemented

- Enrollment removes only the enrolled address from the ephemeral candidate
  list.
- Ignore removes only the ignored address.
- Restore and private-registry removal preserve every current candidate.
- Candidate counts and status copy update without another subnet scan.
- A fresh explicit scan remains the only operation that replaces the full
  candidate list with fresh network evidence.

## Files changed

- `assets/dashboard/dashboard.js`
- `scripts/verify-maintenance-fleet-discovery-a1.rb`
- `docs/soul/FLEET_DISCOVERY_CANDIDATE_CONTINUITY_A4_BRIEF.md`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `config/project_tracker_seed.json`
- `docs/assessments/FLEET_DISCOVERY_CANDIDATE_CONTINUITY_A4_REVIEW.md`

## Deterministic validation

```text
node --check assets/dashboard/dashboard.js
ruby -rjson -e 'JSON.parse(File.read("config/project_tracker_seed.json"))'
make verify-maintenance-fleet-discovery
make verify-maintenance-fleet-dhcp-identity
make verify-project-timeline
git diff --check
```

The discovery verifier checks exact-address filtering, preservation copy,
fresh-scan replacement, and the absence of any whole-list clear after the
four relevant actions.

## Local LLM evals

None. This is deterministic Dashboard session-state behavior.

## Known weaknesses

- Candidate results remain intentionally page-session-only and disappear on a
  full page reload.
- An enrolled device removed from the registry requires a fresh explicit scan
  to appear as a candidate because it was not part of the prior actionable
  result set.

## Memory and lifecycle

- Shared memory keys added or used: none.
- Existing bounded lifecycle states are unchanged.
- No scan, process, timer, watcher, listener, or background continuation was
  added.

## Human review checklist

- [x] Scan a subnet with multiple candidates.
- [x] Act on one and confirm the unrelated candidates remain.
- [x] Confirm the candidate list and count continue to support sequential work.
- [x] Approve merge.

Live acceptance was completed by the Operator on 2026-07-28, who confirmed
that the corrected workflow worked well without an unnecessary rescan.
