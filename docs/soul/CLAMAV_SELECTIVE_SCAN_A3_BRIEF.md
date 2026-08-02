# ClamAV Selective Scan A3 Brief

## Status

```text
operator_rollout_approval: 2026-08-02
operator_workstation_pilot_authorized: yes
fedora_plaintext_staging_authorized: yes
hypervisor_vm_storage_scan_authorized: no
dns_appliance_scan_authorized: no
on_access_scan_authorized: no
automatic_quarantine_or_delete_authorized: no
human_finding_review_required: yes
```

## Purpose

Add current malware signatures and bounded foreground scanning at explicit file
ingress boundaries without turning ClamAV into an indiscriminate full-disk or
always-resident endpoint scanner.

The first endpoint is the Operator workstation. Its initial target is the
Operator's Downloads directory. A Fedora backup endpoint may scan only a
separately created plaintext restore-staging directory. Encrypted Restic data,
hypervisor storage, DNS services, models, generated media, and ordinary home
trees remain excluded.

## Runtime decision

Install the distribution-signed ClamAV package and use standalone `clamscan`.
Do not enable `clamd` or on-access scanning. Standalone scans load signatures,
scan one approved target, write an owner-private receipt, and terminate.

Use the distribution's `clamav-freshclam-once.timer` to run one bounded daily
signature update. Run one initial `freshclam` update before the first scan.
This timer is explicitly approved by this brief; no other schedule, watcher, or
resident process is added.

## Approved package families

- Arch/CachyOS: repository package `clamav`.
- Fedora: repository packages `clamav` and `clamav-freshclam`, plus resolved
  signed dependencies.

Package names are fixed by platform. No AUR, third-party signature feed,
unofficial database, remote scanner, or network-facing ClamAV socket is used.

## Scan policy

Tracked defaults live in `config/clamav_scan_policy.json`. Production scanning
uses `/usr/bin/clamscan` and `/usr/bin/timeout` exactly. Test binary overrides
are accepted only when the explicit test-mode environment flag is present.

The first policy:

- permits `downloads` and `import_staging` target classes only;
- accepts an exact target or descendant only after real-path normalization;
- refuses symlink or path traversal outside the selected ingress root;
- has a 15-minute whole-operation timeout;
- refuses cross-filesystem traversal;
- uses official databases only;
- limits file, container, recursion, and per-file scan work;
- writes scan output and structured receipts mode `0600` below ignored private
  state;
- never supplies delete, move, copy, or quarantine options.

Exit code 0 becomes `complete/clean`. Detection exit code 1 becomes
`blocked_for_human_review/detections` and leaves the source untouched. Timeout
or scanner failure becomes `failed`.

## Wazuh evidence

The A3 pilot first proves bounded local receipts. On an endpoint with a passive
Wazuh agent, a later A3 sub-gate may collect an exact ClamAV log through a
reviewed local-file stanza and verify Wazuh's built-in decoder. It must not
expose a Syslog listener or grant Active Response.

The Operator workstation does not have a distribution-supported Wazuh package.
A separately reviewed A2B lane now qualifies one Operator-installed community
package, but A3 does not install or automatically trust that package merely to
centralize a clean-scan receipt.

## Verification

- package identity and signature source are recorded;
- initial signature update succeeds;
- daily update timer is enabled and active;
- `clamd` and on-access services remain disabled;
- bounded scan verifier passes clean, detection, error, timeout, permissions,
  and path-escape cases;
- one real ingress scan terminates with a private receipt;
- no source file is mutated;
- CPU and elapsed time are observed;
- no secrets or owner file names enter tracked artifacts.

## Rollback

Disable the exact daily update timer. Retain or remove the signed package only
through the platform package manager after human review. Removing ClamAV must
not delete source files or Wazuh evidence. Private scan receipts follow the
security evidence retention policy.

## Excluded from A3

- full-disk or full-home scans;
- encrypted backup blobs or VM/LXC storage;
- `clamd`, `clamonacc`, mail filtering, or network sockets;
- automatic deletion, movement, quarantine, or remediation;
- third-party signature feeds;
- unattended scan schedules;
- Wazuh Active Response;
- model-based safety approval.
