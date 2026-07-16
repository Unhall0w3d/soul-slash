# Model Runtime Portability 2B Inactive AMD Unit Review

## Candidate

```text
Name: Inactive AMD Vulkan model user-unit deployment
Risk class: Class 3 persistent host configuration
Status: candidate_complete
Human review required: yes
Date: 2026-07-16
```

## Implementation summary

This slice adds a portable plan/install/status/uninstall workflow for exactly
one `soul-model-amd.service` user unit. Inputs are explicit private paths,
recorded SHA-256 digests, the shared provider alias, loopback host, and port.
Installation validates the rendered unit, writes atomically without following
symlinks, runs only `systemctl --user daemon-reload`, and verifies the unit is
loaded, inactive, and unenabled. It neither starts AMD nor stops NVIDIA.

## Files changed

```text
Makefile
docs/GETTING_STARTED.md
docs/MILESTONES.md
docs/ROADMAP.md
docs/soul/MODEL_RUNTIME_PORTABILITY_2B_AMD_UNIT_BRIEF.md
docs/assessments/MODEL_RUNTIME_PORTABILITY_2B_AMD_UNIT_REVIEW.md
lib/soul_core/model_runtime_profile_deployment.rb
scripts/soul-model-runtime-profile
scripts/verify-model-runtime-profile-deployment.rb
```

## Commands run

```text
ruby -c lib/soul_core/model_runtime_profile_deployment.rb
ruby -c scripts/soul-model-runtime-profile
ruby -c scripts/verify-model-runtime-profile-deployment.rb
ruby scripts/verify-model-runtime-profile-deployment.rb
make verify-model-runtime-controls
```

Host plan/install/status and verification commands completed:

```text
ruby scripts/soul-model-runtime-profile plan <pinned inputs>
ruby scripts/soul-model-runtime-profile install <pinned inputs> --confirmation INSTALL_INACTIVE_AMD_MODEL_UNIT
systemctl --user show llama-server.service soul-model-amd.service --property=Id --property=LoadState --property=ActiveState --property=SubState --property=UnitFileState --no-pager
ruby -Ilib <bounded live ModelRuntimeControlService status projection>
sha256sum <NVIDIA unit> <NVIDIA drop-in> <AMD unit>
curl --silent --show-error --max-time 3 http://127.0.0.1:8082/health
```

## Deterministic results

```text
Inactive AMD deployment verifier: 14/14 checks passed.

Covered:
- read-only plan and exact confirmation
- digest/path/loopback/alias validation
- atomic managed-unit write
- exact daemon-reload-only mutation boundary
- no start, stop, restart, enable, disable, or --now command
- loaded/inactive/static verification
- NVIDIA unit and drop-in byte preservation
- idempotent matching reinstall
- active-unit uninstall refusal
- explicit inactive removal
- symlink destination rejection

Host deployment result:
- server digest: c7a15d4eaef92e63869db6725f4976943a194ca5741933ed45b9c7ebecf78e68
- model digest: 824e0f3373e69b84f2cae46fdcb9bd1ebc6ab3bfc7acc125d818b7b8178cc613
- rendered/installed unit digest: c1e690eb3c07a3f393ad45f3a4b067303833949eb7974df5df7fcff66472dbc7
- NVIDIA base unit digest: bd1b18d7af63213ee2ed63bba514677941eaa2744a4e8ffa84d2dfa4e21
- NVIDIA drop-in digest: c28ade127f915dd3f4042a82a27538325c7d708c58d06d36db2423d3fee1ad3c
- NVIDIA: loaded, active/running, enabled
- AMD: loaded, inactive/dead, static and unenabled
- Soul active profile: nvidia-fallback
- Soul can_switch: true
- existing endpoint health: ok
- start/stop/enable/switch commands executed: none

Regression result:
- complete Model Runtime Portability chain: passed
- Phase 12C dashboard and earlier chain: passed
- Phase 13A integrated acceptance: passed
- Phase 13C milestone closeout: passed
- staged whitespace validation: passed
```

## Local LLM evaluation

```text
Not run. The model was behaviorally evaluated in the accepted alternate-port
slice. LLM output cannot authorize persistent service configuration.
```

## Memory and lifecycle

```text
Durable user memory: none
Skill-private memory: none
Persistent state: one reviewed systemd user-unit file
Lifecycle states: complete, failed, awaiting_input, blocked_for_human_review
Background continuation: none
```

## Safety and persistence check

```text
Persistent service unit added: authorized, exactly one inactive user unit
Service enabled: no
Service started: no
NVIDIA stopped or modified: no
Provider endpoint or .env changed: no
Daemon/watch/timer/cron added: no
Automatic switch/failover/retry added: no
Confirmation gate weakened: no
Root or sudo action added: no
```

## Known weaknesses

```text
- The compatibility alias temporarily retains the Qwen-oriented name so the
  unchanged provider and NVIDIA rollback remain interoperable.
- Unit installation proves systemd load state, not inference readiness.
- The AMD service remains untested as a persistent unit until the separately
  approved first-switch gate.
- Removing an active unit is intentionally blocked and requires explicit unload.
```

## Human review checklist

```text
[ ] Review exact rendered unit argv and hardening.
[ ] Confirm server/model digests match accepted evidence.
[ ] Confirm the unit has no Install section and is unenabled.
[ ] Confirm AMD remains inactive.
[ ] Confirm NVIDIA unit/drop-in hashes and active state remain unchanged.
[ ] Confirm dashboard shows AMD inactive and does not switch automatically.
[ ] Approve or reject the first live AMD switch as a separate gate.
```

## Human review outcome

```text
Outcome: approved
Reviewer: repository owner
Date: 2026-07-16
Decision summary: Approved the inactive, unenabled AMD unit deployment and authorized proceeding to the separately gated first live AMD switch.
Required changes: none
```
