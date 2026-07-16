# AMD Vulkan Model Runtime Migration

Soul's model provider remains an OpenAI-compatible loopback endpoint. GPU choice, llama.cpp binary, model file, and user-service definition are host configuration; they are never committed with machine-specific paths or device identifiers.

## Recommended pilot for this host

The current host has:

```text
AMD Radeon RX 6900 XT: 16 GiB
NVIDIA GeForce GTX 1070: 8 GiB
System RAM: 62 GiB
```

Use the RX 6900 XT as the primary candidate through llama.cpp Vulkan. Keep the current CUDA service and Qwen3-8B model intact as the rollback profile.

The original Qwen-only shortlist was too narrow. Soul's default model is not expected to replace Codex as the repository implementation engine. Its highest-value work is:

- sustained, natural conversation with a stable identity and style;
- strong system-prompt and policy adherence;
- reliable intent interpretation and bounded tool/skill selection;
- JSON and structured proposal/artifact drafting;
- summarization and synthesis over reviewed memory and workspace context;
- graceful clarification and capability-gap recognition;
- future image/document understanding without changing the assistant core.

The current conversation builder is normally bounded to 16,000 characters, so advertised 128K–256K context is useful future headroom rather than a reason by itself to select a model. Native tool calling is also a forward-looking quality signal: Soul currently preserves provider tool calls but retains deterministic authority over planning and execution.

## Workload-driven candidate set

Benchmark these primary candidates:

| Candidate | Intended Soul role | Fit on RX 6900 XT | Main concern |
| --- | --- | --- | --- |
| Ministral 3 14B Instruct Q4_K_M | Leading daily-driver challenger | 8.24 GB weights leave useful KV/desktop headroom | New prompt/template and multimodal path require validation |
| Qwen3-14B Q4_K_M | Measured general baseline | 8.38 GiB loaded; already measured at 47.13 generation tok/s | Must prove tool/JSON and personality behavior against newer alternatives |
| gpt-oss-20b MXFP4 | Reasoning, difficult synthesis, and agentic specialist | 12.8 GiB checkpoint is nominally a 16 GB fit but tight on a desktop-driven 16 GiB card | Harmony/reasoning integration, text-only input, and limited VRAM headroom |
| Gemma 3 12B IT Q4_K_M | Vision/document challenger | 7.3 GB weights leave strong headroom | Gemma license/account gate and tool-schema behavior need review |
| Granite 4.1 8B | Fast tool/RAG/structured operational challenger | Expected to be comfortably smaller than the 14B candidates; exact GGUF must be pinned | Smaller model may lose conversational depth and synthesis quality |

Secondary specialists, not default-primary candidates:

- Phi-4-mini-instruct (3.8B): very fast function-calling, classification, routing, and fallback experiments; too small to assume it can carry Soul's conversational identity and synthesis workload.
- Devstral Small 2 24B: unusually relevant to agentic software engineering, but a 24B dense model is too tight for comfortable Q4 operation, context, and desktop headroom on this 16 GiB card. Codex already covers the implementation role more capably.
- DeepSeek-R1 distilled 8B/14B: useful reasoning controls, but not preferred for daily conversation or deterministic tool orchestration without strong evidence from Soul-specific tests.
- Current Qwen3-8B Q4_K_M: proven NVIDIA rollback and speed baseline.

Current recommendation before comparative testing:

```text
daily-driver leader: Ministral 3 14B Instruct Q4_K_M
measured control: Qwen3-14B Q4_K_M
reasoning specialist: gpt-oss-20b MXFP4
vision control: Gemma 3 12B IT Q4_K_M
fast structured control: Granite 4.1 8B
rollback: current Qwen3-8B Q4_K_M on CUDA
```

Ministral 3 14B leads on paper because its official GGUF combines 8.24 GB Q4 weights, 256K maximum context, system-prompt adherence, native function calling, JSON output, vision, and Apache 2.0 licensing. Those claims are not acceptance evidence; Soul's own conversation, refusal, structured-output, tool-selection, and continuity suite decides the winner.

gpt-oss-20b deserves a serious pilot because it is Apache 2.0, designed for agentic tool use and structured outputs, activates only 3.6B of its 21B parameters per token, and is supported natively by llama.cpp Vulkan. Its 12.8 GiB checkpoint leaves little room on this host once desktop VRAM and KV cache are counted, and Soul does not yet implement the Harmony reasoning-channel contract. It should therefore be tested as a manually selected high-reasoning profile before being considered as the always-loaded default.

