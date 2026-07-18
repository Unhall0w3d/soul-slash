# Core Shared-Profile Transition Repair Review

## Candidate

```text
Name: Direct AMD-Free ↔ Music Core transition
Risk class: Class 2 — exact-gated owner-private intent mutation
Date: 2026-07-18
Status: approved
```

## Implementation summary

The Core orchestrator now treats AMD-Free and Music as separate operating
intents over one shared Qwen profile. When Qwen is already active and certainly
idle, preview produces a dedicated digest and confirmation. Execution changes
only the private Core-selection record; the model service remains running.

## Files changed

```text
- lib/soul_core/core_orchestration_service.rb
- lib/soul_core/model_runtime_control_service.rb
- scripts/verify-core-orchestration.rb
- scripts/verify-music-core-vulkan-feasibility.rb
- docs/soul/CORE_ORCHESTRATION_A0_A1_BRIEF.md
- docs/soul/CORE_SHARED_PROFILE_TRANSITION_REPAIR_BRIEF.md
- docs/assessments/CORE_SHARED_PROFILE_TRANSITION_REPAIR_REVIEW.md
```

## Deterministic tests

```text
ruby scripts/verify-core-orchestration.rb                 PASS (21 checks)
ruby scripts/verify-music-core-vulkan-feasibility.rb      PASS
ruby scripts/verify-model-runtime-profile-switching.rb    PASS
```

`verify-core-orchestration.rb` passes all 21 checks, including direct forward
and reverse transitions, stale digest rejection, no added service commands,
and unchanged Daily stop/start behavior.

## Memory and lifecycle

```text
Memory keys: none
Writes: owner-private Core selection only after exact confirmation
Forget behavior: not applicable
Lifecycle: complete, awaiting_input, blocked_for_human_review
```

## Safety check

```text
Service/model mutation in shared-profile transition: no
Automatic Core transition: no
Persistent service/daemon/watcher/schedule/background loop: no
Confirmation or lease gate weakened: no
```

## Human review checklist

```text
[x] Direct AMD-Free → Music preview is available
[x] Exact confirmation and stale-digest gates work
[x] Direct transition performs no service commands
[x] Music → AMD-Free uses the same bounded path
[x] Daily transitions retain existing stop/start behavior
[x] Live transition remains Operator-triggered
```

## Human review outcome

```text
Outcome: approved
Reviewer: repository owner
Date: 2026-07-18
Decision summary: Live AMD-Free to Music transition succeeded without the Daily bridge.
```
