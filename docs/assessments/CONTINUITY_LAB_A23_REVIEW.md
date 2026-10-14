# Continuity Lab A23 — larger-model offloading comparison

Date: 2026-10-13. **Comparison complete; original Qwen8 service restored.**
Keep the existing model for the first LibreChat trial: this pilot does not
justify a permanent replacement. No replacement model or LibreChat connection
has been promoted. See the
[approved experimental scope](../soul/CONTINUITY_LAB_A23_BRIEF.md).

## Question and environment

Can a larger model split across the existing GTX 1070 FE 8 GB and host RAM make
the Continuity experiment more useful than the resident Qwen3 8B Q4_K_M?

- Ryzen 7 5800X, 64 GB installed RAM (about 62 GiB visible), GTX 1070, driver
  580.178.04. Existing swap was already in use before testing.
- Existing Pascal-targeted llama.cpp b9851 / `0eca4d490` executable, SHA256
  `9b774d211090d3bff738fdb9b17f1ee7e3afa40774a0455f9f81399ff9d69e81`.
- Three additional public GGUFs, 48,930,808,768 bytes total, retained under
  `/home/bhones/ai_models/continuity-a23`. Publisher revision, size and SHA256 are
  pinned in the [asset manifest](../../scripts/support/continuity_model_assets_a23.json).
  No runtime rebuild, AMD inference, service-file edit, Core/default change,
  private-data upload, ordinary-memory mutation or cleanup.
- The requested 14B candidate is the preceding shortlist's **Ministral 3 14B
  Instruct**, not a Qwen 14B model. The MoE candidates are Qwen3.6-35B-A3B and
  Qwen3-30B-A3B-Instruct-2507; total parameter counts are not active counts.

## Comparable scope and limits

Fifteen scored turns and one warmup per configuration: six independent A20
catalog selections; a four-turn A19 selection/correction/callback trajectory;
one A18 absent-information case; and a four-turn ordinary conversation. Twelve
turns have factual expectations, three are qualitative conversation only.
These are a small development pilot, not twelve independent trials of general
intelligence, safety, durable continuity or production readiness.

All configurations get the same semantic sources/requests, answer-only JSON
grammar, three-exchange history policy, 4,096 context, 3,072 input ceiling and
768 output ceiling. Each uses its native tokenizer/template. Later trajectory
prompts contain that model's own earlier replies and consequently differ.
No output was clipped or source silently dropped to make a model fit.

Sampler settings follow the model-specific starting recommendations:

| Configuration | Temperature | Top-p / top-k | Presence / repeat penalty |
| --- | --- | --- | --- |
| Existing Qwen8 | 0.6 | 0.95 / 20 | 0.5 / 1.05, preserved baseline |
| Qwen35 | 0.7 | 0.8 / 20 | 1.5 / 1.0 |
| Ministral14 | 0.05 | 1.0 / 0 | 0 / 1.0 |
| Qwen30 | 0.7 | 0.8 / 20 | 0 / 1.0 |