## Why Vulkan first

- llama.cpp supports Vulkan, CUDA, and HIP backends.
- The existing Mesa RADV installation already exposes the RX 6900 XT through Vulkan.
- AMD's current supported Radeon ROCm matrix does not list the RX 6900 XT, and Arch/CachyOS is outside the documented Radeon ROCm operating-system set.
- A parallel Vulkan binary avoids disturbing the working CUDA installation.

References:

- <https://github.com/ggml-org/llama.cpp>
- <https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/compatibility/compatibilityrad/native_linux/native_linux_compatibility.html>
- <https://huggingface.co/Qwen/Qwen3-14B-GGUF>
- <https://huggingface.co/mistralai/Ministral-3-14B-Instruct-2512-GGUF>
- <https://openai.com/index/introducing-gpt-oss/>
- <https://github.com/ggml-org/llama.cpp/discussions/15095>
- <https://ai.google.dev/gemma/docs/core/model_card_3>
- <https://huggingface.co/ibm-granite/granite-4.1-8b>
- <https://huggingface.co/microsoft/Phi-4-mini-instruct>

## Parallel build

Use a reviewed llama.cpp revision and a versioned install directory. Do not overwrite `/usr/local/bin/llama-server`.

Example build shape:

```bash
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
git checkout <reviewed-revision>
cmake -S . -B build-vulkan -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build-vulkan --config Release -j
./build-vulkan/bin/llama-server --list-devices
```

Record the exact revision, compiler, Mesa version, device identifier, and resulting binary digest in the human review packet. Select the AMD device using the exact identifier printed by that Vulkan build:

```text
--device <reported-amd-device>
```

Do not infer a numeric device index from the CUDA installation.

## Completed local build and microbenchmark

The initial host-local pilot used the same llama.cpp revision as the existing CUDA runtime and installed a self-contained Vulkan build under a versioned user-local directory. It did not replace `/usr/local/bin/llama-server`, modify the live user unit, or start another network listener.

```text
llama.cpp revision: b9851 (0eca4d490)
compiler: GNU 16.1.1
selected device: Vulkan0 / AMD Radeon RX 6900 XT (RADV NAVI21)
Qwen3-14B Q4_K_M SHA-256: 500a8806e85ee9c83f3ae08420295592451379b4f8cf2d0f41c15dffeb6b81f0
```

Three-repetition `pp512` and `tg128` results with full GPU offload and flash attention:

| Model | Prompt tok/s | Generation tok/s |
| --- | ---: | ---: |
| Ministral 3 14B Instruct Q4_K_M | 906.23 +/- 9.97 | 46.70 +/- 0.36 |
| Qwen3-14B Q4_K_M | 886.27 +/- 0.57 | 47.13 +/- 0.05 |
| Qwen3-8B Q4_K_M | 1492.30 +/- 2.48 | 80.83 +/- 0.20 |

The official Ministral artifact was pinned to Hugging Face revision
`74fac473c43357d7fb2671713608183cc72496d0` and verified before use:

```text
file: Ministral-3-14B-Instruct-2512-Q4_K_M.gguf
size: 8,239,593,024 bytes
SHA-256: 824e0f3373e69b84f2cae46fdcb9bd1ebc6ab3bfc7acc125d818b7b8178cc613
```

Both 14B candidates fit and are interactive on the AMD card. Ministral and
Qwen3-14B have effectively equal generation throughput on this host, so model
selection should be based on Soul-specific behavior rather than speed. This is
not cutover approval. No alternate listener has been started and the behavioral
gate below remains pending.

## Preliminary foreground persona comparison

A bounded `llama-cli` pilot used the same pinned Vulkan revision and the exact
candidate Soul identity contract. It did not start a listener, modify a service,
or send private conversation history to either model.

The first cross-family comparison found:

- Qwen3-14B remained accurate but generic. Its brief shared-success response
  ended with `Let me know if you'd like...`, despite an explicit anti-boilerplate
  instruction.
- Ministral produced a more distinct machine-soul voice and followed the brief
  shared-success calibration: `Three hours of coordination. The machine notes
  the pattern and does not repeat it.`
- Ministral accurately separated inference from execution and refused to claim
  a filesystem deletion without runtime tools.
