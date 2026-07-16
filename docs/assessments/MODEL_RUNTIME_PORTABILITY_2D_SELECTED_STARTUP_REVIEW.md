# Model Runtime Portability 2D — Selected-Profile Startup Review

## Candidate

```text
date: 2026-07-16
status: candidate_complete
risk class: Class 3 — approved persistent user-startup policy
human review required: yes
```

## What was implemented

- Added a bounded selected-profile starter that uses the existing profile
  registry, `selected_profile.json`, lease/control lock, and allowlisted systemd
  user-unit names.
- Added an exact-confirmation deployment workflow for one systemd user oneshot.
- Enabled `soul-model-runtime-selected.service` and disabled the old
  NVIDIA-specific `llama-server.service` startup link without `--now`.
- Preserved the active AMD/Ministral process without a restart.
- Added public Make targets and setup documentation for plan, install, status,
  foreground reconciliation, and separately confirmed removal.

At user-manager startup, the selector starts at most the last human-confirmed
profile and exits. If that profile is already active it completes without
mutation. A wrong or conflicting active profile, uncertain state, unsafe
selection, lock contention, or failed start blocks or fails without an
automatic stop, retry, switch, or fallback.

## Files changed

```text
Makefile
docs/GETTING_STARTED.md
docs/MILESTONES.md
docs/ROADMAP.md
docs/soul/MODEL_RUNTIME_PORTABILITY_2D_SELECTED_STARTUP_BRIEF.md
docs/assessments/MODEL_RUNTIME_PORTABILITY_2D_SELECTED_STARTUP_REVIEW.md
lib/soul_core/model_runtime_selected_starter.rb
lib/soul_core/model_runtime_startup_deployment.rb
scripts/soul-model-runtime-start-selected
scripts/soul-model-runtime-startup
scripts/verify-model-runtime-selected-startup.rb
```

## Live deployment evidence

```text
selector unit: soul-model-runtime-selected.service
selector unit SHA-256: 79d477a07372c684467273b357feba36a622b72ebd1231ed14210c3c54b1d951
selector unit state: enabled, inactive after successful oneshot completion
legacy NVIDIA unit state: disabled, inactive
active profile: amd-quality
AMD service state: active/running
AMD MainPID before installation: 347396
AMD MainPID after installation and reconciliation: 347396
reboot performed: no
model start/stop/restart during installation: none
```

The installed unit passed live `systemd-analyze --user verify`. Invoking it once
through the live user manager completed with `Result=success` and
`ExecMainStatus=0`. A direct foreground reconciliation reported:

```text
selected_profile_id: amd-quality
nvidia-fallback: inactive
amd-quality: active
started: false
automatic_stop: false
retries: 0
```

This demonstrates that the new policy is active now; no reboot was needed to
install or verify it.

## Commands run

```text
scripts/soul-model-runtime-startup plan
scripts/soul-model-runtime-startup install --confirmation INSTALL_SELECTED_MODEL_STARTUP
scripts/soul-model-runtime-start-selected --root /home/bhones/Projects/soul
systemd-analyze --user verify ~/.config/systemd/user/soul-model-runtime-selected.service
systemctl --user start soul-model-runtime-selected.service
make verify-model-runtime-controls
ruby scripts/verify-phase13b-local-model-dashboard-acceptance.rb
ruby scripts/verify-live-persona-contract.rb
git diff --check
```

## Deterministic test results

```text
selected-profile startup verifier: pass, 14 checks
model-runtime portability verifier: pass
multi-profile switching verifier: pass
inactive AMD deployment verifier: pass
Phase 13B dashboard/local-model contract verifier: pass
live persona contract verifier: pass
whitespace validation: pass
```

Coverage includes mutation-free already-active behavior, exact selected-unit
start, wrong-active conflict, single-attempt start failure, unsafe selection,
read-only planning, wrong confirmation, exact enablement changes, bounded unit
shape, absence of model lifecycle commands during installation, no-reboot
status, idempotence, prohibited starter primitives, and explicit persistence
authorization.

## Local LLM evaluation results

No new local LLM evaluation was run because this slice changes only deterministic
startup coordination and does not change prompts, routing, provider behavior, or
model output. The accepted Phase 2C 20-turn AMD evaluation remains the applicable
behavioral evidence. Local model output is not used as safety or startup
authorization.

## Memory keys

```text
durable user-memory reads: none
durable user-memory writes: none
shared runtime read: Soul/runtime/model_runtime/selected_profile.json
shared coordination: Soul/runtime/model_runtime/control.lock and leases/
new private memory store: none
```

## Lifecycle states touched

```text
complete
failed
awaiting_input
blocked_for_human_review
```

The selector invocation always terminates. The separately approved selected
model service may remain active after the oneshot exits.

## Known weaknesses

- The unit pins the repository path and current Ruby executable. Moving the
  checkout or replacing that Ruby requires reinstalling the selector unit.
- A selected model start failure does not fall back automatically. This is
  deliberate fail-closed behavior and requires operator review.
- The policy runs when the user's systemd manager starts. Starting it before an
  interactive login depends on the host's user-linger/session configuration;
  this slice does not change linger settings.
- The dashboard does not yet display whether the startup selector is enabled.
- The temporary provider alias still names Qwen while AMD/Ministral is active;
  that coordinated alias cleanup remains separate.

## Safety and persistence check

```text
Persistent unit added: yes, explicitly approved bounded oneshot
Daemon or long-running selector added: no
Timer/watcher/cron/scheduled loop added: no
Network listener added: no
Model service restarted during install: no
Automatic stop/switch/fallback added: no
Retries or polling added: no
Legacy NVIDIA startup disabled: yes, explicitly approved, without --now
Current AMD runtime interrupted: no
Confirmation or active-work gate weakened: no
LLM output treated as authority: no
Provider/LAN configuration changed: no
Cloud request made: no
```

## Human review checklist

```text
[x] Review exact persistent oneshot scope and no-reboot installation
[x] Confirm selector starts only the shared human-selected allowlisted profile
[x] Confirm unexpected active state blocks without automatic stop
[x] Confirm install contains no model start/stop/restart or --now
[x] Confirm AMD PID and live endpoint remained unchanged
[x] Confirm Qwen autostart is disabled and selector autostart is enabled
[x] Review deterministic regressions and known weaknesses
[x] Approve candidate for commit and merge
```

## Human review outcome

```text
Outcome: approved
Reviewer: repository owner
Date: 2026-07-16
Decision summary: Approved the bounded selected-profile startup policy and live no-reboot deployment.
Required changes: none
```
