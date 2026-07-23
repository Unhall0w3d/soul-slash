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

## Motion decision (superseded by A3 research)

The original LTX-Video 2B choice was a research placeholder. Visual Studio A3
selects Wan 2.2 TI2V 5B Q4 for the measured pilot because current
`stable-diffusion.cpp` supports Wan 2.2 through Vulkan and the current LTX
family is no longer the prudent 16 GiB first target. It is **not** advertised as
ready. A3 must measure:

- successful AMD execution without hidden CUDA substitution;
- peak VRAM/RAM and effect on the active Core;
- 4–8 second output integrity and temporal coherence;
- cancellation, timeout, cleanup, and no lingering process;
- whether native execution or an explicitly approved ComfyUI workflow is the
  more maintainable boundary.

The official Wan Python path targets larger cards. A3 therefore treats the Q4
Vulkan/CPU-offload path as an experiment, not a production capability. See
`VISUAL_STUDIO_A3_MOTION_QUALIFICATION_BRIEF.md`.

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
