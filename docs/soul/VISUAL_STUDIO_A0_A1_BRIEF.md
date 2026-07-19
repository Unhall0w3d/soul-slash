# Visual Studio A0–A1 Brief

Status: owner-authorized implementation candidate

Authorization date: 2026-07-18

## Outcome

Add a private local Visual Studio beside Music Studio. Its first complete lane
creates one still-image project, previews one exact operation, runs a bounded
AMD Vulkan renderer, validates the artifact, and returns the candidate for
human review. Music Studio and Visual Studio live under one **Creative Studios**
menu without removing either surface.

## Host decision

The first production-shaped lane is FLUX.2 Klein 4B Q4 through pinned
`stable-diffusion.cpp` Vulkan. The selected checkpoint, Qwen3 text encoder, and
small FLUX.2 decoder total 5,207,178,964 bytes. The host pilot generated a
1024×576 PNG in 9.885 seconds on the RX 6900 XT.

The selection is based on primary project material:

- [stable-diffusion.cpp FLUX.2 guidance](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/flux2.md) documents Klein generation and image-guided editing with the same CLI and an explicit CPU-offload option.
- [FLUX.2 Klein](https://github.com/black-forest-labs/flux2) provides a current unified generation/editing family with an Apache-2.0 4B variant.
- [Z-Image](https://github.com/Tongyi-MAI/Z-Image) is the comparison candidate: its 6B Turbo variant targets 16 GB consumer devices, but its released Turbo lane is generation-focused and the dedicated editing checkpoint is not yet the cleaner first boundary.

## Motion decision

[LTX-Video 2B distilled](https://github.com/Lightricks/LTX-Video) is the lead
short-motion candidate because it supports text-to-video, image-to-video,
keyframes, extension, and CPU offload. It is **not** advertised as ready. Its
official local path is CUDA-first, while this lane must run on Arch Linux and an
RDNA2 RX 6900 XT. A later qualification must measure:

- successful AMD execution without hidden CUDA substitution;
- peak VRAM/RAM and effect on the active Core;
- 4–8 second output integrity and temporal coherence;
- cancellation, timeout, cleanup, and no lingering process;
- whether native execution or an explicitly approved ComfyUI workflow is the
  more maintainable boundary.

Wan2.2 TI2V-5B and HunyuanVideo 1.5 are excluded from this host lane: their
official memory/platform requirements are not a prudent fit for the 16 GB AMD
card. Wan2.1 1.3B remains a lower-quality fallback only if LTX cannot qualify.

## Bounded lifecycle

```text
create project (complete)
  -> generation preview (blocked_for_human_review)
  -> exact digest + click authority
  -> one foreground render (complete / failed / canceled)
  -> candidate (blocked_for_human_review)
```

The runtime is a CLI process, not a listener. It loads for one request and exits.
The source, models, inputs, logs, output digest, elapsed time, and lifecycle are
inspectable. Partial generation directories are removed after a terminal result.

## Storage and authority

- Private projects: `Soul/visual/projects`, ignored by Git, mode 0700/0600.
- Runtime and exact models: `~/.local/share/soul/visual`.
- No Visual Studio candidate enters Music Studio automatically.
- Promotion/binding into a music candidate was excluded from A1 and is supplied
  by the later A2 exact human gate.
- No cloud provider, private prompt transmission, service, watcher, queue,
  scheduler, or automatic publication is introduced.

## Completion boundary

A1 is candidate-complete when deterministic tests pass, the exact host model set
verifies, one real candidate is retained, the authenticated dashboard exposes
the project and image, and the dashboard service restarts successfully. Motion
generation and Music Studio promotion are explicitly later slices.
