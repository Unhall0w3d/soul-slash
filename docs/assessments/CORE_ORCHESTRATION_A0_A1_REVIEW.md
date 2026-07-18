# Core Orchestration A0-A1 Review

## Candidate status

```text
date: 2026-07-18
status: approved_for_commit
risk: Class 3 - manually controlled local runtime mutation
live Core transition performed: yes
default Core changed: no
selected profile changed: no
human visual review: approved by the owner on 2026-07-18
```

## Implementation summary

Soul now has a bounded Core layer above the existing model-runtime controller.
The authenticated top bar exposes Daily Core and AMD-Free Core from explicit
profile roles. Activating a Core resolves one exact target profile, reuses the
existing idle/lease/activity checks, preview digest, click-bound exact
confirmation, and allowlisted service switch, then records only the last
successful profile choice for each Core.

Daily Core keeps AMD chat active and leaves NVIDIA available to ACE-Step on
demand. AMD-Free Core moves chat to Qwen on NVIDIA and visibly holds the Music
Studio lane until the Operator returns to Daily Core. Music Studio is not
misrepresented as a Core, and Soul does not attempt to colocate Qwen and
ACE-Step.

## Files changed

```text
Makefile
Soul/config/model_runtime_profiles.example.yaml
assets/dashboard/dashboard.css
assets/dashboard/dashboard.js
assets/dashboard/index.html
docs/CURRENT_STATE.md
docs/ROADMAP.md
docs/RUNTIME_PROVIDERS.md
docs/soul/CORE_ORCHESTRATION_A0_A1_BRIEF.md
docs/assessments/CORE_ORCHESTRATION_A0_A1_REVIEW.md
lib/soul_core/application_contract.rb
lib/soul_core/application_facade.rb
lib/soul_core/core_orchestration_service.rb
lib/soul_core/model_runtime_profile_registry.rb
scripts/verify-core-orchestration.rb
scripts/verify-gemma-core-dashboard.rb
```

The ignored private host inventory was changed only to classify the existing
NVIDIA fallback as `reserve-chat`. It contains no new address, path, model, or
credential and is not part of the public candidate.

## Commands run

```text
ruby -c lib/soul_core/core_orchestration_service.rb
ruby -c lib/soul_core/application_facade.rb
node --check assets/dashboard/dashboard.js
ruby scripts/verify-core-orchestration.rb
make verify-model-runtime-controls
ruby scripts/verify-gemma-core-dashboard.rb
ruby scripts/verify-phase12c-foreground-dashboard.rb
make verify-music-studio-a3
systemctl --user restart soul-dashboard.service
systemctl --user is-active soul-dashboard.service
bounded exact-confirmed Daily -> AMD-Free -> Daily live acceptance
git diff --check
```

## Deterministic test results

```text
Core grouping, target selection, digest delegation, stale digest, exact
stop/start ordering, bounded selection persistence, target substitution,
symlink protection, application operations, UI gate, and no-polling: passed

Model-runtime portability, profile switching, inactive AMD/Gemma deployment,
selected-profile startup, and identity migration suites: passed

Gemma Core/System Status dashboard identity: passed
Music Studio A3 dashboard regression: passed
Dashboard service after bounded code-only restart: active

Live Core round trip:
  initial: daily / amd-quality / ready / idle
  reserve: amd-free / nvidia-fallback / ready / music lane held
  restored: daily / amd-quality / ready / 0 active work
```

The Phase 12C aggregate reached all functional checks and stopped only at its
repository-curation assertion because this review verifier was intentionally
untracked during candidate construction. No functional Phase 12C assertion
failed.

## Local LLM evaluation

Not run. This slice changes deterministic runtime orchestration and dashboard
presentation, not model behavior. Model output cannot authorize Core changes.
The preceding Gemma integration review contains the relevant behavioral eval.

## Memory and lifecycle

```text
Shared Soul memory read/written: none
Skill-private memory added: none
Private runtime coordination state: soul.core_selection.v1
Lifecycle states: complete, awaiting_input, failed, blocked_for_human_review
Automatic transition/failover/preemption: none
```

The Core selection record is bounded owner-private runtime state. It contains
only configured Core IDs and profile IDs, rejects symlinks and invalid schemas,
and is updated only after a successful exact-confirmed activation.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Destructive-action protection weakened: no
Skill-private memory store added: no
Model or provider added: no
Default Core changed: no
```

## Known weaknesses

- Phone-width presentation retains the responsive CSS contract but was not
  separately inspected on a physical phone during this gate.
- AMD-Free Core intentionally prevents Music Studio generation while NVIDIA
  chat is active. It does not unload and restore Qwen automatically.
- A dedicated Music Core, automatic workflow-aware transitions, and concurrent
  Qwen/ACE-Step placement are not implemented.
- Qwen's smaller fallback persona calibration and Gemma's possible promotion
  to default Daily profile remain separate behavioral gates.
- Core selection is a dashboard/runtime control; Soul chat does not yet have a
  reviewed capability skill for invoking it.

## Human review checklist

```text
[x] Confirm Daily Core and AMD-Free Core terminology
[x] Confirm the top-bar selector hierarchy and responsive presentation
[x] Confirm Music Studio is visibly held in AMD-Free Core
[x] Confirm no runtime changes occur before the preview dialog action
[x] Approve one live Daily -> AMD-Free -> Daily transition test
[x] Confirm Ministral remains the selected/default Daily profile
[x] Approve candidate for commit and merge
```

## Human review outcome

```text
Outcome: approved for commit and merge
Reviewer: repository owner
Date: 2026-07-18
Decision summary: Visual candidate and bounded live round trip approved.
Required changes: none
```
