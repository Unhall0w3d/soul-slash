# Model Runtime Portability 2B — Inactive AMD Unit Deployment Brief

```text
implementation_authorized: yes
persistent_unit_authorized: yes
human_authority: repository owner approval on 2026-07-16
milestone: Deployment and Operations
slice: Model Runtime Portability 2B
human_review_required: yes
```

## Objective

Install one exact, reviewed `soul-model-amd.service` systemd user-unit definition
for the already verified Vulkan llama.cpp binary and Ministral model. Reload the
user manager so the unit becomes known, then prove it remains inactive and
unenabled while the existing NVIDIA/Qwen3 rollback stays active and unchanged.

This gate does not start the AMD runtime, stop NVIDIA, switch providers, change
Soul's endpoint, alter the NVIDIA unit/drop-in, or enable either model service.

## Explicit persistence authorization

The owner authorizes creation of exactly:

```text
~/.config/systemd/user/soul-model-amd.service
```

and one bounded:

```text
systemctl --user daemon-reload
```

The unit is persistent host configuration but has no `[Install]` section and
must not be enabled. Installation must not call `start`, `stop`, `restart`,
`enable`, `disable`, or `--now` for any service.

## Pinned host inputs

```text
binary: user-local versioned Vulkan llama-server b9851
binary SHA-256: c7a15d4eaef92e63869db6725f4976943a194ca5741933ed45b9c7ebecf78e68
model: Ministral-3-14B-Instruct-2512-Q4_K_M.gguf
model SHA-256: 824e0f3373e69b84f2cae46fdcb9bd1ebc6ab3bfc7acc125d818b7b8178cc613
device: Vulkan0
bind: 127.0.0.1:8082
temporary compatibility alias: soul-qwen3-8b-q4
```

Machine paths are private installer inputs and must not appear in tracked public
configuration. The installer verifies regular non-symlink files, executable
permission for the server, exact lowercase SHA-256 digests, loopback host,
unprivileged port, bounded alias, and the exact allowlisted unit destination.

The compatibility alias deliberately matches the unchanged live provider
contract. It does not claim the AMD model is Qwen. The dashboard profile label
is authoritative for operator presentation. A neutral shared alias requires a
later reviewed change to both the NVIDIA rollback and Soul `.env`.

## Unit command

The rendered service uses fixed argv with no shell:

```text
<verified llama-server>
-m <verified Ministral GGUF>
-a <shared compatibility alias>
--host 127.0.0.1
--port 8082
-c 8192
-n 2048
-np 1
-ngl 999
-dev Vulkan0
-fa on
--jinja
--metrics
--slots
--reasoning off
--timeout 120
```

It uses `Restart=on-failure`, a bounded stop timeout, owner-only umask, and
systemd hardening that preserves read-only access to the user-local binary/model
and GPU device. It contains no shell interpolation, download, network-external
bind, credential, environment secret, or automatic enablement.

## Deployment workflow

```text
plan -> blocked_for_human_review
install without exact phrase -> awaiting_input
install with exact phrase -> complete / failed
status -> complete / failed
uninstall inactive unit with exact phrase -> complete / failed
```

Install confirmation:

```text
INSTALL_INACTIVE_AMD_MODEL_UNIT
```

Uninstall confirmation:

```text
REMOVE_INACTIVE_AMD_MODEL_UNIT
```

The plan reports exact paths, hashes, argv, and commands. Installation validates
the rendered unit, writes atomically without following symlinks, performs only
`daemon-reload`, and verifies `LoadState=loaded`, `ActiveState=inactive`, and an
unenabled/static unit-file state. Any unexpected active state blocks completion.

Uninstall refuses while AMD is active, removes only a regular non-symlink unit
containing the deployment marker, and reloads the user manager. It never stops
the service implicitly.

## Bounds and prohibitions

```text
unit files written: 1
systemctl mutation commands: daemon-reload only
command timeout: 12 seconds
output cap: 16 KiB
retries: 0
background continuation: prohibited
```

- No AMD start, NVIDIA stop, or model switch.
- No service enablement or login autostart.
- No modification of `llama-server.service` or its drop-in.
- No provider endpoint, alias, or `.env` mutation.
- No binary/model download, build, driver, package, or permission mutation.
- No root/sudo/system service operation.
- No watcher, timer, polling loop, queue, or scheduled work.

## Acceptance

- Plan is read-only and digest-bound to verified inputs and rendered unit.
- Wrong confirmation writes nothing and runs no command.
- Symlink destination, foreign existing unit, digest drift, missing executable,
  non-loopback host, invalid alias, and invalid port fail closed.
- Install command log contains only `systemctl --user daemon-reload` and bounded
  read-only verification commands.
- Installed AMD unit is loaded, inactive, and unenabled/static.
- Existing NVIDIA unit bytes and drop-in bytes are unchanged.
- NVIDIA remains active on the existing loopback provider endpoint.
- Dashboard changes AMD from unavailable to inactive and offers a reviewed
  Switch action, but no switch is executed.
- Deterministic deployment, runtime-control, dashboard, and Phase 13 regressions
  pass before candidate completion.

## Human review outcome

```text
Outcome: approved for implementation and inactive host installation
Reviewer: repository owner
Date: 2026-07-16
Decision summary: Proceed to the next gate; install and load the AMD unit definition without starting, enabling, or switching it.
```
