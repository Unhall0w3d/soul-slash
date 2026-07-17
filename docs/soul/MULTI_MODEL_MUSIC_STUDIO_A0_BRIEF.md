# Multi-Model and Music Studio A0 Research Brief

Status: authorized by repository owner instruction to proceed with the next slice

Authorization date: 2026-07-17

## Outcome

Produce a host-specific architecture and implementation sequence for a future
Music Studio capable of iterative 2–3 minute local song creation. Define how
Soul's current conversation model, NVIDIA fallback, music generation, audio
analysis, future speech, and optional specialist models share the existing
hardware without automatic switching or hidden background work.

## Authorized work

- Inspect installed hardware and runtime versions read-only.
- Research current model/runtime capabilities using primary sources.
- Compare candidates against the RX 6900 XT, GTX 1070, Ryzen 7 5800X, and
  62 GiB system RAM.
- Define project storage, reference provenance, task lifecycle, resource
  arbitration, dashboard workflow, cancellation, and human review gates.
- Correct stale roadmap state for already-completed A4–A5 work.
- Add deterministic documentation verification and a human review artifact.

## Explicitly excluded

- Downloading model weights or repositories.
- Installing Python, ROCm, CUDA, audio, or system packages.
- Starting a model, API server, listener, container, service, or background job.
- Adding the Music Studio dashboard tab before the generation boundary exists.
- Uploading, downloading, scraping, copying, training on, or generating from
  third-party songs.
- Creating an artist-cloning or voice-cloning workflow.
- Changing the active conversation model or selected startup profile.
- Enabling automatic model selection, fallback, idle loading, or unloading.
- Treating vendor benchmarks, model output, or generated music as safety,
  originality, rights, quality, or release approval.

## Required decisions

- Name one lead foreground pilot and at least one comparison candidate.
- State which GPU each role uses and which roles are mutually exclusive.
- Define a no-reboot, manual resource handoff compatible with current runtime
  leases and idle checks.
- Define how lawful reference audio is distinguished from research notes and
  distilled musical concepts.
- Define bounded terminal lifecycle, progress, cancellation, failure, partial
  output, and review behavior.
- Define a phased path from CLI benchmark to dashboard integration.

## Completion

This A0 slice is documentation and architecture only. It terminates complete
when deterministic documentation checks pass and remains candidate work for
human review. It authorizes no A1 installation or model pilot.
