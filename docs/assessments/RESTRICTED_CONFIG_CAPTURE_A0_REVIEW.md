# Restricted configuration capture review

## Execution result

The approved graphical pkexec invocation completed successfully. Seven files
were captured and their content hashes validated without displaying contents.
Artifact: `Soul/private/operator_backup/restricted-config-x87bk_si/capture.json`.
The capture changed no source files and started no backup. At collection time, snapshot/replica acceptance was deferred to the next
scheduled backup at the Operator's request; its result is recorded below.

Candidate reviewed before privileged execution. Risk: fixed privileged reads
of credential-bearing configuration, with owner-private output.

Implementation: `scripts/soul-restricted-config-capture.py` reads exactly the
two Soul audit rule files, PAM su, the Soul sudo logging rule, its logrotate
file, SNMP configuration, and Alloy configuration. No caller-selected root
path, system write, restore, service, or schedule is exposed. The collector
requires root and the caller requires non-root. pkexec is explicitly invoked
with a 120-second bound and isolated Python import behavior.

Recovery artifact: a unique private directory below
`Soul/private/operator_backup`, with `capture.json` containing base64 file
contents, SHA-256, original numeric uid/gid, mode, size, and modification time.
Base64 is not encryption: local protection is owner-private permissions;
off-device protection is the existing encrypted Restic workflow. No contents
are logged. Original permissions are unchanged. ACLs, xattrs, capabilities,
and automatic restoration are not supported by this candidate.

Validation: `python3 -I scripts/verify-restricted-config-capture.py` passes
three deterministic tests covering scope, metadata/content fidelity, writable
files, oversized files, leaf/ancestor symlinks, and corrupt hashes.
`git diff --check` passes. No local LLM eval or memory keys apply.

Lifecycle: complete on validated publication; failed on authorization timeout,
unsafe source, or capture error. No background process remains. No new backup manifest entry is required for the Soul profile: it selects
`Soul/private`. The separate Operator profile intentionally excludes the Soul
repository tree, so its snapshots do not cover this artifact.

Human acceptance: inspect the fixed scope; authorize graphical elevation;
verify the completed artifact metadata without displaying contents; confirm
the next scheduled snapshot and replica contain the artifact. Refresh the
capture after later system configuration changes. Do not interpret this
point-in-time export as continuous system coverage.

## Scheduled backup acceptance — 2026-09-24

The 2026-09-23 Soul nightly DRS completed local snapshot
`36d57b4e1a87` (prefix) and replica. Its verified snapshot path inventory
contains the exact capture file, and the completed replica receipt lists that
local snapshot ID in destination lineage. The capture predates the snapshot.
The scheduled backup did not retain its password. This is metadata and replica
lineage proof; no captured contents or restore were opened. The Operator nightly
DRS also completed, but its intentional `Projects/soul/**` exclusion means its
snapshot does not contain the capture. The original profile coverage statement
above is corrected accordingly.
