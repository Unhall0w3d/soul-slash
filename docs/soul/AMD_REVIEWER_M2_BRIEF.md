# Optional AMD reviewer — M2 bounded runtime pilot

2026-10-13. The operator authorized continuing after the M0/M1 report explicitly
identified M2 as the next bounded AMD inference pilot. This records that scope;
M0/M1's historical brief and receipts remain unchanged.

## Scope and decision

Use the already installed Ollama-bundled llama.cpp server and Vulkan plugin with
the already cached, publisher-hash-pinned Ministral 3 14B Q4_K_M model. This
selects a fitting asset for infrastructure qualification, not a winning reviewer.
Do not install/download anything, change services or Core selection, interrupt
NVIDIA Qwen, train adapters, integrate LibreChat, promote memory, or edit M1's
fingerprinted store implementation. M2 records are isolated qualification data,
not M1 completed review artifacts or independent validation of a primary task.

Primary owns `scripts/qualify-amd-reviewer-m2.rb`, protocol/lifecycle boundaries,
this brief, assessment and review-index entries. A test worker may own only
`scripts/verify-amd-reviewer-m2.rb`. Preserve all existing dirty work.

## Frozen pilot protocol

- Fixed installed `/usr/lib/ollama/llama-server` and Vulkan plugin; record binary,
  shared-library, model, template, protocol and source digests. Verify publisher
  size and SHA256 before launch. RADV ICD, Vulkan0 RX 6900 XT only; CUDA hidden.
- Reuse `amd-vulkan-generation` via the existing external AMD workload gate.
  Require at least 11 GiB initially free and the unchanged foreign-allocation
  admission check. Busy means explicitly unavailable; do not evict anything,
  weaken admission, substitute another model, retry automatically or wait forever.
- One foreground window, at most 900 seconds, startup at most 180 seconds,
  each request at most 90 seconds. Temporary listener only on 127.0.0.1:8096,
  one slot, web UI and agent tools disabled. No service or startup registration.
  No inherited LLAMA_ARG/HF/provider settings may change the fixed launch.
  Offline mode, fixed same-origin CORS and a fresh local-only API key file
  protect the temporary endpoint; never print that key in receipts or chat.
- Model-native template, 4096 context, at most 3072 input tokens, 768 output
  tokens, seed 4242, temperature .05, top-p 1, top-k 0, no prompt cache or context
  shifting. Full GPU-layer request, fit disabled: unsupported/OOM is failure,
  not silent CPU fallback. Native log and DRM evidence must corroborate offload.
- Three synthetic independent requests: a supported answer, a contradicted
  arithmetic answer and an absent-evidence answer. Closed M1 response shape,
  source/evidence hashes retained. These are smoke cases, not M3 quality scores,
  self-review controls or fresh evidence of general reviewer superiority.
- One cancellation request after first output, close stream then terminate the
  owned server, verify process/listener/VRAM release. One fresh reload and short
  request then normal termination. At most five generation requests total.
- Sample whole-host RAM, swap counters and AMD memory/thermals every two seconds.
  Abort at edge >=80 C, hotspot >=95 C, <2 GiB GPU free, <8 GiB RAM available,
  >256 MiB swap-out since start, or log >16 MiB. These are conservative pilot
  bounds, not hardware maximum claims. Report whole-host counters as such.
- Reap only the owned child; TERM then bounded KILL fallback. No arbitrary PID
  cleanup. On abnormal parent death, retained launch PID/start identity plus
  lease/evidence requires inspection; do not auto-resubmit. Cooperative leasing
  is not an OS-wide reservation against games launched mid-run.

## Acceptance and reporting

Run Ruby syntax and targeted deterministic protocol/lifecycle tests, unchanged
M1 contract checks, external AMD gate checks and changed-path-required checks.
Test occupied endpoint, unsafe paths, budget/response limits, invalid output,
source binding, timeouts and child teardown without GPU inference.

Live acceptance requires exact runtime/model identity, valid nontruncated
responses, measured startup/first-token/decode timing, bounded cancellation and
reload, owned process gone, endpoint closed, memory released within 256 MiB of
initial usage (allow bounded driver settling), shared lease gone, and unchanged
Qwen PID/config and existing source hashes. Separate blocked admission, startup,
harness, behavioral and host-resource failures. Preserve first failures; fixes
receive new evidence roots, not overwritten results. No M3/M4 promotion follows
automatically. Update the canonical review packets with actual evidence.

## First-attempt adjustment

The first loader attempt passed device admission and loaded, then failed the
mandatory full-offload log assertion before generation. Its default verbosity
omitted that evidence. Preserve the attempt and repeat only in a new evidence
root with verbosity 4; do not weaken the offload assertion. The loopback
endpoint's default permissive CORS warning also prompted explicit same-origin
CORS plus a fresh private key file. These are runtime/harness adjustments, not
changes to test answers, model weights, resource limits or semantic criteria.

The second loader attempt produced the required 41/41 offload line, but raw
non-UTF-8 vocabulary bytes caused an ASCII diagnostic scan to fail before
generation. The third attempt uses byte-safe matching of that same evidence.
Retain the second result as a harness failure: the shared gate's `blocked`
label came from its broad ArgumentError handling, not actual busy admission.
M2 now wraps post-admission ArgumentError as a pilot failure. This correction
changes neither the model protocol nor the admission guard.
