# Codex `danger-full-access` A0 Audit

Date: 2026-09-21

## Scope

This is a read-only dependency audit supporting a later decision about changing
Soul's project default from `danger-full-access` to `workspace-write`. It does
not change the default, grant new authority, or assert that lexical matches are
live requirements.

The source inventory covered `scripts/`, `lib/`, `deploy/`, `bin/`, and
`config/`. A broad lexical census found files containing:

| Signal | Files |
| --- | ---: |
| `/etc/` | 38 |
| `systemctl`, `systemd-run`, or `loginctl` | 92 |
| `sudo` or `pkexec` | 45 |
| `/dev/` | 29 |
| `/run/` | 15 |
| Ruby network listener/client primitives | 53 |
| `ssh`, `scp`, or `rsync` | 36 |
| `curl` or `wget` | 24 |
| Docker or Podman | 8 |

These counts include tests, fixtures, documentation-bearing configuration, and
the advisory classifier itself. They describe review surface, not the number of
operations requiring full access.

## Access classes

### Repository work

Source edits, deterministic fixtures, schemas, documentation, and most syntax
or unit verification fit `workspace-write`. No evidence shows that ordinary
implementation needs unrestricted host writes.

### Read-only host observation

Host status paths read files such as `/etc/os-release`, `/proc`, `/sys`, and
systemd status. These require host visibility but not unrestricted mutation.
Examples include `BoundedHostSystemStatusAssessor` and the Proxmox lockup
collector. The latter is intentionally executed by the operator on the target
hypervisor and is not a reason for the local Codex project default to be full
access.

### Owner-home and user-service mutation

Dashboard deployment, selected model runtimes, generated user units, runtime
models, and desktop integration can write outside this checkout or control
`systemctl --user`. These operations are legitimate only at an approved
deployment gate. They should use explicit escalation rather than inheriting
unrestricted access for unrelated repository work.

### System mutation

Reviewed deployment surfaces install into `/etc`, `/usr/local`, `/var`, system
unit directories, sudoers, PAM, audit, sysctl, observability, logging, or Wazuh
configuration. Representative paths include:

- `deploy/observability/collector/install-collector.sh`
- `deploy/observability/central/install-central.sh`
- `deploy/network-syslog/crucible/install.sh`
- `deploy/maintenance/debian-apt/install-authority.sh`
- `lib/soul_core/atelier_cis_hardening.rb`
- `lib/soul_core/atelier_cis_hardening_a2.rb`

These are real exceptional privilege paths. Their existence supports explicit
escalation and dedicated review; it does not support full access as the default
for mapping, review, or ordinary implementation.

### Hardware and desktop interfaces

GPU, audio, microphone, display, and device qualification can require `/dev`,
DRM, PipeWire, Hyprland sockets, or related runtime interfaces. Deterministic
tests generally substitute fixtures, while live qualification should be an
explicitly authorized escalation because it crosses from repository validation
into machine interaction.

### Local and remote sockets

Soul uses loopback listeners and clients for dashboard, OAuth, model endpoints,
and test harnesses. It also uses LAN HTTP/SNMP and SSH/SFTP/rsync for fleet
status, maintenance, backups, and observability. The classes differ:

- fixture-only tests can often remain sandboxed;
- loopback integration checks may need a narrowly enabled network capability;
- live LAN or Internet access should be explicit to the task;
- remote mutation, maintenance, backup, and reboot remain primary-only and
  independently verified.

### Persistence

The repository intentionally contains reviewed service and timer deployment
paths. Persistence requires explicit current authorization, an approved brief,
deterministic verification, rollback visibility, and a review artifact. It does
not require the parent session to begin in unrestricted mode.

## Finding

No ordinary repository-development requirement was found that inherently needs
`danger-full-access` as the project default. Legitimate exceptions exist for:

1. writes outside the checkout, including owner-home deployment;
2. system configuration and service control;
3. hardware and desktop integration;
4. live local, LAN, Internet, and remote-host sockets;
5. privileged or persistent qualification.

Each exception is task-specific and can be represented as explicit escalation.
The remaining uncertainty is operational ergonomics: some live acceptance
harnesses may make several related socket or hardware calls and should be
qualified under `workspace-write` before the default changes.

## Recommended qualification before changing the default

1. Start a fresh Soul session with `workspace-write`.
2. Confirm mapper and reviewer remain read-only in effective runtime state.
3. Confirm implementer can edit and test repository-owned paths.
4. Exercise one loopback-only verifier and record whether it needs escalation.
5. Preview, but do not execute, one owner-home/user-systemd deployment path.
6. Exercise one explicitly escalated live hardware or LAN status check.
7. Confirm `/etc`, system service, remote mutation, and persistence operations
   fail without escalation.
8. Confirm an approved escalation succeeds and remains attributable to the
   exact operation.

Only after that qualification should `.codex/config.toml` move to
`sandbox_mode = "workspace-write"`.

## Project-default repair and bounded qualification — 2026-09-24

With the Operator's approval to proceed, the ignored project-local
`.codex/config.toml` was changed from `danger-full-access`/`never` to
`workspace-write`/`on-request`; other keys were preserved. An owner-only copy
of the prior file is retained under
`Soul/private/operations/baseline-stabilization-20260923/`. No global setting
was changed in this action.

A separate Codex CLI `doctor --json` reported restricted filesystem sandbox
and OnRequest approvals. A no-model CLI sandbox probe with the Soul project
selected allowed repository writes while denying protected `.git` and
`.codex` writes, an outside-home write, and loopback. Read-only profile
denied all probe writes and loopback. Soul's 13-check operational-readiness
verifier passed inside the workspace profile. The maintenance-resume
deployment `plan` returned `blocked_for_human_review` with no mutation. An
explicitly escalated host read saw HTTP 200 from the dashboard and model
health endpoints; that is not an in-sandbox exception.

These are configuration and no-model sandbox checks. This Annex-hosted task
did not start a fresh interactive Soul Codex session or exercise its live
approval prompt, so the exact future task's effective permissions remain a
first-session qualification gate. See the official OpenAI Docs on
[configuration precedence](https://learn.chatgpt.com/docs/config-file/config-basic)
and [sandbox versus approval controls](https://learn.chatgpt.com/docs/sandboxing).
