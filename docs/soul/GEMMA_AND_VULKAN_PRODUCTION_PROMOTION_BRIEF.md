# Gemma and Vulkan production promotion brief

Status: human-approved implementation scope (2026-07-18)

## Objective

Promote the reviewed Gemma 4 12B Instruct Q4_K_M Ollama/Vulkan profile to
Soul's supported AMD Daily Core, retire Ministral 3 14B from the supported
runtime inventory, and promote the accepted ACE-Step 1.5 4B LM / 2B Turbo
Q8_0 Vulkan pipeline to the Music Core.

## Runtime contract

- Daily Core: Gemma 4 12B Instruct Q4_K_M on AMD Vulkan through the local
  loopback Ollama-compatible service. NVIDIA remains free for bounded tools.
- Music Core: Qwen3 8B Q4_K_M on NVIDIA provides reserve chat while the
  foreground ACE-Step Vulkan process uses AMD.
- AMD-Free Core: Qwen3 on NVIDIA; AMD is reserved for the Operator and music
  generation is unavailable.
- Ministral is removed from the supported profile file, startup selection,
  Core selection, dashboard identity, setup guidance, and current-state docs.
  Historical bake-off evidence may continue to name it. Model weights are not
  deleted by this promotion.

## Music execution contract

- The pinned `acestep.cpp` and GGUF revisions remain immutable and hash checked.
- Generation is a foreground operation. No listener, daemon, service, watcher,
  scheduled task, or background continuation is added.
- Supported Music Core durations are exactly 30, 90, and 180 seconds.
- One approved generation may perform at most three LM planning attempts.
  Degenerate audio-code plans are rejected before synthesis; a deterministic
  new LM seed is used for the next attempt. Three consecutive collapses end as
  `blocked_for_human_review`.
- VAE chunking remains 256. Batch size remains one. CPU/GPU offload is disabled.
- The selected WAV intermediate is converted to a 48 kHz stereo FLAC master
  and an MP3 listening copy, then removed. Failed partial work remains bounded
  in the candidate quarantine for review rather than being published.
- The existing exact project/revision confirmation gate remains authoritative.
  Automatic LM recovery does not broaden that approval to another project or
  another candidate.

## Lifecycle and risk

Terminal states are `complete`, `failed`, `awaiting_input`, `canceled`, or
`blocked_for_human_review`. Generated candidates always stop at human listening
review. Risk is high for local GPU availability and medium for private project
data; no privileged or destructive host action is part of generation.

## Live promotion boundary

The already-installed Gemma and Qwen user services may be switched through the
existing digest-bound Core controller. The obsolete Ministral service may be
stopped and disabled after Gemma is selected. Removing its unit or model file is
a separate destructive cleanup and is not authorized by this brief.

## Acceptance

- Deterministic runtime, Core, dashboard, generation, cancellation, and collapse
  tests pass.
- A live Music Core inventory identifies Qwen chat plus AMD Vulkan music.
- A live Daily Core inventory identifies Gemma as the selected and active chat
  runtime after promotion.
- Dashboard status contains no candidate/pilot or Ministral identity for the
  supported production paths.
- Review artifact records commands, results, known weaknesses, lifecycle states,
  memory use, and human checks.
