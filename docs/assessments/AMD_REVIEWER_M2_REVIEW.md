# Optional AMD reviewer — M2 live runtime pilot

2026-10-13. **M2 infrastructure pilot passed; reviewer quality is not qualified.**
Scope: [M2 brief](../soul/AMD_REVIEWER_M2_BRIEF.md). No production reviewer,
Soul/LibreChat delivery, model replacement, training or automatic job was enabled.

## Result

The existing Ollama 0.33.3-1 / ollama-vulkan 0.33.3-1 installation supplied
`/usr/lib/ollama/llama-server`, version `0.3.0-dev`, build 1, commit `0f3a71be1`,
and its Vulkan plugin. No install or download was needed. Cached Ministral 3 14B
Instruct Q4_K_M matched the pinned publisher SHA256
`824e0f3373e69b84f2cae46fdcb9bd1ebc6ab3bfc7acc125d818b7b8178cc613`.
All 41/41 layers loaded on Vulkan0, the RX 6900 XT at `0000:0a:00.0`.
Native logs, mapped plugin and the launched PID's DRM allocation corroborate
offload. The owned allocation was about 7.98 GiB, including KV and compute buffers.

One successful window returned three closed-schema, nontruncated review responses,
canceled a fourth request after a nonterminal content event, terminated/reaped
the owned runtime, released memory, reloaded, and returned a fifth response.
The reload reuses the supported case; it is not another independent quality case.

| Measurement | Observed |
| --- | --- |
| Startup / reload | 2.745 / 2.750 seconds |
| Supported / arithmetic / absent-evidence reply | 3.296 / 4.713 / 5.242 seconds |
| First content, those three replies | 0.923 / 0.795 / 0.826 seconds |
| Native decode throughput | 45.5–47.7 tokens/second |
| Native prompt throughput | 668–881 tokens/second |
| Output token counts | 109 / 188 / 211 |
| Reload reply | 3.290 seconds, 109 tokens |
| Intentional cancellation: first content / reap after cancellation | 0.793 / 0.200 seconds |
| Peak sampled whole-device VRAM | 10.83 GiB |
| Peak sampled edge / junction / memory temperature | 75 / 80 / 60 C |
| Minimum sampled available system RAM | 37.16 GiB |
| Successful window swap-in / swap-out | 7 / 0 pages (4 KiB/page) |

Startup excludes preflight hashing. Replies exclude startup/template/tokenization;
first content measures streaming completion-request latency. Throughput uses the
runtime's native timing/token counters, not a tokenizer-independent benchmark.
Samples were every two seconds (11 samples), so peaks are sampled, not maxima
guaranteed across every instant. This short run does not qualify sustained
thermals, gaming coexistence or subjective desktop responsiveness.

## Semantic observations — not three automatic passes

- Supported answer: correctly accepted the amber beacon and cited `source1`.
- Contradicted arithmetic: correctly identified `3 × 17 = 51`, not 54, and cited
  `source1`.
- Absent evidence: correctly explained that the three-year warranty was not
  supported, but chose **contradicted**, not **insufficient_evidence**. Missing
  proof is not proof of falsity. Its finding referred to `source1` in prose but
  left `evidence_refs` empty, and included an irrelevant supported weight claim.

These are concrete M3 calibration/protocol concerns, not a reason to relabel the
output as correct or silently repair it. M2's closed schema permits an empty
reference list; shape validation did not establish sound epistemic judgment.
The repeated supported reply after reload was identical in content, but one
repeat does not prove determinism. No self-review or evidence-first comparison
was run, no quality superiority was established, and nothing was fed back to Soul.

## Attempts, failures and recovery

Evidence is retained under `Soul/runtime/qualification/`:

1. `amd-reviewer-m2-20261013T190626Z-20261013-1892136-gg0nxv`: loaded, then
   failed before generation because default logs omitted mandatory offload
   evidence. Default CORS warning prompted same-origin configuration and a
   fresh local API key for later attempts. Whole-host swap-out increased by
   151.54 MiB during this attempt, including preflight; exclusive attribution
   to the model is not established. It was below the 256 MiB stop threshold.
2. `amd-reviewer-m2-20261013T190844Z-20261013-1894983-p7jf7r`: 41/41 offload was
   logged, but raw non-UTF-8 vocabulary bytes broke the diagnostic parser.
   No generation occurred. The original gate receipt says `blocked`; this was
   a harness ArgumentError, not busy GPU admission. Byte-safe matching and
   explicit post-admission error classification fix that distinction.
3. `amd-reviewer-m2-20261013T191032Z-20261013-1896788-j8wnf`: full successful
   window above, exit 0, no extra swap-out. Earlier attempts remain unchanged.

An earlier advisory check refused a transient foreign AMD allocation. A later
DRM inventory showed desktop applications and no game; it did not establish
which allocation triggered the earlier rejection. The actual launch independently
passed the unchanged guard. Nothing was evicted or whitelisted to make it pass.

Every attempt's read-back confirmed unchanged baseline state, released lease
and closed temporary endpoint. The successful window's `primary-closeout.json`
independently confirms Qwen PID **1079343**, active/running on NVIDIA as its sole
compute client, inactive AMD model services, unchanged Hyprland/quickshell PIDs,
no listener on 8096, and approximately 13.22 GiB AMD memory available afterward.
All 53 preserved source/configuration hashes and inventoried runtime hashes
matched; no production source, service, Core/default or M1 store was changed.

## Implementation and deterministic evidence

[Foreground pilot](../../scripts/qualify-amd-reviewer-m2.rb) and
[synthetic verifier](../../scripts/verify-amd-reviewer-m2.rb) are repository-local.
Existing M1 classes and the shared gate were reused without edits. Private new
qualification directories retain packets, revisions, native streams, launch
arguments, code/runtime hashes, GPU telemetry and preservation records. Local
ephemeral API keys remain in private files; do not print or export those files.

- 32/32 M2 grouped deterministic checks pass.
- 23/23 unchanged M1 contract/workflow checks pass.
- 14 existing external AMD workload gate checks pass.
- Both new Ruby files pass pinned Ruby 4.0.7 syntax checks; changed-path routing,
  whitespace and documentation link checks pass.

Focused review led to fixes for startup deadline/resource-abort propagation,
retaining the lease when child teardown is unconfirmed, PID-bound DRM evidence,
and rejecting terminal-first output as a false cancellation pass. Live failures
added the byte-safe diagnostic regression. A synthetic authentication check
confirms the local key goes in the request header, not URL/body. Those checks
do not establish broad security or isolation from a malicious same-UID process.

The retained-lease path is an inspection requirement, not an indefinite hardware
reservation: existing lease expiry/owner-death rules still apply, and the foreign
DRM guard remains essential. Parent SIGKILL/host loss was not live-qualified in
M2. Only successful bounded request cancellation plus full model termination
was exercised; this is not cancellation while leaving a shared model resident.

## Next gate

M3 should test actual net correction benefit using fresh held-out inputs,
Qwen8 self-review and evidence-first controls, explicitly distinguishing false
claims from unsupported claims and measuring spoiled correct answers. Keep
source/evidence revisions fixed and preserve every raw result. M2 does not
select Ministral as a production reviewer, authorize LoRA or grant M4 visibility.
The existing LibreChat connection candidate remains unchanged; an AMD reviewer
is optional, not a new prerequisite for that connection.

No commit/push, deletion, private-data transfer, deployment, scheduled
continuation or running candidate remains. Ordinary Soul memory keys used: none.
