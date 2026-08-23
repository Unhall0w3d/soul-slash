# e1000e Hardware-Hang Recovery A0 Review

## Candidate summary

A0 adds an explicitly authorized persistent recovery observer for the identical
Intel `e1000e` transmit-ring hang reproduced on Forge and Foundry. It follows
new kernel records, matches one exact fault signature, and cycles only `nic0`
with a 60-second cooldown.

## Files changed

- `docs/soul/E1000E_HARDWARE_HANG_RECOVERY_A0_BRIEF.md`
- `scripts/soul-e1000e-recovery`
- `config/systemd/soul-e1000e-recovery.service`
- `scripts/verify-e1000e-hardware-hang-recovery-a0.sh`
- `docs/assessments/E1000E_HARDWARE_HANG_RECOVERY_A0_REVIEW.md`

## Review evidence

- Risk: privileged, persistent, narrowly bounded network recovery.
- Persistent state: one root-owned enabled systemd service per affected host.
- Network listener: none.
- Scheduled polling: none; new kernel events are followed from journald.
- Mutation authority: down/up of fixed `e1000e` interface `nic0` only.
- Memory keys: none.
- Soul skill lifecycle states: none; this is host recovery infrastructure.

## Human checklist

- [x] Deterministic verifier passes.
- [x] Forge target validation passes.
- [x] Foundry target validation passes.
- [x] Unit is enabled and active on both hosts.
- [x] systemd hardening review passes without blocking journal access or link
      mutation.
- [ ] A future naturally occurring hang produces one recovery pair and restores
      host and guest reachability.
- [ ] Human approves commit and publication separately.

## Live installation evidence

On 2026-08-20, the exact candidate helper, unit, and brief were installed on
Forge and Foundry. Both helpers returned `e1000e:nic0:ready`; both units passed
`systemd-analyze verify`, were enabled for `multi-user.target`, entered active
state, and reported zero restarts after startup. No synthetic link interruption
was performed. Temporary deployment copies were removed from both hosts.
