# Noctalia Companion Contract — A0 Brief

## Human-approved objective

Replace the owner-local Soul Overview plugin's embedded fleet topology and SSH
targets with a public-safe, versioned integration boundary. The Noctalia plugin
must render devices dynamically from Soul, associate details and actions by a
stable opaque device ID, and ask Soul to open the selected SSH session.

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

Newly enrolled SSH devices inherit their reviewed registry alias. Private
`device_actions.json` entries may override that alias when interactive access
must use a different identity from restricted automation.

## Explicit exclusions

- publication or GitHub repository creation;
- maintenance or reboot actions;
- background services, watchers, or new schedules;
- remote probing initiated by the plugin;
- migration of the installed plugin source before live validation.
