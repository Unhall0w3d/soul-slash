# Atelier CIS Hardening A1 Brief

## Human decision

On 2026-08-08, the Operator reviewed the nine distinct remaining decisions from
Atelier's scan-bound Wazuh Arch CIS posture. The Operator rejected periodic
password expiration, minimum password age, password-expiration warnings, and
SELinux/AppArmor audit watches on a host where neither MAC framework is active.

The Operator approved:

- a dedicated rotated sudo command log;
- an explicit DCCP module deny;
- audit coverage for permission, ownership, and extended-attribute changes;
- audit coverage for unsuccessful unauthorized file access; and
- audit coverage for file deletion and rename events.

This brief authorizes the exact root-owned configuration files required for
those five controls. It does not authorize a generic privileged helper,
password storage, passwordless sudo, arbitrary command forwarding, automatic
remediation, or a new persistent process.

## Exact managed files

The bounded installer owns only:

- `/etc/sudoers.d/85-soul-sudo-audit`;
- `/etc/logrotate.d/soul-sudo-audit`;
- `/etc/modprobe.d/soul-disable-dccp.conf`; and
- `/etc/audit/rules.d/70-soul-workstation-events.rules`.

It creates `/var/log/sudo.log` as `0600 root:root` only when absent. Removal
retains that evidence rather than deleting it.

The audit rules cover both 64-bit and 32-bit syscall ABIs because Atelier runs
desktop and gaming software that may use either. They select interactive local
identities with `auid>=1000` and exclude unset audit identities. No filesystem
contents are captured by these rules.

## Bounded transaction

The foreground installer must:

1. produce an exact file and plan digest;
2. require that digest and `INSTALL_ATELIER_CIS_HARDENING`;
3. require root only for the reviewed transaction;
4. reject symlinks, pre-existing drift, and path collisions;
5. validate the sudoers and logrotate candidates before installation;
6. write exact root-owned files atomically;
7. load the audit rules through the existing audit service tooling;
8. verify file digests, modes, DCCP denial, and all three live audit keys; and
9. remove newly written files if installation fails.

Removal requires the current digest and `REMOVE_ATELIER_CIS_HARDENING`, refuses
drifted files, reloads the remaining audit rules, and preserves the sudo log.

## Lifecycle and exclusions

The transaction terminates as `complete`, `failed`, `awaiting_input`, or
`blocked_for_human_review`. It never remains running after returning control.

The following remain explicit reviewed exceptions:

- forced periodic password changes;
- a seven-day minimum password age;
- password-expiration warning days; and
- SELinux/AppArmor audit watches without either framework enabled.

A fresh Wazuh scan and a new scan-bound adapted posture are separate live
acceptance steps. Raw Wazuh results must never be rewritten.
