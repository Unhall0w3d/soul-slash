# Dev Core Local Model Bake-off Assessment

## Outcome

```text
candidate_complete: yes
recommended_model: gpt-oss:20b
recommended_role: bounded local implementation worker
production_integration: not authorized and not implemented
lifecycle_state: blocked_for_human_review
```

GPT-OSS 20B is the preferred Dev Core candidate on Maven. It passed the
complete bounded matrix, resides entirely on the RX 6900 XT at 16,384 context,
and delivered the best combination of correctness, security-review depth, and
latency. Gemma 4 26B-A4B Q8 also passed and is the preferred larger local
review/escalation candidate, but it is slower and consumes host memory.

The existing Gemma 4 12B Q4 model remains a strong fast lane for simple bounded
work. This assessment does not justify duplicating it into another always-on
Core. Qwen 3.6 35B-A3B Q8 physically fits through RAM-assisted placement, but
did not meet the practical worker threshold.

## Hardware and runtime

```text
host: Maven
cpu: AMD Ryzen 7 5800X (8C/16T)
system_memory: 62.7 GiB visible
amd_gpu: Radeon RX 6900 XT, 16 GiB VRAM
runtime: Ollama 0.32.5, Vulkan
listener: temporary 127.0.0.1:18083 only
context: 16,384 tokens
```

No production Core, service unit, dashboard configuration, provider, or model
alias was changed. The temporary listener was stopped and port 18083 was
verified closed.

## Results

| Rank | Candidate | Matrix | Aggregate output | Placement | Decision |
|---|---|---:|---:|---|---|
| 1 | `gpt-oss:20b` MXFP4 | 5/5 | 28.964 tok/s | 12.75 GB model, entirely VRAM | Integrate as bounded Dev worker candidate |
| 2 | `gemma4:26b-a4b-it-q8_0` | 5/5 | 10.518 tok/s | 29.17 GB total; 12.54 GB VRAM | Retain as optional deeper reviewer |
| 3 | `gemma4:12b-it-q4_K_M` | 5/5 | 27.906 tok/s | 8.39 GB, entirely VRAM | Keep current fast baseline |
| 4 | `qwen3.6:35b-a3b-q8_0` fast | 3/5 | 9.127 tok/s best clean run | 38.88 GB total; 13.41 GB VRAM | Do not integrate as default worker |
| 5 | `qwen3.6:35b-a3b-q8_0` reasoning | incomplete | 1.092 tok/s measured | same placement | Reject on practical latency |

Aggregate output divides API-reported completion tokens by measured request
wall time, including load/prompt/reasoning overhead. It is a workflow measure,
not raw decoder throughput.

### Pinned local manifests

```text
gpt-oss:20b
  digest: 17052f91a42e97930aa6e28a6c6c06a983e6a58dbb00434885a0cf5313e376f7
  package: 13 GB

gemma4:26b-a4b-it-q8_0
  digest: 6bfaf9a8cb378e03991da10daa94ea8e85905276d6baaeed67f0b3ae9996fede
  package: 28 GB

qwen3.6:35b-a3b-q8_0
  digest: 0218f872e86baa9c7610509f27db36a7bc52eea7afee24688f81ca74ffcb6c77
  package: 38 GB

gemma4:12b-it-q4_K_M
  digest: 4eb23ef187e2c5462566d6a1d3bbbc2f1346d0b4327cbb66d58fffbcc9b2b05c
  package: 7.6 GB
```

The three newly acquired candidates remain in the local Ollama store for human
review. The complete store now occupies about 95 GB. Removing rejected Qwen
later would recover approximately 38 GB; no model bytes were deleted in this
assessment.

## Behavioral evidence

The deterministic matrix required:

- strict schema output;
- correct diagnosis of an ordering defect;
- a complete path-plus-source Ruby handoff whose tests run inside a bounded,
  networkless Bubblewrap namespace;
- recognition of at least two of path traversal, shell injection, and missing
  resource bounds;
- preservation of primary-agent review, human merge authority, and explicit
  lifecycle states;
- selection of one read-only tool from a synthetic allowlist without execution.

GPT-OSS produced the deepest security review, including shell injection, path
escape, unbounded output, cleanup, and error-handling concerns. Gemma 4 26B was
the only other candidate to identify all three scored security classes in its
passing run. Gemma 4 12B passed the threshold but missed the missing-bound
class. Qwen fast mode alternated between missing constructor validation and
missing security classes. Qwen reasoning mode spent 166.6 seconds on the first
small diagnosis and then returned an empty final response on the next case.