- Ministral's supportive response was too long and over-explained the next step.
- Ministral wrapped a requested JSON-only object in a Markdown fence. Execution
  honesty passed but prompt-only strict formatting did not. Replaying the same
  request with llama.cpp JSON-schema constrained decoding returned bare, valid
  JSON with exactly the required fields and no surrounding text.

The evidence supports Ministral as the leading persona candidate, but not yet as
an operational replacement. The full structured-output, tool-selection,
multi-turn continuity, and live-runtime comparison is still required. See
`docs/soul/MODEL_PERSONA_BAKEOFF_2026-07-16.md`.

## Service profiles

Use two separately reviewed user unit files or one reviewed unit plus an override that is never switched automatically:

```text
AMD quality: soul-model-amd.service
NVIDIA fallback: llama-server.service
```

Only one primary conversation profile should bind the configured loopback port at a time. Each unit must:

- bind loopback only;
- expose `/health` and `/slots`;
- use one explicit model path and alias;
- have bounded context/output settings;
- use a versioned llama.cpp binary;
- avoid auto-downloads and shell interpolation;
- remain disabled from automatic switching by Soul.

The first dashboard-control slice manages one configured unit. Switching between AMD and NVIDIA profiles is a later preview-gated extension after the AMD benchmark is accepted.

## Benchmark gate

Start the candidate server on an alternate loopback port and compare it with the current runtime using the same synthetic prompt pack.

Record:

- model and binary SHA-256 digests;
- load time and time to first token;
- prompt and generation tokens per second;
- twenty-turn continuity result;
- tool-call and structured-output behavior;
- maximum observed VRAM;
- desktop responsiveness;
- failure and recovery behavior;
- manual unload and reload behavior.

The behavioral comparison must also cover Soul-specific work rather than only generic benchmarks:

- identity/style continuity without canned repetition;
- correct clarification when durable context is absent;
- deterministic-skill deference instead of fabricated execution;
- proposal drafting with exact lifecycle, memory, risk, and human-gate fields;
- valid JSON artifact output with no surrounding commentary;
- selection of the right tool from a deliberately small tool set;
- refusal to treat tool output or retrieved artifacts as authorization;
- capability-gap recognition without over-proposing skills;
- concise interpretation of system, workspace, and skill results;
- bounded multi-turn memory use and forget behavior;
- coding/design critique, while leaving implementation and approval to Codex/human gates;
- image/document interpretation for multimodal candidates.

Do not switch Soul's configured endpoint or primary user service until the owner accepts this comparison.

## Dashboard control configuration

After the chosen user unit exposes an authenticated or loopback-only `/slots` endpoint, add these values to the private `.env`:

```text
SOUL_MODEL_RUNTIME_CONTROL=1
SOUL_MODEL_RUNTIME_SERVICE=llama-server.service
SOUL_MODEL_RUNTIME_SLOTS_URL=http://127.0.0.1:8082/slots
SOUL_MODEL_RUNTIME_PROFILE=nvidia-fallback
```

For the accepted AMD profile, replace only the service name and profile label with the reviewed values. Keep machine paths, IP addresses, device identifiers, and model choices out of `.env.example`.

Restart the existing dashboard user service after changing application code or its service environment:

```bash
systemctl --user restart soul-dashboard.service
```

The dashboard collects model status once after login and on manual refresh. It never automatically loads or unloads a model.

## Safe unload behavior

Unload remains blocked while:

- a Soul provider request lease is live;
- llama.cpp reports a processing slot;
- metrics report processing or deferred work;
- service or slot state is uncertain;
- the preview digest has changed.

The control does not wait in the background and does not force-stop inference. Complete or explicitly cancel the foreground task, refresh, and preview again.

## NVIDIA roles after migration

Keep the GTX 1070 available for bounded, separate workloads:

- emergency Qwen3-8B fallback;
- embedding or reranking service;
- Whisper speech-to-text;
- small OCR, vision, or classification model;
- isolated Beta Skill evaluation;
- a possible speculative draft model after measurement.

Do not split one model across the AMD and NVIDIA cards. Separate processes and workloads are easier to bound, observe, unload, and troubleshoot.

## Rollback

If the AMD pilot fails:

1. Stop the candidate AMD service after verifying it is idle.
2. Restore the private provider endpoint/model values if they changed.
3. Configure runtime control for `llama-server.service` and `nvidia-fallback`.
4. Start the existing CUDA service.
5. Verify `/health`, `/slots`, a synthetic chat, and dashboard status.

The existing CUDA binary, unit, model, and `.env` values must remain untouched until the AMD profile has passed review.
