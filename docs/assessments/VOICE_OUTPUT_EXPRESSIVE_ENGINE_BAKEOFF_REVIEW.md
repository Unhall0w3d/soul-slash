# Expressive Voice Engine Bake-off Review

## Status

```text
research_complete
date: 2026-07-24
production_voice_changed: no
operator_quality_result: Chatterbox Original preferred over Chatterbox Turbo
```

## Objective

Evaluate Chatterbox and Fish Audio S2 Pro as more expressive local speech
engines without weakening Voice Output A0's bounded one-shot lifecycle,
request privacy, explicit playback, or Core/resource protections.

## Reviewed host

```text
CPU: AMD Ryzen 7 5800X
Memory: 64 GiB
NVIDIA: GeForce GTX 1070, 8 GiB
AMD: Radeon RX 6900 XT, 16 GiB
Active Music Core chat runtime: Qwen3 8B Q4_K_M on NVIDIA
Qwen NVIDIA allocation at idle: approximately 5.3 GiB
```

The host's current AMD inference stack is Vulkan-based. No ROCm/HIP runtime is
installed.

## Engines and exact evaluated material

### Chatterbox

```text
Package: chatterbox-tts 0.1.7
Python: 3.12
PyTorch: 2.6.0+cu124
Original checkpoint: ResembleAI/chatterbox
Original revision: 5bb1f6ee58e50c3b8d408bc82a6d3740c2db6e18
Turbo checkpoint: ResembleAI/chatterbox-turbo
Turbo revision: 749d1c1a46eb10492095d68fbcf55691ccf137cd
License: MIT
```

The isolated package required two compatibility repairs before its CPU path
would initialize: `onnxruntime==1.23.2`, omitted by the Perth dependency, and
`setuptools==80.9.0`, because Perth still imports the removed
`pkg_resources` API.

### Fish Audio S2 Pro

```text
Source: fishaudio/fish-speech
Source revision: e5e292632cb11e7a27b2b7487f58f612bc101e13
Checkpoint: fishaudio/s2-pro
Checkpoint revision: 1de9996b6be38b745688de084d87a5633f714e4e
Model: 4B slow AR + 400M fast AR, approximately 11 GiB of checkpoint material
License: Fish Audio Research License
```

The Fish license permits research and noncommercial use without charge;
commercial use requires a separate license. It is therefore not suitable as
Soul's portable public default.

## Measured results

### Chatterbox beside active Qwen on NVIDIA

Both Original 500M and Turbo 350M failed safely during model load.

```text
NVIDIA capacity: 7.92 GiB
Qwen allocation: approximately 5.17 GiB
Free before test: approximately 2.65 GiB
Chatterbox allocation before failure: approximately 2.60-2.61 GiB
Terminal result: CUDA out of memory
```

Turbo's smaller language model does not sufficiently reduce the shared speech
decoder footprint. Neither variant has safe production headroom beside Qwen
on the 8 GiB card.

### Chatterbox on CPU

Identical text and the local Supertonic F3 synthetic audition were used for
both comparisons.

```text
Original:
  audio: 11.68 seconds
  model load: 6.02 seconds
  synthesis: 50.62 seconds
  real-time factor: 4.334
  peak process RSS: 6.94 GiB

Turbo:
  audio: 13.04 seconds
  model load: 5.12 seconds
  synthesis: 35.65 seconds
  real-time factor: 2.733
  peak process RSS: 6.43 GiB
```

The Operator preferred Original. Turbo misread the adjective "present" as the
noun "present" and its implementation reported that CFG, minimum-p, and
exaggeration controls were ignored. Original preserved the intended phrasing
and produced the more natural result.

CPU operation is memory-safe but too slow for automatic conversational speech.
It remains possible as an explicit quality-first render fallback.

### Chatterbox with transactional NVIDIA time-sharing

Soul's guarded model-runtime controller confirmed zero active slots, deferred
requests, and leases before Qwen was unloaded. A single transaction then
unloaded Qwen, ran Original Chatterbox, exited the voice process, restored
Qwen, and waited for a healthy endpoint.

```text
Qwen guarded unload: 0.95 seconds
Chatterbox load: 11.75 seconds
Chatterbox synthesis: 10.29 seconds for 13.00 seconds of audio
Chatterbox real-time factor: 0.791
Chatterbox peak NVIDIA allocation: 3.73 GiB
Qwen restore through ready health check: 9.31 seconds
Approximate complete post-response cycle: 32.3 seconds
Final Qwen health: ready
Orphan voice processes: none
```

