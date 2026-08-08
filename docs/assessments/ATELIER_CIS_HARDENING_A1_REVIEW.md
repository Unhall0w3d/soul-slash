# Atelier CIS Hardening A1 Review

Status: candidate — live root transaction and fresh Wazuh scan pending

## Candidate summary

This slice translates the Operator's 2026-08-08 CIS decisions into four exact,
reversible root-owned configuration files. It adds no credential, passwordless
authority, generic privileged command surface, service, timer, watcher, or
background process.

## Files changed

- `lib/soul_core/atelier_cis_hardening.rb`
- `scripts/soul-atelier-cis-hardening`
- `scripts/verify-atelier-cis-hardening-a1.rb`
- `Makefile`
- `docs/soul/ATELIER_CIS_HARDENING_A1_BRIEF.md`
- `docs/assessments/ATELIER_CIS_HARDENING_A1_REVIEW.md`
- `config/project_tracker_seed.json`

## Deterministic verification

Run:

```text
make verify-atelier-cis-hardening
```

The verifier covers:

- digest-bound human confirmation;
- explicit approved controls and reviewed exceptions;
- absence of password storage, passwordless authority, arbitrary commands, and
  newly added persistent processes;
- stale-digest rejection;
- exact file contents and modes in an isolated fixture root;
- owner-private sudo evidence creation;
- drifted-path collision rejection; and
- exact configuration removal while retaining sudo evidence.

## Memory and lifecycle

No Soul memory keys or skill-private memory are added. The owner-private
Project Timeline and scan-bound Wazuh posture remain the durable review
surfaces. The foreground transaction uses `blocked_for_human_review`,
`awaiting_input`, `complete`, and `failed` lifecycle outcomes.

## Known limits

- The existing `auditd` service must already be installed and active.
- The live rule load may expose pre-existing audit-rule ordering or immutable
  mode problems. Such a failure must remain visible and must not be bypassed.
- The broader event coverage may increase audit volume. Live acceptance must
  observe volume before final validation.
- Wazuh may retain raw findings because its Arch policy contains duplicate and
  older rule assumptions. Adapted review remains separate from raw scoring.

## Human review checklist

- [x] Operator chose the five controls and four exceptions.
- [ ] Review the exact plan digest.
- [ ] Run the one-shot root installation.
- [ ] Confirm all four managed files are exact.
- [ ] Confirm DCCP resolves to the deny rule.
- [ ] Confirm `perm_mod`, `access`, and `delete` are live audit keys.
- [ ] Exercise one sudo command and confirm `/var/log/sudo.log` records it.
- [ ] Observe audit volume during ordinary desktop use.
- [ ] Run a fresh Wazuh SCA scan.
- [ ] Create a new scan-bound adapted posture with zero open decisions.
