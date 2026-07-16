# Model Runtime Portability Review

## Candidate status

```text
candidate_complete
```

Human acceptance remains pending.

## Implementation summary

- Added an opt-in controller for one allowlisted existing `systemd --user` model service.
- Added read-only status and preview/digest/exact-confirmation load and unload operations.
- Added bounded cross-process leases around local provider calls.
- Added llama.cpp slot and optional metrics checks that prevent unload during active or uncertain work.
- Added authenticated dashboard status and manual controls without polling, auto-load, or auto-unload.
- Documented a parallel AMD Vulkan pilot, Qwen3-14B baseline, NVIDIA fallback, benchmark gate, and rollback.
- Built an isolated, version-pinned Vulkan runtime outside the repository and benchmarked both the proposed 14B model and current 8B model on the RX 6900 XT.
- Replaced the Qwen-only model assumption with a Soul-workload-driven candidate matrix covering Mistral, OpenAI, Google, IBM, Microsoft, DeepSeek, and Qwen families.
- Preserved all existing services, binaries, models, provider values, safety gates, and conversation state.

## Files changed

```text
- .env.example
- Makefile
- assets/dashboard/dashboard.css
- assets/dashboard/dashboard.js
- assets/dashboard/index.html
- docs/CURRENT_STATE.md
- docs/GETTING_STARTED.md
- docs/MILESTONES.md
- docs/ROADMAP.md
- docs/assessments/MODEL_RUNTIME_PORTABILITY_REVIEW.md
- docs/soul/AMD_VULKAN_MODEL_RUNTIME_MIGRATION.md
- docs/soul/MODEL_RUNTIME_PORTABILITY_BRIEF.md
- lib/soul_core/application_contract.rb
- lib/soul_core/application_facade.rb
- lib/soul_core/configuration_schema.rb
- lib/soul_core/conversation_provider_client.rb
- lib/soul_core/conversation_runtime.rb
- lib/soul_core/model_runtime_control_service.rb
- lib/soul_core/model_runtime_lease_store.rb
- lib/soul_core/phase12a_portable_typed_configuration_assessor.rb
- lib/soul_core/phase12a_portable_typed_configuration_assessor.rb
- scripts/verify-model-runtime-portability.rb
```

## Commands run

```text
- ruby scripts/verify-model-runtime-portability.rb
- ruby scripts/verify-phase12a-portable-typed-configuration.rb
- ruby scripts/verify-multiturn-conversation-runtime-phase3.rb
- ruby scripts/verify-phase12c-foreground-dashboard.rb
- ruby scripts/verify-phase13c-conversational-soul-closeout.rb
- ruby -c <changed Ruby files>
- node --check assets/dashboard/dashboard.js
- git diff --check
- llama-server --list-devices
- llama-bench -m <Qwen3-14B-Q4_K_M.gguf> -p 512 -n 128 -r 3 -ngl 999 -dev Vulkan0 -fa on -t 8 -o md
- llama-bench -m <Qwen3-8B-Q4_K_M.gguf> -p 512 -n 128 -r 3 -ngl 999 -dev Vulkan0 -fa on -t 8 -o md
- sha256sum <versioned binaries and candidate model>
- ldd <versioned llama-server>
```

## Deterministic test results

```text
Model Runtime Portability verifier:
- idle active status: pass
- exact preview digest: pass
- stale preview rejection: pass
- allowlisted stop/start argv: pass
- live provider lease blocker: pass
- active slot blocker: pass
- metrics processing blocker: pass
- unreachable slot blocker: pass
- expired lease cleanup: pass
- disabled-by-default behavior: pass
- arbitrary unit rejection: pass
- provider success lease cleanup: pass
- provider failure lease cleanup: pass
- application operation allowlist: pass
- dashboard controls and no-timer boundary: pass

Phase 12A typed configuration regression: pass after replacing its historical fixed setting-count assertion with the canonical schema length.

Phase 12C dashboard regression: pass, including Phase 12B and earlier nested regressions.

Phase 13C aggregate closeout regression: pass across all 33 Phase 1–13, authentication, dashboard, Skill Studio, Self Improvement, Review Center, conversation lifecycle, protected deployment, integrated acceptance, local-model acceptance, and repository-curation checks.
```

## AMD pilot evidence

