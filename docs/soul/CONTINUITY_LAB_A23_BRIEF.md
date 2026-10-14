# A23: four-model NVIDIA/CPU comparison

2026-10-13. The owner explicitly approved testing Qwen3.6-35B MoE,
Ministral 3 14B Instruct (the preceding shortlist's 14B), Qwen3-30B MoE,
and the existing Qwen3-8B, adapting to model variation. This is a bounded
foreground experiment, not a replacement approval or LibreChat activation.

## Frozen initial protocol

- Reuse fifteen synthetic requests: six A20 selection cases, four A19 chronology
  turns, A18 absent-warranty, and four A15 ordinary-conversation turns. Preserve
  every raw request/response, template, tokenizer count, runtime arguments and
  source/model digests. No private conversation, ordinary memory or tool actions.
- Same semantic system/reference/request messages, history policy and answer-only JSON
  grammar. Each model uses its embedded template/tokenizer. Disable thinking where
  supported; use recorded model-appropriate sampler settings. This compares usable
  model configurations, not architecture alone. Existing 8B sampler remains its
  qualified baseline. Keep 4096 context, at most 3072 input and 768 output tokens,
  three prior exchanges, one slot; refuse oversized input rather than trim evidence.
  Standalone prompts are paired. Multi-turn groups are closed-loop trajectories:
  each model receives its own earlier replies, not a teacher-forced correct answer.
  Their later histories therefore differ. Report trajectory quality separately;
  do not describe later-turn prompts as byte-identical. Invalid/truncated outputs
  stop their dependent chain with explicit skipped rows in the fixed denominator.
- Initial budget: fifteen scored generations plus one warmup per model, maximum
  120 seconds per generation, 45 minutes total live window. At most two additional
  startup-placement attempts per candidate, without rerunning scored answers.
  Failed attempts remain visible. Additional protocol revisions require a new
  recorded experiment, not silent rescoring or replacing first results.
- Report mechanical screens separately from primary semantic assessment. Check
  every constraint, contradictions, unsupported assertions, corrections and recall;
  ordinary conversation also needs qualitative review. Historical regex false
  positives/negatives are not ground truth. A pilot is not universal reliability.
- Usability target: roughly 200-token answers in 30 seconds, no sustained paging,
  no thermal/driver instability, meaningful quality gain without important observed
  regressions. Report actual output lengths, first-token and complete-answer latency,
  prompt/decode speeds, RAM, VRAM and paging; do not manufacture exact-length answers.

## Host scope and recovery

Primary downloads only the three pinned public GGUFs (about 49 GB total) into
`/home/bhones/ai_models/continuity-a23`, verifies publisher size/SHA256, and retains
them. No executable remote installer or remote model code is run. The existing
Pascal-targeted b9851 runtime is the initial candidate runtime, not overwritten.

Use the existing model-runtime control lock; refuse retained leases, pending
transitions, busy slots or foreign NVIDIA compute clients. Before switching,
record and verify baseline process/config identity and idle state. Temporarily
stop only `llama-server.service`; start each candidate as an owned bounded child
on a separate loopback endpoint. No systemd edits, default/Core changes, firewall
changes, root operation, AMD GPU inference or unattended persistence. Kill/reap
only owned candidate children on failure/cancel/deadline. Always restore the
previously active unchanged service and verify its model/template/health/idle
state. If restoration cannot be verified, report explicitly and do not continue.

The user-authorized test window covers temporary model replacement and local
inference; supported sandbox escalation is still required. Downloads have bounded
timeouts and resume only verified-path partials. Retain evidence locally under
`Soul/runtime/qualification/continuity-model-a23-*`; no cleanup or Git promotion.
The temporary comparison adapter never weakens A19/A22's production identity gates.

Deliver comparative results, configuration differences, failures and limitations,
restoration evidence, and a recommendation before any LibreChat connection.

## A23b placement follow-up (declared before execution)

Initial CPU-expert placement left substantial VRAM unused and incurred long
prompt processing. After the initial four-model run and verified restoration,
replay the same fifteen requests and one warmup for each of Qwen35 and Qwen30
with automatic complete-layer fitting (remove `--cpu-moe`) and `--flash-attn auto`.
Keep all other settings, assets, prompts/history policy, guards and restoration
unchanged. This is 32 additional generations, bounded by a separate 45-minute
window and the same 120-second request deadline. Do not retry failed answers.

Use `scripts/compare-continuity-placement-a23.rb` and a separate
`continuity-placement-a23-*` evidence root. Compare configurations; two changed
settings do not isolate a causal mechanism. The repeated cases are development
replays, not new held-out evidence, and kernel changes can alter model answers.
No prompt-specific hints, tuned answers, runtime rebuild or permanent promotion.
