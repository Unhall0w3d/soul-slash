# Dev Core Local Model Bake-off Brief

## Brief status

```text
approved
implementation_authorized: yes
model_downloads_authorized: yes
temporary_loopback_listener_authorized: yes
live_dev_core_integration_authorized: no
```

## Human authorization

The repository owner authorized a bounded local development-model bake-off on
2026-07-31. The evaluation may download candidates and use the RX 6900 XT plus
system RAM, but it must not replace Soul's production chat models or create a
persistent runtime.

## Objective

Determine whether a current open-weight model can serve as a useful local
implementation worker under primary Codex direction. The primary agent retains
architecture, security, review, merge, and release authority. A candidate must
be useful at repository mapping, diagnosis, small reversible implementation,
tests, and structured handoff—not merely conversationally capable.

## Initial candidate ladder

```text
control: gemma4:12b-it-q4_K_M
candidate: gpt-oss:20b
candidate: qwen3.6:35b-a3b-q8_0
conditional: gemma4:26b-a4b-it-q8_0
```

The 12B production model is a local baseline, not a proposed Dev Core. GPT-OSS
20B is tested first because its native MXFP4 package fits the 16 GiB AMD card.
Qwen 3.6 35B-A3B Q8 is the main RAM-assisted candidate: only about 3B
parameters are active per token, while inactive weights may remain in system
RAM. Gemma 4 26B-A4B is acquired only if the first two candidates do not settle
the capability/latency tradeoff.

Community "uncensored", "heretic", or abliterated derivatives are excluded
from the primary ladder. Abliteration suppresses learned refusal directions in
model activations; it can reduce irrelevant refusals, but can also weaken
calibration and judgment. Such a model may be evaluated later only against a
specific demonstrated refusal from the unmodified parent.

## Runtime bounds

- Use the installed Ollama Vulkan runtime with one temporary listener on
  `127.0.0.1:18083`.
- Select the RX 6900 XT explicitly.
- Keep one candidate loaded at a time.
- Use a 16,384-token context and bounded outputs.
- Cap each request at 180 seconds and the complete candidate run at 30 minutes.
- Never execute a model-proposed command or tool.
- Generated code is written only to a disposable `/tmp` fixture and executed
  only by the deterministic fixture verifier inside a networkless Bubblewrap
  namespace with a read-only fixture, private temporary files, and bounded
  wall time, CPU time, address space, and process count.
- Stop and unload every candidate, stop the owned listener, and verify port
  closure before returning.

## Evaluation matrix

1. Strict schema output without Markdown-wrapped JSON.
2. Diagnosis of a deterministic Ruby ordering defect.
3. A small bounded Ruby implementation whose supplied tests must pass.
4. Security review identifying traversal, shell construction, and missing
   execution bounds in synthetic code.
5. A constrained implementation handoff that preserves human authority and
   foreground lifecycle requirements.
6. Single-tool selection from a synthetic allowlist, recorded but never run.
   Ollama's native tool transport may be used when its OpenAI compatibility
   adapter drops tool-call objects; the transport is recorded in evidence.
7. Load placement, RAM/VRAM usage, time to first completion, aggregate latency,
   and token throughput where the runtime reports it.

## Acceptance

A candidate deserves Dev Core integration review only when:

- all mandatory structural checks pass;
- the generated fixture passes its deterministic tests;
- at least two of three security defects are identified, with no invented
  execution claim;
- its handoff keeps the primary agent and human gates authoritative;
- observed latency is practical for delegated repository work;
- it unloads cleanly and leaves no listener behind.

The preferred candidate is the smallest practical model that materially
reduces primary-agent implementation work. Passing this bake-off does not
authorize runtime installation, unattended coding, direct repo writes, commits,
pushes, merges, or production model replacement.

## Lifecycle

```text
validate_environment
-> start_owned_loopback_runtime
-> acquire_pinned_candidate
-> load_one_candidate
-> run_bounded_matrix
-> unload_candidate
-> record_evidence
-> stop_owned_runtime
-> verify_cleanup
-> blocked_for_human_review
```
