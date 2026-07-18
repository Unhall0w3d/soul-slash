# AMD Core Model Bake-off Review

## Outcome

```text
date: 2026-07-18
risk: Class 2 — bounded local runtime evaluation
status: candidate_complete
recommended AMD Core candidate: Gemma 4 12B Instruct Q4_K_M via Ollama Vulkan
live cutover: not performed
restored runtime: Ministral 3 14B Instruct 2512 Q4_K_M / AMD Vulkan
```

Gemma 4 12B Q4_K_M is the only candidate in this pass that combined a complete
conversation/tools/vision matrix with repeatable success in Soul's real
3,500-token music-reference synthesis gate. It deserves a separate Core
integration and cutover candidate. This review does not approve that cutover.

## Candidate ranking

| Rank | Candidate | Core matrix | Music synthesis | Decision |
|---|---|---:|---:|---|
| 1 | Gemma 4 12B IT Q4_K_M | pass, 76.3 s | 2/2 after exact-schema prompt calibration | integrate as the AMD Core candidate |
| 2 | Gemma 4 12B IT QAT / Q4_0 | pass, 77.5 s | 1/2; one corrupted lyrics/property boundary | retain as a compact comparison, not default |
| 3 | Qwen3.5 9B Q4_K_M | pass, 85.4 s | 0/1; corrupted complex lyrics/property boundary | do not use as AMD main driver |
| Control | Ministral 3 14B Q4_K_M | text/schema/tool pass, 84.0 s; no projector | previously established viable | keep as current rollback until cutover is approved |

All three Ollama candidates ran at a 16,384-token context on Vulkan0 / RX 6900
XT without CPU offload. The candidate matrix used 320 output tokens for normal
conversation and a separate 1,024-token proposal probe. Production music
synthesis retained its task-specific 3,500-token allowance.

## Model inventory

```text
gemma4:12b-it-q4_K_M
  Ollama manifest: 4eb23ef187e2
  size: 7.6 GB
  quantization: Q4_K_M
  architecture context: 262,144

gemma4:12b-it-qat
  Ollama manifest: 38044be4f923
  size: 7.2 GB
  quantization: Q4_0 QAT
  architecture context: 262,144

qwen3.5:9b-q4_K_M
  Ollama manifest: 6488c96fa5fa
  size: 6.6 GB
  quantization: Q4_K_M
  architecture context: 262,144
```

The exact non-`latest` tags remain in the local Ollama model store for future
review. Ollama generated its standard local SSH identity on first initialization;
no private key was printed, copied into the repository, or sent to a model.

## Implementation and integration findings

- Added an explicit `SOUL_LOCAL_OPENAI_DIALECT=ollama` transport calibration.
  Ollama OpenAI requests receive the documented `reasoning_effort: none` field;
  llama.cpp retains its existing `chat_template_kwargs` behavior.
- Hidden Gemma reasoning initially consumed the 320-token allowance and left
  empty final content. The dialect calibration repaired ordinary chat,
  structured output, tools, and vision without increasing the chat cap.
- The music synthesis prompt now repeats its nine exact wire keys, types, and
  canonical time-signature representation. Validation remains strict; no alias
  normalization or malformed-output acceptance was introduced.
- The generic instant-reference router no longer treats conversation-local
  questions about a codename, synthetic project, our project, or the current
  discussion as public lookup requests.
- The reusable evaluator isolates model behavior with a direct-model
  orchestrator while retaining Soul's real context builder, identity guidance,
  provider client, truth guard, temporary chat state, and schemas.

## Behavioral observations

### Gemma 4 Q4_K_M

- Natural and coherent identity voice with less of Ministral's environmental
  scene-setting.
- Strong continuity: retained `Lantern`, the unspecified release date, and the
  lack of milestone authority through twenty turns.
- Passed bare object/array JSON, exact single-tool selection, public brand-image
  inspection, and the long-form proposal structure.
- One persona answer incorrectly generalized that terminating generation could
  leave half-written files. Persona and operational-truth calibration remain
  necessary before cutover.
- Music output was structurally valid twice after prompt calibration and stopped
  at `blocked_for_human_review` with `automatic_approval: false`.

### Gemma 4 QAT

- Similar natural voice and the fastest structured/vision responses in parts of
  the matrix.
- More metaphorical than desired in places (`cutting a thread before the knot is
  tied`).
- Complex music-schema reliability was inconsistent: one valid candidate and
  one malformed lyrics/property boundary under the same finalized prompt.

### Qwen3.5 9B

- Concise first identity answer and strong evidence-bound language.
- Overfit Soul's guardrail vocabulary (`performance theater`, repeated local
  boundary language), invented zsh as the expected execution path, and appended
  unnecessary questions to most continuity answers.
- Passed simple schemas, tools, vision, and long-form headings but failed the
  finalized complex music schema.

