# Visual Studio A3 — Local Motion Qualification

Status: owner-authorized implementation candidate

Authorization date: 2026-07-21

## Outcome

Establish one isolated, reproducible, bounded path for determining whether this
host can create useful AI video locally. The first measured operation animates
one reviewed still into a 4.125-second clip. It does not yet add a production
generation button or change Music Studio export behavior.

If the host pilot passes technical and human review, the next slice will expose
the same operation as a Visual Studio motion candidate and allow a reviewed
motion candidate to replace a static still in the existing music-companion
binding and export pipeline.

## Selection

The qualification candidate is **Wan 2.2 TI2V 5B Q4_K_M** through a separately
pinned `stable-diffusion.cpp` Vulkan build:

- unified image-to-video and text-to-video architecture;
- a 5B dense model rather than a much larger current LTX model;
- current `stable-diffusion.cpp` support for Wan 2.1/2.2 on Vulkan;
- quantized diffusion and text-encoder weights with CPU offload;
- Apache-2.0 model license.

The exact runtime revision and 8,520,510,320 model bytes are pinned in
`config/visual_motion_models.json`. The official Wan implementation calls for at
least 24 GiB VRAM at 720p, so fitting the Q4 Vulkan path into this RX 6900 XT is
a hypothesis to measure, not a compatibility claim.

LTX-Video is no longer the first candidate. Current LTX support in the selected
runtime targets LTX-2.3, a substantially larger 22B lane with additional Gemma,
connector, VAE, and upscaler dependencies. It remains a possible future option,
not the prudent initial 16 GiB test.

Primary references:

- [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)
- [stable-diffusion.cpp Wan guide](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/wan.md)
- [Wan 2.2](https://github.com/Wan-Video/Wan2.2)
- [Wan 2.2 TI2V 5B model](https://huggingface.co/Wan-AI/Wan2.2-TI2V-5B)

## Measured pilot

The first profile is intentionally conservative and fixed:

```text
mode: image to video
canvas: 832x480
frames: 33 (Wan-compatible 4n+1 sequence)
frame rate: 8 fps
nominal duration: 4.125 seconds
steps: 20
CFG: 6.0
sampler: Euler
flow shift: 3.0
backend: AMD Vulkan with CPU offload
decoder: taew2_2 TAEHV
```

The source image, prompt, negative prompt, seed, runtime revision, exact model
digests, and fixed profile are included in the preview digest. A stale or
altered plan cannot execute.

The first live attempt completed 20/20 Vulkan denoising steps in 90.22 seconds,
then lost the AMD device context during full VAE GPU decode. A CPU-only full VAE
retry remained unfinished after roughly fourteen minutes while using about 50
GiB RAM, so it was canceled as production-imprudent. The runtime's Wan guidance
explicitly recommends TAEHV when the full VAE needs too much VRAM and identifies
`taew2_2.safetensors` for Wan 2.2 TI2V 5B. The qualification profile therefore
pins that exact 22,848,048-byte decoder; human review must judge its documented
quality tradeoff.

## Lifecycle

```text
check -> complete
setup plan -> blocked_for_human_review
exact setup -> complete / failed
download plan -> blocked_for_human_review
exact download -> complete / failed
pilot plan -> blocked_for_human_review
exact pilot -> blocked_for_human_review / failed / canceled
```

Each mutation is an explicit foreground command. The renderer has a fixed
one-hour ceiling, owns one process group, terminates that group on timeout or
interruption, validates the resulting video with `ffprobe`, and removes partial
run state before returning failure. Successful output is immutable, digest
identified, and retained for human review.

## Storage and isolation

- Runtime: `~/.local/share/soul/visual-motion`
- Existing still runtime: unchanged at `~/.local/share/soul/visual`
- Pilot outputs: `~/.local/share/soul/visual-motion/runs`
- No model is loaded between invocations.
- No service, network listener, queue, scheduler, watcher, automatic retry, or
  background continuation is introduced.
- No pilot result is automatically bound to Visual Studio or Music Studio.
- No existing still candidate, music candidate, or export is modified.

## Technical qualification gate

The pilot must demonstrate:

- the command uses the Vulkan build and does not substitute CUDA;
- the RX 6900 XT completes without destabilizing the desktop or active Core;
- the output is a readable video stream at the expected dimensions and bounded
  duration;
- source and output hashes, elapsed time, and exact configuration are retained;
- timeout/interruption removes partial state and leaves no child renderer;
- the runtime exits and releases GPU resources after completion.

## Human qualification gate

Technical success is not production approval. The operator reviews temporal
coherence, unwanted camera motion, subject deformation, color stability,
looping potential, and whether the result is meaningfully better than a static
presentation. Dashboard enablement remains a separate owner decision.

## Completion boundary

A3 qualification tooling is candidate-complete when its deterministic verifier
passes and the setup, download, and pilot plans are inspectable. It stops at the
human installation/download gate. A real pilot and production Visual Studio
integration are later approved actions.