## Transport findings

Both GPT-OSS and Qwen ignored `tool_choice=required` through Ollama's OpenAI
Chat Completions adapter and answered with prose. Both emitted correct native
tool-call objects through `/api/chat`. Gemma candidates also passed native tool
selection. The worker integration must therefore pin and verify its transport;
model capability cannot be inferred from the OpenAI compatibility adapter.

A read-only Codex CLI 0.146 agent trial against Gemma 4 26B did not reach a
usable repository tool loop:

- Codex treated the colon-containing Ollama tag as unknown fallback metadata;
- Codex's model manager expected a different model-list response shape than
  Ollama returned;
- telemetry rejected the model tag and emitted a warning per streamed event;
- the model streamed for several minutes without invoking repository tools.

The run was canceled and made no repository changes. This is an integration
blocker for direct `codex exec` delegation through the tested custom provider,
not a failure of Gemma's bounded model matrix. The next slice should implement
or adapt a Soul-owned bounded worker envelope using the verified native Ollama
transport, then separately requalify direct Codex OSS-provider support when the
model metadata/API mismatch is resolved.

## Why modified/"uncensored" models were not tested

No unmodified candidate produced a task-blocking refusal in this matrix.
Hermes-style neutral-alignment fine-tunes remain plausible when a concrete
behavioral need appears. Abliterated models were excluded because abliteration
suppresses activation directions associated with refusals; that can reduce
irrelevant refusals, but it can also weaken judgment, calibration, and
instruction fidelity. A modified model should be tested only against a
reproducible parent-model refusal, not adopted as a general quality upgrade.

## Files changed

```text
docs/soul/DEV_CORE_MODEL_BAKEOFF_BRIEF.md
docs/assessments/DEV_CORE_MODEL_BAKEOFF.md
scripts/run-dev-core-model-bakeoff.rb
scripts/verify-dev-core-model-bakeoff.rb
Makefile
```

## Commands and deterministic results

```text
ruby -c scripts/run-dev-core-model-bakeoff.rb
  Syntax OK

ruby scripts/verify-dev-core-model-bakeoff.rb
  Dev Core bake-off verifier passed

ruby scripts/run-dev-core-model-bakeoff.rb ...
  GPT-OSS 20B: ok=true
  Gemma 4 26B-A4B Q8: ok=true
  Gemma 4 12B Q4 baseline: ok=true
  Qwen 3.6 35B-A3B Q8 fast: ok=false
  Qwen 3.6 35B-A3B Q8 reasoning: incomplete/failed

curl http://127.0.0.1:18083/api/ps after shutdown
  connection refused (expected)
```

Detailed synthetic outputs remain mode `0600` beneath `/tmp` for the current
review session only. They contain no private user context.

## Required completion artifact fields

- Memory keys added or used: none.
- Task lifecycle states touched: `blocked_for_human_review`.
- Risk classification: medium; local model acquisition and sandboxed execution
  of generated synthetic code, with no production integration.
- Local LLM eval result: recorded above; behavioral evidence only, never safety
  authorization.
- Known weaknesses: compact synthetic matrix; no successful Codex repository
  tool loop; 16K context is below Qwen's recommended long-context setting;
  candidate files consume 75 GB beyond the prior local store.

## Human review checklist

- [ ] Review the recommendation and retained model disk cost.
- [ ] Confirm GPT-OSS 20B as the first Dev Core integration candidate.
- [ ] Decide whether Gemma 4 26B remains installed as a reviewer lane.
- [ ] Decide whether to remove the rejected 38 GB Qwen candidate.
- [ ] Review the native Ollama worker-envelope proposal before any persistent
      Core, dashboard control, or repo-writing authority is implemented.
- [ ] Preserve primary-agent review and human commit/push/merge authority.

## Sources

- Qwen 3.6 model and benchmark card: <https://huggingface.co/Qwen/Qwen3.6-27B>
- Qwen 3.6 Ollama tags: <https://ollama.com/library/qwen3.6/tags>
- OpenAI GPT-OSS overview: <https://openai.com/index/introducing-gpt-oss/>
- GPT-OSS Ollama package: <https://ollama.com/library/gpt-oss:20b>
- Gemma 4 overview: <https://ai.google.dev/gemma/docs/core>
- Gemma 4 Ollama tags: <https://ollama.com/library/gemma4/tags>
