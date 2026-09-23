# Atelier CIS A2 source curation — 2026-09-23

Status: source candidate for human merge review. The earlier owner review records
an accepted, installed and independently checked host transaction. This
curation did not read or change live sysctl, audit, PAM, sudo, Docker, WinBoat,
or Wazuh state.

The bounded CLI implements the three reviewed controls: disable IPv4 redirect
sending and secure redirects while preserving forwarding; audit user-originated
mount syscalls; and require wheel membership for `su`. It uses an exact plan
digest, confirmation phrase, baseline hash, atomic file replacement and
rollback. The source adds no daemon or general privileged command surface.

The public Makefile offers deterministic verification and an unprivileged plan.
Install, remove and root status require direct, explicitly reviewed CLI
invocation; no Make variable is interpolated into a privileged shell recipe.

`make verify-atelier-cis-hardening-a2`, Ruby syntax and `git diff --check` pass
in the isolated source worktree. Host scan IDs, hashes and operational receipts
remain in the owner's private review material. A later deployment must repeat
fresh host preflight and read-back; this source check does not authorize one.
