# Model Runtime Portability 2D — Selected-Profile Startup Brief

```text
implementation_authorized: yes
persistent_oneshot_authorized: yes
autostart_policy_change_authorized: yes
human_authority: repository owner instruction on 2026-07-16
milestone: Deployment and Operations
slice: Model Runtime Portability 2D
human_review_required: yes
```

## Objective

Make Soul's reviewed `selected_profile.json` authoritative when the user systemd
manager starts, without requiring a reboot to install or activate the policy.
Replace NVIDIA-specific enablement with one bounded selector oneshot. The
selector starts at most one allowlisted selected model unit and then exits.

The currently active AMD runtime must not be stopped or restarted during live
installation.

## Explicit persistence authorization

The owner authorizes creation and enablement of exactly:

```text
~/.config/systemd/user/soul-model-runtime-selected.service
```

The unit is `Type=oneshot`, runs one repository-owned bounded command, and is
wanted by `default.target`. It is not a daemon and contains no restart policy,
polling, retry, timer, watcher, network listener, or background continuation.

The owner also authorizes disabling the old NVIDIA-specific startup link:

```text
systemctl --user disable llama-server.service
```

Neither command uses `--now`; neither stops, starts, or restarts the currently
active NVIDIA or AMD model service during installation.

## Startup authority and behavior

The startup selector derives authority only from the locally persisted profile
ID previously written by Soul's human-confirmed runtime controller. It does not
derive authority from LLM output.

On each invocation it:

1. loads the bounded local profile registry and selected profile record;
2. acquires the shared model-runtime control lock;
3. observes every allowlisted profile service once;
4. returns `complete` without mutation if only the selected profile is active;
5. starts only the selected allowlisted unit if all profiles are inactive;
6. verifies that exact unit becomes active; and
7. exits.

It returns `blocked_for_human_review` without mutation when a different profile,
multiple profiles, an unknown service state, unsafe selection file, invalid
registry, unavailable command, or lock contention is observed. It never stops,
switches, enables, disables, reloads, or retries a model service.

When no selection record exists, the reviewed registry default is used.

## Live installation

Installation is preview-first and requires exact confirmation:

```text
INSTALL_SELECTED_MODEL_STARTUP
```

The installer validates the fixed Ruby executable, repository root, selector
script, rendered unit, destination, and current active profile. It then performs
only these bounded user-manager mutations:

```text
systemctl --user daemon-reload
systemctl --user enable soul-model-runtime-selected.service
systemctl --user disable llama-server.service
```

It does not require or request a reboot. The policy is installed immediately;
the currently active AMD runtime continues unchanged. A foreground selector
status/reconciliation command may be run immediately to prove it recognizes the
already active selected profile without mutation.

If selector enablement or NVIDIA disablement fails, installation restores the
prior enablement arrangement where possible and reports `failed` or
`blocked_for_human_review` with bounded command evidence.

Uninstall is separately confirmed with:

```text
REMOVE_SELECTED_MODEL_STARTUP
```

It disables and removes only the managed selector unit, reloads the user
manager, and restores NVIDIA enablement as the legacy fallback. It never changes
the active model runtime.

## Bounds

```text
selector invocations per startup: 1
model start commands per invocation: at most 1
command timeout: 12 seconds
output cap: 16 KiB per command
retries: 0
polling: 0
background continuation: prohibited
```

## Explicit exclusions

- No reboot, logout, dashboard restart, or current model restart.
- No automatic stop, switch, failover, health retry, or fallback start.
- No change to `.env`, profile selection format, provider endpoint, Caddy, UFW,
  model binaries, model files, or either model unit definition.
- No root/system service, timer, cron, watcher, daemon, or network listener.
- No LLM-decided startup, model choice, safety classification, or authorization.

## Deterministic acceptance

- Plan is read-only and discloses exact file and enablement changes.
- Wrong confirmation writes nothing and executes nothing.
- Unit/script/root symlinks, path escape, foreign unit, invalid Ruby executable,
  registry drift, invalid selection, and unknown services fail closed.
- No active profile starts exactly the selected allowlisted service once.
- Selected already active is a mutation-free success.
- Wrong/multiple active profiles, lock contention, start failure, and unexpected
  post-start state terminate explicitly without stop/fallback behavior.
- Installation never invokes `start`, `stop`, `restart`, or `--now`.
- Current AMD PID/service state and all model unit hashes remain unchanged.
- Selector is enabled, NVIDIA is disabled, and neither model unit is restarted.
- Existing runtime-control, profile-switching, deployment, dashboard, and Phase
  13 acceptance regressions pass.

## Human review outcome

```text
Outcome: approved for implementation and live no-reboot installation
Reviewer: repository owner
Date: 2026-07-16
Decision summary: Implement startup persistence without requiring a system reboot.
```
