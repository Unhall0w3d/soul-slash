# Noctalia Core Control — A1 Brief

## Human-approved objective

Extend the public Soul Overview Noctalia plugin so the Operator can review and
activate Soul's five configured Cores from the desktop panel.

This brief supersedes only the approved-command list and mutation exclusion in
`NOCTALIA_COMPANION_CONTRACT_A0_BRIEF.md`. Its device, SSH, privacy, and
foreground-execution boundaries remain unchanged.

## Approved Cores

- `daily` — Soul Core
- `amd-free` — Soul-Lite Core
- `music` — Creative Core
- `free` — Free Core
- `dev` — Dev Core

Noctalia must not accept a model profile, service, command, or arbitrary Core
identifier from the Operator.

## Required authority flow

1. `status` returns a bounded five-Core inventory and the active Core.
2. Selecting a non-active Core requests a fresh read-only preview.
3. The panel presents the exact source, target, purpose, and whether service
   mutation is required.
4. A separate **Activate** click is the human authority for that exact preview.
5. Soul revalidates Core membership, active-work state, runtime idleness, exact
   confirmation, and the preview digest before changing anything.
6. The operation terminates as complete, failed, awaiting input, or blocked for
   human review; the plugin refreshes status after a terminal result.

## Approved commands

```text
soul-noctalia core-preview --core CORE_ID
soul-noctalia core-activate --core CORE_ID --target-profile PROFILE_ID \
  --confirmation PHRASE --expected-digest SHA256
```

The plugin may construct `core-activate` only from a successful companion
preview retained in service memory. A plugin reload or cancel action discards
the pending preview.

## Safety and lifecycle

- No automatic Core switching.
- No one-click preview-and-execute shortcut.
- No execution while Soul reports active work or uncertain idleness.
- No arbitrary service or shell command.
- No persisted authorization token, confirmation phrase, or preview digest.
- No new listener, daemon, watcher, timer, schedule, or background continuation.
- No maintenance, reboot, deletion, credential, publication, or remote authority.
- A stale digest fails safely and requires a new preview.

## Acceptance

- All five Cores render from Soul's status contract.
- The active Core cannot be selected for activation.
- Preview and execute are distinct gestures.
- Unsafe identifiers and gate fields fail before orchestration.
- Exact CoreOrchestrationService blockers and digest checks remain authoritative.
- Public plugin verification finds no private topology, target, or credential.
- Live review changes Cores only after the second click and refreshes the panel.
