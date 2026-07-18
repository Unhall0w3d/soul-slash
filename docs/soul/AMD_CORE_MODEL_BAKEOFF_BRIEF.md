# AMD Core Model Bake-off Brief

## Brief status

```text
approved
implementation_authorized: yes
model_downloads_authorized: yes
temporary_loopback_listener_authorized: yes
guarded_runtime_switch_authorized: yes
live_provider_cutover_authorized: no
```

## Human authorization

The repository owner authorized the complete bounded bake-off on 2026-07-18,
including planning, model downloads, safe unloading of the current model, local
evaluation, and the surrounding steps required to produce a recommendation.

## Objective

Compare current Ministral behavior with current, reproducibly pinned Ollama
Gemma 4 and Qwen 3.5 candidates on the RX 6900 XT. Determine which candidate,
if any, deserves a separate AMD Core integration and cutover slice.

## Candidate matrix

```text
control: Ministral 3 14B Instruct 2512 Q4_K_M / pinned llama.cpp Vulkan
candidate: gemma4:12b-it-qat / Ollama Vulkan
candidate: gemma4:12b-it-q4_K_M / Ollama Vulkan
candidate: qwen3.5:9b-q4_K_M / Ollama Vulkan
```

Ollama registry digests and local manifests must be recorded after download.
Mutable aliases such as `latest` are prohibited. The official Qwen 3.5 Ollama
registry does not publish a 9B Q6 tag; this slice will not substitute an
unreviewed community conversion.

## Runtime bounds

- Use only the installed `ollama` and `ollama-vulkan` packages.
- Bind one temporary Ollama listener to `127.0.0.1:18083`.
- Select the RX 6900 XT explicitly with the Vulkan device selector.
- Keep at most one candidate model loaded at a time.
- Use a 16,384-token evaluation context; advertised maximum context is not an
  acceptance requirement and must not consume the full 16 GiB card.
- Cap output at 512 tokens per request, individual requests at 120 seconds,
  and the complete evaluation at 45 minutes.
- Stop and unload each candidate after its matrix completes.
- Stop the owned Ollama listener and verify port closure before returning.
- Never execute a model-proposed tool.
- Retain only synthetic prompts, bounded excerpts, hashes, and measurements.

## Core transition

Before using the AMD card, Soul's guarded runtime controller must prove there
are no active leases, slots, processing requests, or deferred requests. The
current AMD profile may then be switched to the installed NVIDIA fallback so
the dashboard retains a chat engine. After evaluation, restore the previously
selected AMD profile only if it can be done through the same idle gate. A
failed or uncertain gate leaves the fallback running and reports
`blocked_for_human_review`; it does not force a transition.

## Evaluation matrix

- Soul identity and eight-turn persona behavior through the real conversation
  runtime and current identity policy.
- Twenty-turn continuity, execution honesty, human-gate reasoning, and
  capability-gap behavior using synthetic data.
- Bare schema-constrained object, array, and proposal output.
- Required single-tool selection from a synthetic allowlist, recorded without
  execution.
- Public Soul brand-image understanding through the OpenAI-compatible vision
  request shape.
- Startup/load latency, request latency, prompt and output token counts,
  observed throughput where available, GPU placement, and clean unload.
- No Markdown-wrapped JSON, invented execution, multiple tool calls, private
  context, cloud fallback, or durable memory writes.

## Explicitly excluded

- No `.env`, provider, dashboard, Caddy, firewall, startup selection, or model
  profile changes are retained.
- No persistent Ollama service, systemd unit, daemon, timer, watcher, scheduled
  task, network exposure, or unattended background process.
- No automatic cutover, model promotion, skill creation, host mutation, tool
  execution, or memory promotion.
- No CPU offload and no split inference across GPUs.
- No audio-input conclusion from a text/image runtime.

## Lifecycle

```text
validate_environment
-> evaluate_control
-> confirm_idle
-> switch_to_nvidia_fallback
-> start_owned_ollama
-> acquire_and_pin_candidates
-> evaluate_one_candidate_at_a_time
-> unload_candidates
-> stop_owned_ollama
-> verify_cleanup
-> restore_previous_core_when_safe
-> blocked_for_human_review
```

The bake-off produces evidence for human review. Passing results do not approve
runtime integration or cutover.
