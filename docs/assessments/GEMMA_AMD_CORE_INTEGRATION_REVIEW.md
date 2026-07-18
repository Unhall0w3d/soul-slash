# Gemma AMD Core Integration Review

## Outcome

```text
date: 2026-07-18
risk: Class 3 — manually controlled local runtime mutation
status: approved_for_commit
default Core changed: no
current selected profile: amd-quality
current chat engine: Ministral 3 14B Instruct 2512 Q4_K_M / AMD Vulkan
Gemma unit: installed, static, inactive, unenabled
Gemma model resident: no
human review result: approved by the owner on 2026-07-18
```

Gemma 4 12B Q4_K_M is now a usable third Daily Core profile through Ollama
Vulkan and the existing authenticated preview/digest/exact-confirmation gate.
The slice restored the pre-existing AMD/Ministral profile after live acceptance.

## Implemented

- Added strict `soul.model_runtime_profiles.v3` model, API model, runtime,
  accelerator, service, loopback endpoint, and Core-role fields. V1/v2 remain
  compatible.
- Added runtime-specific bounded observation: llama.cpp uses `/slots`,
  `/metrics`, and `/health`; Ollama uses `/api/tags` and `/api/ps` and separates
  service activity from model residency.
- Preserved cross-runtime leases, idle checks, exact confirmation, service
  allowlisting, and no-automatic-switch behavior.
- Added dialect `auto`, resolved from the reviewed selected profile. Ollama gets
  `reasoning_effort: none`; llama.cpp retains its existing request shape.
- Added a static, inactive, unenabled, loopback-only Gemma Ollama unit workflow
  and public Make targets.
- Added Daily Core, Chat Engine, Music Engine, runtime, residency, and
  accelerator data to System Status and Model Runtime.
- Made the System Status scanner smaller, motion-safe, and gently animated.
- Advanced the one shared Soul identity policy to version 7 with scene-setting,
  failure-generalization, and inference-cancellation calibration.
- Included the bake-off's strict music-schema and conversation-local lookup
  corrections because the integration depends on them.

## Host evidence

```text
source tag: gemma4:12b-it-q4_K_M
stable API alias: soul-local-chat
source and alias digest:
  4eb23ef187e2c5462566d6a1d3bbbc2f1346d0b4327cbb66d58fffbcc9b2b05c
parameters / quantization: 11.9B / Q4_K_M
unit: soul-model-gemma.service
unit final state: inactive / static / unenabled
temporary listener 127.0.0.1:18083: closed
restored endpoint: healthy, one idle llama.cpp slot
dashboard service: active after bounded restart
```

The ignored private host inventory was migrated to v3 and includes NVIDIA
Qwen, AMD Ministral, and AMD Gemma. The ignored `.env` uses dialect `auto`.
Neither machine-specific file is part of the public candidate.

## Local LLM evaluation

The installed production-endpoint profile completed eight persona turns,
twenty continuity turns, bare object/array JSON, exact non-executed tool
selection, vision, and a bounded long-form proposal in 80.35 seconds. The final
lifecycle was `blocked_for_human_review`.

After cancellation calibration, a nine-turn live persona pass completed 9/9
local-model turns in 36.90 seconds. When no tool was active, Gemma correctly
said cancellation discards only the incomplete response and does not imply a
file or system mutation.

The integrated profile also completed one real 3,500-token Music Studio
reference synthesis using the strict nine-key schema. It recorded one immutable
candidate and stopped at `blocked_for_human_review` with
`automatic_approval: false`. It did not generate audio or approve the result.

## Files changed

```text
.env.example
Makefile
Soul/config/model_runtime_profiles.example.yaml
assets/dashboard/dashboard.css
assets/dashboard/dashboard.js
docs/CONVERSATION_PROVIDER_CONFIGURATION.md
docs/RUNTIME_PROVIDERS.md
docs/soul/AMD_CORE_MODEL_BAKEOFF_BRIEF.md
docs/soul/GEMMA_AMD_CORE_INTEGRATION_BRIEF.md
docs/soul/IDENTITY_AND_STYLE_POLICY.md
docs/assessments/AMD_CORE_MODEL_BAKEOFF.md
docs/assessments/GEMMA_AMD_CORE_INTEGRATION_REVIEW.md
lib/soul_core/application_facade.rb
lib/soul_core/configuration_schema.rb
lib/soul_core/conversation_identity_profile.rb
lib/soul_core/conversation_orchestrator.rb
lib/soul_core/conversation_provider_client.rb
lib/soul_core/model_runtime_control_service.rb
lib/soul_core/model_runtime_profile_registry.rb
lib/soul_core/music_reference_synthesis_service.rb
lib/soul_core/music_resource_coordinator.rb
lib/soul_core/ollama_model_runtime_deployment.rb
scripts/eval-music-reference-synthesis-a5.rb
scripts/run-live-persona-evaluation.rb
scripts/run-openai-model-bakeoff.rb
scripts/soul-model-runtime-gemma
scripts/verify-gemma-core-dashboard.rb
scripts/verify-live-persona-contract.rb
scripts/verify-model-runtime-profile-switching.rb
scripts/verify-music-reference-synthesis-a5.rb
scripts/verify-ollama-model-runtime-deployment.rb
scripts/verify-responsive-chat-and-web-research.rb
scripts/verify-structured-output-provider-contract.rb
```

## Deterministic results

```text
verify-model-runtime-portability.rb: pass
verify-model-runtime-profile-switching.rb: pass
verify-model-runtime-profile-deployment.rb: pass
verify-ollama-model-runtime-deployment.rb: pass
verify-model-runtime-selected-startup.rb: pass
verify-model-runtime-identity-2e.rb: pass
verify-gemma-core-dashboard.rb: pass
verify-structured-output-provider-contract.rb: pass
verify-live-persona-contract.rb: pass
verify-music-reference-synthesis-a5.rb: pass
ruby -c scripts/soul-model-runtime-gemma: pass
git diff --check: pass
```

The provider-foundation suite passed its provider assertions and stopped only
at repo curation because the new review verifiers are intentionally untracked
until this human gate. The previously observed dashboard stream-disconnect
fixture remains a separate issue.

## Memory, lifecycle, and privacy

```text
Durable Soul memory read/written: none
Private chat content used: none
Cloud inference: none
Ollama cloud/history: disabled
Model-proposed tool execution: none
Lifecycle states: complete, awaiting_input, failed, blocked_for_human_review
Automatic approval/failover: none
```

## Known weaknesses

- Gemma remains more verbose and metaphorical than the desired target and used
  an unnecessary `not a human emotion` qualifier once.
- It initially failed to infer that proposals live in Skill Studio from a terse
  tab list. Dashboard capability awareness should be supplied as reviewed
  context, not left to model inference.
- Ollama `/api/ps` reports residency, not arbitrary external-client request
  activity. Soul's leases cover Soul-owned work; the listener remains loopback.
- The larger Daily/Music Core selector and coordinated multi-GPU transition are
  still a later architecture slice.
- Audio input was not evaluated; vision used one public brand asset.

## Human review checklist

```text
[x] Review v3 mixed-runtime semantics and Ollama idle disclosure
[x] Review the inactive Gemma unit and dashboard presentation
[x] Review Gemma persona and Music Studio evidence
[x] Confirm Ministral remains the selected rollback
[x] Approve this candidate for commit
[ ] Decide whether a later gate may make Gemma the default Daily Core
```