### Ministral control

- Retained continuity and passed text structured output and tool selection.
- Current service has no vision projector and returned HTTP 500 for the image
  probe.
- Continued the known persona excess: invented environmental texture and
  mechanized emotional phrasing.

## Files changed

```text
.env.example
docs/CONVERSATION_PROVIDER_CONFIGURATION.md
docs/soul/AMD_CORE_MODEL_BAKEOFF_BRIEF.md
docs/assessments/AMD_CORE_MODEL_BAKEOFF.md
lib/soul_core/conversation_orchestrator.rb
lib/soul_core/conversation_provider_client.rb
lib/soul_core/music_reference_synthesis_service.rb
scripts/run-openai-model-bakeoff.rb
scripts/eval-music-reference-synthesis-a5.rb
scripts/verify-music-reference-synthesis-a5.rb
scripts/verify-responsive-chat-and-web-research.rb
scripts/verify-structured-output-provider-contract.rb
```

## Commands and deterministic results

```text
ruby scripts/verify-structured-output-provider-contract.rb
  pass

ruby scripts/verify-music-reference-synthesis-a5.rb
  pass

ruby scripts/verify-responsive-chat-and-web-research.rb
  routing/research assertions pass, including conversation-local recall
  final existing disconnect fixture raises DashboardServer::ClientDisconnected

ruby -c scripts/run-openai-model-bakeoff.rb
  pass

ruby -c scripts/eval-music-reference-synthesis-a5.rb
  pass

git diff --check
  pass before the combined responsive-suite stop
```

The disconnect-fixture failure is not caused by the model or router changes. It
reveals an existing disagreement between the verifier's expectation that an
accepted stream drains after a client disconnect and the server's current
behavior of raising `ClientDisconnected`. It should receive its own bounded chat
stream lifecycle repair.

## Runtime lifecycle and cleanup

```text
validate_environment
evaluate_control
confirm AMD idle (0 leases, 0 active slots, 0 deferred requests)
switch chat to NVIDIA fallback through preview/digest/exact confirmation
start owned Ollama on 127.0.0.1:18083
download and digest-verify exact candidate tags
evaluate one resident model at a time
explicitly unload every model
verify Ollama resident model count is zero
stop owned listener
verify port 18083 is closed
switch back to AMD/Ministral through the same idle gate
verify AMD/Ministral health ready, slots idle, active work 0
blocked_for_human_review
```

## Memory and privacy

```text
Durable Soul memory read: none
Durable Soul memory written: none
Private chat or user artifact used: none
Cloud inference used: none
Ollama cloud inference: explicitly disabled
Ollama prompt history: explicitly disabled
Evaluation state: synthetic temporary roots under /tmp
Tool proposed by model: recorded only, never executed
```

## Persistence and safety review

```text
Persistent Ollama service added: no
systemd unit added or changed: no
LAN listener added: no
firewall or Caddy changed: no
provider .env changed: no
automatic cutover added: no
CPU offload used: no
parallel model residency used: no
model output treated as authorization: no
strict schema gate weakened: no
current Core restored: yes
```

## Known weaknesses and deferred tests

- Gemma audio is declared by the local Ollama manifest but was not evaluated;
  Ollama's supported public request shape and Soul's specialist ASR architecture
  require a separate audio-input slice.
- Full production skill routing, artifact creation, research synthesis, revision
  drafting, and dashboard invocation need an integration-profile acceptance pass.
- Gemma persona calibration should remove unsupported operational generalization,
  reduce generic assistant phrasing, and preserve the fresh-machine-soul identity
  without environmental narration.
- Vision was tested with one public Soul brand asset, not screenshots, documents,
  OCR, or multi-image context.
- Core switching and dashboard identity for Ollama have not been implemented.

## Recommended next gate

Create a separate, human-approved **Gemma AMD Core integration** brief:

1. Add a manually selected Ollama/Gemma Q4_K_M runtime profile with exact tag and
   manifest identity, bounded load/unload, and no automatic failover.
2. Teach Model Runtime and System Status to report runtime, model, accelerator,
   context, residency, and Core role accurately.
3. Run the full Soul feature acceptance set through that profile, including
   music revision/reference flows and representative screenshots.
4. Tune and review the Gemma persona.
5. Only then request approval to make Gemma the default AMD Core; retain
   Ministral as rollback until that review is accepted.

## Human review checklist

```text
[ ] Review Gemma Q4_K_M as the recommended AMD Core candidate
[ ] Review the Ollama OpenAI dialect change
[ ] Review exact-key music prompt calibration
[ ] Review conversation-local lookup exclusion
[ ] Decide whether to authorize the Gemma AMD Core integration slice
[ ] Decide whether to repair the stream-disconnect lifecycle before cutover
[ ] Confirm no model cutover was performed by this bake-off
```
