# Atelier CIS Hardening A1 Review

Status: accepted — live-installed; post-install SCA refresh deferred

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
- The broader event coverage may increase audit volume. Routine security review
  should continue to observe it after acceptance.
- Wazuh may retain raw findings because its Arch policy contains duplicate and
  older rule assumptions. Adapted review remains separate from raw scoring.

## Live acceptance evidence

The Operator completed the digest-bound root installation and the privileged
status verifier on 2026-08-08. The accepted transaction established all four
exact managed files and loaded the three audit key families. Independent
non-root follow-up confirmed that:

- DCCP resolves to `install /bin/false`;
- `auditd` and `wazuh-agent` remain active and enabled;
- the audit, logrotate, and module-denial files retain their reviewed modes;
- `/var/log/sudo.log` is owner-private and received evidence from the live
  verification; and
- no new Soul service, timer, listener, watcher, credential, or generic
  privileged execution surface was introduced.

The Operator accepted this implementation as complete on 2026-08-08. A fresh
Wazuh SCA scan and new scan-bound adapted posture were not run and are recorded
as deferred routine security follow-up. No refreshed score or scan evidence is
claimed by this review.

## Human review checklist

- [x] Operator chose the five controls and four exceptions.
- [x] Review the exact plan digest.
- [x] Run the one-shot root installation.
- [x] Confirm all four managed files are exact.
- [x] Confirm DCCP resolves to the deny rule.
- [x] Confirm `perm_mod`, `access`, and `delete` are live audit keys.
- [x] Exercise one sudo command and confirm `/var/log/sudo.log` records it.
- [ ] Deferred follow-up: observe audit volume during ordinary desktop use.
- [ ] Deferred follow-up: run a fresh Wazuh SCA scan.
- [ ] Deferred follow-up: create a new scan-bound adapted posture.