```text
llama.cpp revision: b9851 (0eca4d490)
compiler: GNU 16.1.1
install shape: versioned, self-contained user-local directory
backend/device: Vulkan0 / AMD Radeon RX 6900 XT (RADV NAVI21)
candidate model: Qwen3-14B Q4_K_M, 14.77B parameters, 8.38 GiB loaded weights
candidate model SHA-256: 500a8806e85ee9c83f3ae08420295592451379b4f8cf2d0f41c15dffeb6b81f0
llama-server SHA-256: c7a15d4eaef92e63869db6725f4976943a194ca5741933ed45b9c7ebecf78e68
llama-bench SHA-256: 574aac5b4b8894e0b50f5e2486bb77668634d26a0960fef63ca7d54fefe395d5
dynamic-library check: pass; versioned llama/ggml libraries resolve beside the binary

Identical three-repetition pp512/tg128 benchmark:
- Qwen3-14B Q4_K_M: 886.27 +/- 0.57 prompt tok/s; 47.13 +/- 0.05 generation tok/s
- Qwen3-8B Q4_K_M: 1492.30 +/- 2.48 prompt tok/s; 80.83 +/- 0.20 generation tok/s

Live NVIDIA service interrupted: no
Soul provider configuration changed: no
Candidate network listener started: no
```

The 14B candidate gives up about 42% of the 8B candidate's generation throughput on the same AMD card while retaining an interactive 47 tok/s. Quality, long-context behavior, model load time, VRAM headroom, and Soul's 20-turn behavioral suite still require the separately gated alternate-port server pilot.

## Local LLM eval results

```text
Not run for this slice.

Reason: this work changes deterministic runtime coordination and administration controls. Model output cannot validate service authorization, command allowlisting, active-work safety, or confirmation gates.
```

## Memory keys

Reads:

```text
- none
```

Writes/updates:

```text
- none
```

Forget behavior:

```text
- no memory behavior changed
```

The lease registry is ephemeral shared runtime coordination, not durable user memory. It stores no prompt or response content.

## Task lifecycle states touched

```text
- complete
- failed
- awaiting_input
- canceled (application contract remains available)
- blocked_for_human_review
```

## Risk classification

```text
Status and preview: Class 0 read-only local observation
Provider leases: Class 2 ephemeral local coordination state
Load/unload execute: Class 3 explicit local service mutation
```

## Safety and persistence check

```text
Persistent service added: no
Existing approved user service controlled: yes, explicitly approved in brief
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
launch agent added: no
Windows service added: no
Long-running background loop added: no
Background polling added: no
Automatic load/unload added: no
Forced active-request termination added: no
Confirmation gate weakened: no
Skill-private memory store added: no
Cloud provider use: no
Model download for controller implementation: no
Adjacent AMD pilot model download: yes, official Qwen repository artifact with matching SHA-256/ETag
GPU driver or runtime installation: no
```

## Known weaknesses

- The first controller manages one service profile; AMD/NVIDIA profile switching remains a later reviewed extension.
- The dashboard exposes active-work counts rather than cancellation controls. The foreground task must finish or be canceled through its originating workflow.
- A non-Soul local client is detected through llama.cpp slots/metrics rather than Soul lease metadata, so the dashboard cannot name that client.
- The llama.cpp `/slots` endpoint is operational API surface and may change between revisions; the selected Vulkan build must be pinned and reverified.
- Load execution verifies the immediate observed service/health state once. A large model may still report loading until a later manual refresh.
- The AMD runtime has not yet been exercised as an OpenAI-compatible server against Soul's behavioral suite; no alternate-port listener was started in this slice.
- Load time, time to first token, long-context VRAM headroom, structured-output behavior, and desktop responsiveness remain to be measured before cutover.
- The live service and provider still use the NVIDIA/Qwen3-8B fallback profile.
- Ministral 3, gpt-oss, Gemma 3, and Granite are researched candidates only; no additional weights were downloaded and no unmeasured vendor claim is treated as acceptance evidence.

## Human review checklist

```text
[ ] Matches approved brief
[ ] No unapproved scope expansion
[ ] Existing service-control authorization is acceptable
[ ] Unit and loopback endpoint allowlists are sufficiently narrow
[ ] Active-work blockers are meaningful
[ ] No automatic or background runtime behavior exists
[ ] Risk classes are correct
[ ] Memory behavior is appropriate
[ ] Confirmation gates are intact
[ ] Deterministic tests are meaningful
[ ] Failure behavior is predictable
[ ] Dashboard presentation is acceptable
[ ] AMD build and microbenchmark evidence is acceptable
[ ] Workload-driven multi-family candidate set is acceptable
[ ] Alternate-port behavioral pilot is approved
```

## Human review outcome

```text
Outcome: pending
Reviewer:
Date:
Decision summary:
Required changes:
```