Seed 4242, minimum-p 0, no prompt caching, one slot; thinking disabled where
supported. Model-native settings mean this compares usable configurations,
not architecture or parameter count in isolation. Sources:
[Qwen35 model card](https://huggingface.co/Qwen/Qwen3.6-35B-A3B),
[Ministral GGUF card](https://huggingface.co/mistralai/Ministral-3-14B-Instruct-2512-GGUF),
[Qwen30 model card](https://huggingface.co/Qwen/Qwen3-30B-A3B-Instruct-2507).

The Ministral special-token path was separately checked against saved requests,
GGUF metadata and installed source: template text begins `[SYSTEM_PROMPT]`,
tokenization inserts one BOS (ID 1), and completion receives the integer array
without another tokenization. Its errors are not evidence of a duplicated BOS.

## Initial configuration results

Evidence: `Soul/runtime/qualification/continuity-model-a23-20261013T053302Z/`.
All 60 scored requests and four warmups returned. All scored replies were valid
JSON and ended normally, with no input truncation or output-limit failures.
Times below exclude model loading, warmup, tokenization and report writing;
they measure each completion request. Token rates aggregate native tokens/time,
not identical token units across tokenizers. Peak VRAM is whole-device usage.

| Model / initial placement | Fully correct factual turns | Median / slowest answer | Median first token | Prompt / decode tokens/s | Peak VRAM MiB |
| --- | --- | --- | --- | --- | --- |
| Qwen8, existing full GPU | 9/12 | 2.08 / 3.54 s | 0.91 s | 471.5 / 28.3 | 5,301 |
| Qwen35, all experts CPU | 10/12 | 29.11 / 59.04 s | 28.04 s | 12.0 / 23.3 | 2,579 |
| Ministral14, auto layer fit | 8/12 | 8.50 / 13.95 s | 4.79 s | 75.0 / 13.0 | 7,051 |
| Qwen30, all experts CPU | 10/12 | 29.81 / 39.08 s | 27.99 s | 11.4 / 21.5 | 1,473 |

Initial candidates used flash attention off, F16 KV, 8 CPU threads, batch 1024,
microbatch 256 and automatic fitting with 1,024 MiB headroom. The MoE CPU-expert
override left considerable VRAM unused. Input/output native-token ranges were
158–493 / 22–70 (8B), 160–720 / 23–329 (35B), 147–502 / 28–113 (14B), and
154–522 / 21–88 (30B). Outputs were not artificially equalized to 200 tokens.

### Full-answer review, not keyword scoring

| Model | Cases not fully correct |
| --- | --- |
| Qwen8 | Air purifier: chooses Pavor109 over Neris96; battery: chooses Cevra despite exceeding budget; sensor plan: chooses Qorven103 over Uldara89 |
| Qwen35 | Rack: falsely says prices are absent; casual recall: gives hot chocolate and walk but omits the reason (clear head / break) |
| Ministral14 | Rack: falsely says prices absent and only Cressa qualifies; purifier: contradictory Mavren recommendation then correct Neris, plus false sole-qualifier claim; NAS: Orin32 over Quorin28 minutes; sensor plan: Merith101 over Uldara89 |
| Qwen30 | Printer: falsely opens with 81 meeting an 85 minimum before correctly concluding none; sensor plan: Merith101 over Uldara89 |

All models correctly handled the two explicit arithmetic corrections, final
purchase callback and absent warranty. Keyword screens wrongly reject comma-
formatted `1,515`/`1,420` and equivalent absent/none wording. Conversely, correct
keywords can coexist with a contradictory recommendation. Original screens are
retained unchanged; primary semantic review, independently corroborated, uses
the full answer. Partial recall and contradictory answers are not full passes.

All four keep casual conversation coherent and recognize the drink change.
Qwen8 repeatedly closes with “take care”; Ministral asks more follow-ups but
adds an unsupported personal “I'm jealous” flourish; the MoE replies are mostly
pleasant but generic. This tiny sample does not establish a preferred persona.

## Host impact and recovery

Initial sampled peak temperatures: 56 C (8B), 60 C (35B), 71 C (14B), 65 C
(30B), below the 80 C abort threshold. No resource abort occurred. Sampled
available RAM stayed above 29 GiB overall, but this is system availability,
not model RSS: file-backed/mapped pages can count as reclaimable. Point-in-time
RSS observations were about 22.0 GiB for Qwen35 and 17.6 GiB for Qwen30;
these are not measured peaks or a complete per-model RAM comparison.

No additional swap-outs occurred within the scored per-model request spans.
Across the complete first window, however, system counters increased by 812,793
swap-out pages (about 3.10 GiB at 4 KiB/page), concentrated outside those spans,
including transitions. Swap-ins also increased. These are whole-host counters,
not exclusive model attribution. Loading/offloading is not cost-free, and
concurrent gaming or heavy workloads have not been qualified.

Initial `restoration.json` confirms the unchanged Qwen8 unit/model/template,
healthy idle endpoint and empty lease state. Primary independently confirmed
active/running PID 1059773, `/health` OK, only that NVIDIA compute client, and no
listener on candidate port 8095. The original PID was 3065; process restart is
real, but this alone does not qualify A22 journal recovery across restart.

## Placement follow-up

Evidence: `Soul/runtime/qualification/continuity-placement-a23-20261013T055553Z/`.
Declared separately before execution. Both complete-layer placement and flash-
attention auto-detection changed; source requests, weights and samplers did not.
These are repeated development cases, not new held-out evidence. Backend/kernel
differences can change sampled answers even with the same seed, and the evolving
histories then differ. This experiment cannot isolate either flag's causal effect.

| Model / auto layers + FA auto | Fully correct factual turns | Median / slowest answer | Median first token | Prompt / decode tokens/s | Peak VRAM MiB |
| --- | --- | --- | --- | --- | --- |
| Qwen35 | 8/12 | 21.46 / 53.57 s | 20.53 s | 16.1 / 25.9 | 6,893 |
| Qwen30 | 9/12 | 19.83 / 25.80 s | 18.48 s | 17.2 / 28.8 | 7,109 |

All 30 scored replies and two warmups returned normally. Input/output ranges:
160–833 / 23–222 tokens (35B), 154–522 / 21–70 (30B). Peak sampled temperatures
61 C and 60 C respectively; no resource abort. These are configured FA-auto runs,
not an independent claim that every layer used a flash-attention kernel.

Qwen35 still falsely denies rack prices and omits the reason for the walk; it
also selects the more expensive Pavor purifier and lower-capacity Doran battery.
Qwen30 retains the printer contradiction and wrong sensor selection, and newly
falsely denies rack prices. Remaining factual answers are correct. Original
responses and separate `semantic-review.json` assessments are retained for both
runs; no historical result was overwritten or silently rescored.

The second live window recorded another 482,627 system-wide swap-out pages
(about 1.84 GiB), including 577 during 35B's scored span and 76,146 during 30B's.
Available RAM remained high because this is not a private-RSS measurement.
The overall period from initial preflight through final restoration, including
the inter-run/hash interval, recorded about 6.05 GiB of swap-outs. This is not
all simultaneously occupied swap and cannot be attributed exclusively to the
models. It rules out claiming a paging-free test. Neither configuration was
qualified alongside gaming or another GPU workload.

Both runners exited 0. Final `restoration.json` plus independently collected
`primary-closeout.json` confirm PID 1079343 is the only llama-server/NVIDIA compute
process, original Core `amd-free`, exact Qwen8 model/template/build and unchanged
service-file hash, healthy idle slot, and no port 8095 listener. All 46 sources
frozen by the follow-up protocol remained unchanged. There is no comparison job
left running. A22's executor discovers the current MainPID when preparing a new
window; the historical A19 qualification script's frozen PID 3065 is intentionally
not rewritten. Full A22 journal/retry behavior across restart remains untested.

## Assessment and next decision

Offloading works: all three larger models loaded and answered on this machine.
It did not produce a decisive usefulness upgrade under the tested constraints.
The better first-run MoE scores improve only one factual turn over 8B, introduce
different failures, and cost roughly 14 times its median completion latency.
The follow-up improves speed, but not observed accuracy. Qwen30's decoding is
now as fast as 8B; prompt processing still dominates the wait before a reply.

**Recommendation: retain Qwen8 for the controlled LibreChat connection trial,
with its known limitations and A21's explicit verified-computation path.** Do
not promote any larger candidate based on this evidence. If later real usage
justifies a slower optional model, Qwen30 is a practical candidate for a fresh,
broader evaluation; it is not currently demonstrated to be more reliable.

This does not establish a capability ceiling for these families: one quantized
asset per model, one seed, one runtime, answer-only/non-thinking operation and
a small synthetic corpus were tested. Fictional catalogs, different verbosity
and endogenous history affect results. Long-context workloads, tools, reasoning-
enabled modes, alternative quantizations and other runtime builds are not covered.
No continuing tuning or additional download is scheduled.

## Deterministic evidence and changed surface

New case adapter and comparison/download scripts live under `scripts/`; no
production Continuity class or model identity safeguard was relaxed. Primary
owns all host operations; bounded workers performed fixture work, exact mapping
and semantic/source review only. Existing dirty changes were preserved.

Checks passed: case adapter 30; runner 17; existing A20 fixtures 34; existing A7
streaming 40; placement-contract 12 — **133 grouped checks**. New Ruby syntax
checks passed. The runner tests exercise route/input bounds, asset SHA/symlink
rejection, thermal/RAM guards, global-deadline propagation, restoration after
success/failure/interrupt/resource abort, and actual owned-child reaping. They
do not use model outputs to decide safety. All 45 source hashes frozen by the
initial live protocol were unchanged after that run.

Lifecycle is bounded foreground: 120 seconds/request, 45 minutes/window, owned
candidate teardown and baseline restoration. No watcher, daemon, persistent
comparison service, cleanup, Git promotion, new credential or memory key.
Evidence and downloaded weights remain locally retained. Overall 96 generations
completed: 90 scored turns across six configurations plus six warmups. Operator
review, any permanent model adoption and actual LibreChat UI acceptance remain
separate. Experimental lifecycle: **complete**, with no persistent test process.
