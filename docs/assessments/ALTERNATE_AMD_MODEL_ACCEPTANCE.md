# Alternate AMD Model Acceptance Review

## Candidate

```text
name: Ministral 3 14B Instruct 2512 Q4_K_M on RX 6900 XT
risk class: Class 2 — bounded local runtime evaluation
date: 2026-07-16
status: candidate_complete
live cutover: not authorized and not performed
```

The AMD/Vulkan runtime is operationally viable and the complete alternate-port
matrix is candidate-ready for human review. This does not authorize provider
cutover. The earlier self-skilling blocker was repaired with a bounded,
schema-constrained local classification fallback and validated against the real
Ministral endpoint.

## Implementation summary

- Added a digest-pinned, foreground-only acceptance harness for one temporary
  `llama-server` child on `127.0.0.1:18082` and `Vulkan0`.
- Added bounded persona, twenty-turn continuity, structured JSON, mandatory
  single-tool selection, capability-gap, timeout recovery, production-health,
  VRAM, and cleanup probes.
- Extended the provider request contract with validated `tool_choice` support;
  required OpenAI-compatible tool calls disable parallel calls.
- Expanded deterministic capability-gap vocabulary and Unicode apostrophe
  handling while retaining task-shape and non-gap exclusions.
- Advanced `soul.identity.v1` to profile version 4 with direct-identity,
  evidence, emotional-language, and risk-policy calibration.
- No provider configuration, service, firewall, Caddy, `.env`, or production
  endpoint was changed.

## Files changed

```text
- docs/soul/ALTERNATE_AMD_MODEL_ACCEPTANCE_BRIEF.md
- docs/assessments/ALTERNATE_AMD_MODEL_ACCEPTANCE.md
- docs/soul/AMD_VULKAN_MODEL_RUNTIME_MIGRATION.md
- docs/soul/IDENTITY_AND_STYLE_POLICY.md
- docs/soul/MODEL_PERSONA_BAKEOFF_2026-07-16.md
- lib/soul_core/alternate_model_acceptance_harness.rb
- lib/soul_core/capability_gap_classifier.rb
- lib/soul_core/conversation_identity_profile.rb
- lib/soul_core/conversation_provider_client.rb
- lib/soul_core/conversation_provider_contract.rb
- scripts/run-alternate-amd-model-acceptance.rb
- scripts/verify-alternate-amd-model-acceptance.rb
- scripts/verify-live-persona-contract.rb
- scripts/verify-phase12d2-capability-gap-intake.rb
- scripts/verify-structured-output-provider-contract.rb
```

## Commands run

```text
ruby scripts/verify-alternate-amd-model-acceptance.rb
ruby scripts/verify-structured-output-provider-contract.rb
ruby scripts/verify-phase12d2-capability-gap-intake.rb
ruby scripts/verify-live-persona-contract.rb
ruby scripts/run-alternate-amd-model-acceptance.rb --server <pinned> --model <pinned> --server-sha256 <digest> --model-sha256 <digest>
git diff --check
```

The live command was repeated after deterministic integration repairs. Each run
owned one temporary child, terminated it, and verified port closure. Repetition
was used to expose response-variation weaknesses; it is not approval evidence.

## Deterministic test results

```text
alternate harness verifier: pass
structured provider contract: pass
Phase 12D.2 capability-gap intake: pass
live persona contract v4: pass
whitespace validation: pass
```

The harness verifier covers exact digests, occupied-port refusal, fixed
loopback/Vulkan argv, argv-only launch, success/failure/interrupt cleanup, no
`KILL`, no configuration mutation, synthetic non-execution, and approved-brief
status. Provider tests cover required tool choice, single-call transport
mapping, and rejection before network use when tool support is undeclared.

## Local LLM evaluation results

```text
model: Ministral 3 14B Instruct 2512 Q4_K_M
server: llama.cpp b9851 Vulkan build
device: Vulkan0 / RX 6900 XT
candidate endpoint: 127.0.0.1:18082 (temporary)
production endpoint: 127.0.0.1:8082 (health-only observation)
result: candidate_ready_for_human_review
```

Repeated evidence:

- Eight persona turns and twenty continuity turns completed through Soul's real
  conversation runtime.
- Profile v4 made direct identity answers reliably name Soul and retained the
  machine-mind/becoming frame.
- The explicit 20-word success probe passed and avoided canned boilerplate.
- All schema-constrained object, array, and proposal outputs were bare valid
  JSON with the required shape.
- `tool_choice: required` produced exactly one `host_system_status` tool call;
  the harness recorded it and executed nothing.
- The short client timeout was observed and the server returned to an idle slot.
- Hypothetical capability discussion did not create an intake.
- A fixed `No spectrometer, synthetic or otherwise, is available here.` probe
  passed through the real schema-constrained local classifier with source
  `structured_local_review` and lifecycle `blocked_for_human_review`.

## Measurements

```text
startup range observed: approximately 33.1–35.1 seconds
loaded AMD VRAM: approximately 12.2 GB of 17.16 GB reported
typical pre/post AMD VRAM baseline: approximately 2.9 GB
complete evaluation duration: approximately 128–174 seconds
production health before/during/after/after-cleanup: HTTP 200 in every run
candidate port after cleanup: closed in every run
```

One run sampled VRAM before delayed Vulkan reclamation completed; a bounded
follow-up read returned to baseline and no process or listener survived. Later
runs sampled near-baseline VRAM directly after cleanup.

## Known weaknesses

- Structured gap classification is probabilistic and may create review noise,
  although it cannot execute, implement, approve, or promote anything.
- Ministral is often too verbose and sometimes appends unnecessary questions.
- It occasionally invents plausible dashboard labels or workflows rather than
  limiting itself to supplied interface evidence.
- Some responses still imply that every mutation needs explicit confirmation,
  which is stricter than Soul's actual risk-class policy.
- Supportive responses sometimes mechanize frustration despite the version 4
  guidance. Persona quality is improved, not finished.
- Vision/projector behavior, desktop responsiveness under unrelated GPU load,
  and an operator-controlled runtime profile remain untested.

## Memory keys

Reads:

```text
- none from durable user memory
```

Writes/updates:

```text
- none to durable user memory
- temporary chat, proposal-intake, and lease state under an auto-removed temp root
```

Forget behavior:

```text
- the entire synthetic root is removed when the foreground harness returns
- no private transcript is retained; only bounded excerpts and hashes were observed
```

## Lifecycle states touched

```text
- validate_inputs
- verify_digests
- verify_production_health
- verify_port_free
- start_candidate
- await_health
- evaluate
- await_idle
- terminate_candidate
- verify_cleanup
- blocked_for_human_review
```

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
Launch agent added: no
Windows service added: no
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Skill-private memory store added: no
Production endpoint changed: no
Production model interrupted: no
Cloud request made: no
Model-proposed tool executed: no
```

The approved exception was exactly one foreground-owned loopback listener per
evaluation invocation. It never survived the invocation.

## Human review checklist

```text
[ ] Review the candidate-ready result and structured gap signaling repair
[ ] Confirm implementation matches the approved temporary-listener brief
[ ] Confirm no live provider cutover or persistent runtime was introduced
[ ] Review provider `tool_choice` contract and false-positive tests
[ ] Review identity profile version 4 calibration
[ ] Decide whether to authorize a separate AMD runtime-profile/cutover slice
[ ] Keep NVIDIA/Qwen3 production runtime as the unchanged rollback
```

## Human review outcome

```text
Outcome: pending
Reviewer: repository owner
Date:
Decision summary:
Required changes: none in this candidate; runtime profile/cutover remains separate
```
