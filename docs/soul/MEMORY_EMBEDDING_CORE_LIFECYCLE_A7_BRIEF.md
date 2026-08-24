# Memory Embedding Core Lifecycle A7 Brief

## Approved objective

Make the qualified local memory embedding endpoint available to ordinary Chat
without manual runtime setup. Reuse Soul's reviewed Core lifecycle and retain
approved-only lexical retrieval whenever semantic retrieval is unavailable.

## Exact runtime

- unit: `soul-memory-embedding.service`;
- bind: `127.0.0.1:11434` only;
- model: `qwen3-embedding:0.6b-q8_0` at the reviewed digest;
- accelerator: NVIDIA Vulkan device `1`;
- context ceiling: `1024` tokens;
- one loaded model, one parallel request, five-minute model keep-alive;
- Ollama cloud and history disabled.

The unit is installed inactive and unenabled. It has no `[Install]` section.
The selected-Core startup path and explicit Core transitions are its only
lifecycle owners. Non-Free Cores may start the endpoint; Free Core must stop it.
The embedding model remains demand-loaded and may evict after its keep-alive.

## Authority and failure behavior

Installing or removing the exact reviewed unit requires the corresponding
literal confirmation. Core activation retains its existing human confirmation.
The runtime cannot select a Core, approve memory, rebuild an index, or mutate
the canonical ledger. Endpoint, model, vector, or index failures fall back to
approved-only lexical retrieval. Free Core never retains the endpoint.

## Qualification evidence

On Soul-Lite Core, the 1024-token profile embedded a 1,023-token request while
Qwen chat responded successfully. The endpoint used 1,324 MiB of NVIDIA VRAM,
leaving 1,475 MiB free. Ten warm short requests averaged 56.7 ms. Teardown
closed the endpoint and returned NVIDIA usage to its exact pre-test baseline.

## Review boundary

Deterministic verification must prove the exact unit, fixed 1024 ceiling,
inactive and unenabled installation, closed Core allowlist, Free Core teardown,
bounded systemctl calls, and lexical fallback preservation. Live installation
and cross-Core observation remain separate Operator-reviewed deployment gates.
