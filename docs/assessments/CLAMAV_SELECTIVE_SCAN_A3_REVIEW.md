# ClamAV Selective Scan A3 Review

## Status

The Operator workstation and Fedora plaintext restore-staging endpoint are
live-qualified. No other current fleet role has a useful approved ClamAV ingress
target.

## What was implemented

- Portable, public-safe policy for two explicit ingress target classes.
- One foreground standalone scanner with real-path confinement, whole-operation
  timeout, resource limits, official signatures, and immutable source behavior.
- Owner-private mode-0600 raw log and JSON receipt for every attempted scan.
- Makefile checks, one-click Downloads scan target, and deterministic verifier.
- Platform guidance for a daily bounded signature update without `clamd` or
  on-access scanning.
- Exact repair of the Fedora pilot's unrelated broad cloud-init passwordless
  sudo rule, preserving wheel sudo and the digest-bound maintenance helper.

## Files changed

- `config/clamav_scan_policy.json`
- `scripts/soul-clamav-scan`
- `scripts/verify-clamav-bounded-scan-a3.rb`
- `Makefile`
- `docs/soul/CLAMAV_SELECTIVE_SCAN_A3_BRIEF.md`
- `docs/assessments/CLAMAV_SELECTIVE_SCAN_A3_REVIEW.md`
- `docs/guides/SECURITY_MONITORING.md`
- `docs/ROADMAP.md`
- `config/project_tracker_seed.json`

## Deterministic test results

`ruby scripts/verify-clamav-bounded-scan-a3.rb` passes:

- clean scan termination and no mutation;
- owner-only receipt and raw log permissions;
- detection blocks for human review without deleting its fixture;
- scanner errors terminate failed;
- total timeout terminates failed;
- a path outside the approved ingress root is rejected.

## Operator-workstation live results

- Distribution-signed Arch package `clamav 1.5.3-1` is installed.
- Official databases initialized successfully with daily revision 28079,
  main revision 63, and bytecode revision 339; database self-tests passed.
- `clamav-freshclam-once.timer` is enabled and active with its next daily run
  scheduled. `clamav-daemon`, `clamav-clamonacc`, continuous freshclam, and the
  daemon socket remain disabled.
- The first bounded Downloads scan inspected 5 inputs/archives and 171.95 MiB
  after expansion against 3,627,984 known signatures in 111.2 seconds.
- A second scan was unintentionally started while the command runner had
  detached from the first receipt; it overlapped briefly, terminated normally
  in 112.5 seconds, and returned the identical result.
- Both scans found zero infected files and report no source mutation,
  quarantine, move, or deletion.
- Raw output and structured receipts are owner-only mode `0600` in ignored
  private state.

## Fedora live results

- Fedora repository packages `clamav 1.4.5-1.fc44` and
  `clamav-freshclam 1.4.5-1.fc44` are installed.
- Official signature revision matches the Operator workstation; the daily
  update timer is enabled and active while continuous freshclam and resident
  scanning remain disabled.
- `/srv/soul-backup/restore-staging` is the only approved target and is owned by
  the maintenance user mode `0700`; the encrypted Restic repository is
  excluded.
- The empty staging baseline loaded 3,627,984 signatures and completed cleanly
  in 9.01 seconds.
- A temporary password was set through the hypervisor solely for the reviewed
  setup, then locked by an exit trap. The one-time script was removed,
  arbitrary passwordless sudo remains denied, and the digest-bound maintenance
  self-check still passes.

## Fleet placement decision

- Operator workstation: qualified for Downloads and explicit import staging.
- Fedora backup endpoint: qualified only for plaintext restore staging.
- Proxmox hypervisors: excluded because VM/LXC images and storage are opaque,
  high-churn, duplicated targets; scan inside the relevant guest instead.
- DNS appliance: excluded because it has no file-ingress role and security
  value comes from patching, configuration integrity, and service telemetry.
- NixOS maintenance laboratory: excluded because it has no ingress/staging
  role, only a maintenance account, and a read-only Nix store. If its role
  changes, ClamAV must be added declaratively through its reviewed NixOS module.

## Known weaknesses

- A clean signature scan is evidence, not proof that a file is safe.
- The workstation now has an explicitly qualified community-packaged Wazuh
  agent, but A3 does not yet centralize its scan receipts.
- The Fedora endpoint's Wazuh agent does not yet collect the private scan
  receipt. End-to-end ClamAV detection/log-decoder testing remains a separate
  non-destructive sub-gate; the encrypted Restic repository remains
  intentionally unscanned.
- No recurring file scan exists. Only signature updates are scheduled.

## Local-model evaluation

None. LLM output cannot approve malware findings, scan scope, or persistent
security infrastructure.

## Memory keys added or used

None.

## Lifecycle states touched

`complete`, `failed`, and `blocked_for_human_review`.

## Risk classification

Persistent signature-update timer plus bounded foreground file inspection.
Source mutation, on-access monitoring, resident scanning, and automatic
response are excluded.

## Human review checklist

- [x] Confirm the Operator-workstation package and initial signatures are current.
- [x] Confirm only the daily freshclam timer is enabled.
- [x] Review the first private Downloads scan outcome and resource cost.
- [x] Confirm no source file was deleted, moved, or quarantined.
- [x] Approve the Fedora plaintext restore-staging sub-gate.
- [x] Decide whether any additional endpoint has a genuine ingress path worth
  scanning; do not equate fleet membership with useful ClamAV placement.
