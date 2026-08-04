# Noctalia Companion Contract — A0 Brief

> A1 extension: `NOCTALIA_CORE_CONTROL_A1_BRIEF.md` adds a separately reviewed,
> two-click Core preview/activation flow. All A0 device and privacy boundaries
> remain in force.
>
> A2 extension: `NOCTALIA_INTEGRATED_INVENTORY_A2_BRIEF.md` aligns the dynamic
> fleet with the Dashboard's integrated-inventory boundary while keeping
> status-only presence devices out of the companion and terminal actions
> restricted to Soul's existing opaque allowlist.

## Human-approved objective

Replace the owner-local Soul Overview plugin's embedded fleet topology and SSH
targets with a public-safe, versioned integration boundary. The Noctalia plugin
must render integrated systems dynamically from Soul, associate details and
actions by a stable opaque device ID, and ask Soul to open a selected SSH
session only when Soul supplies that action.

## Boundary

Soul owns:

- enrolled-device discovery and cached status;
- device ID to interactive SSH alias resolution;
- bounded display rows and allowed actions;
- validation before an SSH process is executed.

The plugin owns:

- rendering generic summary and detail rows;
- sending the selected opaque device ID back to Soul;
- opening the foreground terminal that hosts the Soul connection command.

The plugin must not contain or receive resolved SSH aliases, usernames, key
paths, credentials, or hard-coded fleet topology.

## Approved commands

```text
soul-noctalia status
soul-noctalia voice-launch
soul-noctalia connect --device DEVICE_ID
```

All commands are bounded foreground operations. `connect` may replace itself
with `/usr/bin/ssh` only after Soul resolves a known enrolled device ID to a
reviewed private target.

## Contract

`status` returns `soul.noctalia.status.v2`. Fleet cards contain generic
`summary_rows`, `detail_rows`, and an allowlist of action descriptors. Targets
used to execute those actions are intentionally absent.

Newly enrolled SSH devices inherit their reviewed registry alias. Integrated
local, host-local, and read-only network-inventory devices may appear without
actions. Private
`device_actions.json` entries may override that alias when interactive access
must use a different identity from restricted automation.

## Explicit exclusions

- publication or GitHub repository creation;
- maintenance or reboot actions;
- background services, watchers, or new schedules;
- remote probing initiated by the plugin;
- migration of the installed plugin source before live validation.