This is viable as an explicit Expressive voice mode. It must not interrupt
active model work, and every failure path must restore and health-check the
prior chat profile.

When Daily Core places Gemma on AMD and leaves NVIDIA free, Chatterbox can use
NVIDIA without displacing the chat engine. Music Core and AMD-Free Core place
Qwen on NVIDIA and therefore require the transactional time-share.

### Fish Audio S2 Pro on CPU

The full checkpoint loaded successfully in 33.31 seconds with ample host
memory. Semantic generation then progressed at roughly 11-14 seconds per
audio token. The bounded eight-word test was canceled after three of a
possible 255 tokens because completion would greatly exceed the ten-minute
limit, before codec decoding.

```text
Model load: complete
Audio generation: canceled as impractical
Audition file: not produced
Official recommended inference VRAM: at least 24 GiB
```

The GTX 1070 and RX 6900 XT are both below the official VRAM recommendation.
The reviewed Fish source adds ROCm support for newer RDNA3/RDNA4 hardware,
while this host's RX 6900 XT is RDNA2 and Soul currently uses Vulkan. Adding
ROCm solely for this engine is not justified by the hardware or result.

## Recommendation

1. Keep Supertonic as Soul's default Responsive voice.
2. Add Chatterbox Original as an explicit Expressive voice candidate.
3. In Daily Core, run Chatterbox one-shot on otherwise-free NVIDIA.
4. In Qwen-driven Cores, use a guarded transaction:
   store completed text, verify idle, unload Qwen, synthesize, release
   Chatterbox, restore Qwen, health-check, then return audio.
5. Keep CPU Chatterbox as a bounded fallback, not the normal path.
6. Do not integrate Fish S2 Pro on this host.
7. Select consented or appropriately licensed feminine and masculine
   reference voices before production promotion. Do not clone a proprietary
   hosted voice.

## Production design requirements

```text
- explicit Responsive / Expressive choice
- completed response durably stored before any model unload
- exclusive model-runtime and specialist-resource lease
- active-work, Core, and prior-profile checks
- bounded synthesis and bounded restore timeout
- unconditional prior-profile restoration on failure or cancellation
- health check before the transaction becomes terminal
- visible composed / rendering voice / restoring chat states
- Supertonic fallback when the transaction cannot begin or complete
- request-private reference conditioning, text, and audio cleanup
- no resident Chatterbox server or background continuation
```

## Commands and deterministic observations

```text
uv isolated environment creation and pinned package installation: pass
Chatterbox CUDA visibility with Qwen resident: pass
Chatterbox Original/Qwen coexistence: safe OOM, no orphan process
Chatterbox Turbo/Qwen coexistence: safe OOM, no orphan process
Chatterbox Original CPU render: pass
Chatterbox Turbo CPU render: pass
Fish S2 Pro CPU model load: pass
Fish S2 Pro bounded CPU generation: canceled as impractical
Guarded Qwen unload/restore transaction: pass
Post-transaction Qwen health: pass
Post-transaction orphan-process check: pass
```

## Memory and lifecycle

```text
Shared Soul memory read or written: none
Conversation history mutated: none
Lifecycle states: complete, failed, canceled, blocked_for_human_review
Persistent service added: no
Daemon added: no
Listener added: no
Scheduled or background work added: no
Production voice selection changed: no
```

## Known weaknesses

- The Chatterbox identity test inherited a synthetic Supertonic reference and
  is not a final Soul voice.
- The complete time-share latency is roughly 32 seconds for a 13-second reply.
- Chatterbox model load dominates latency because the bounded design exits
  after each request.
- The installed Chatterbox package has upstream dependency omissions that
  must be pinned explicitly in any reproducible optional setup.
- Fish was evaluated for feasibility but could not produce a bounded audition
  on this hardware.
- Evaluation runtimes and checkpoints occupy approximately 26 GiB outside the
  repository until the Operator chooses whether to retain them.

## Human review checklist

```text
[x] Compare Chatterbox Original and Turbo using identical text/reference
[x] Record pronunciation/context differences
[x] Confirm Chatterbox cannot safely coexist beside Qwen on 8 GiB NVIDIA
[x] Confirm Qwen restores after transactional NVIDIA use
[x] Confirm Fish CPU feasibility is bounded and does not remain running
[ ] Select final licensed feminine reference voice
[ ] Select final licensed masculine reference voice
[ ] Approve or reject an Expressive voice implementation slice
[ ] Decide whether to retain the 13 GiB Fish evaluation runtime/checkpoint
```
