# Music Studio A1 Setup Boundary Brief

Status: authorized by repository owner instruction to continue Music A1 and add
`uv` plus exact model overrides to the public Makefile

Authorization date: 2026-07-17

## Outcome

Create the bounded, review-gated setup and download boundary for the isolated
ACE-Step feasibility pilot. The general Soul setup must remain independent of
Music tooling. The recommended GTX 1070 checkpoint pair is the public default,
while exact case-sensitive checkpoint names and a reviewed manifest may be
overridden by the operator.

## Explicitly authorized persistent local artifacts

After an exact preview digest and confirmation, the setup may create a
versioned, user-local checkout and `uv` environment beneath
`~/.local/share/soul/music`. After a separate preview confirmation, it may
download only manifest-pinned model files into that checkout. These are inert
files, not services, listeners, scheduled jobs, or background processes.

## Required boundaries

- `uv` is optional for Soul and required only for Music setup.
- Pin ACE-Step v0.1.8 at revision
  `dce621408bee8c31b4fcf4811682eb9359e1bc94`.
- Use isolated Python 3.12; do not modify Arch's system Python.
- Override upstream CUDA 12.8 wheels with PyTorch 2.10 CUDA 12.6 wheels because
  the GTX 1070 is Pascal SM 6.1. Probe the installed wheel on the real GPU with
  synchronized matrix multiplication and require a compatible same-major cubin.
- Default to `acestep-v15-turbo` and `acestep-5Hz-lm-0.6B` with the PyTorch LM
  backend, CPU offload, batch one, and INT8 weight-only quantization.
- Reject unknown or case-mismatched checkpoint names.
- Keep Qwen inactive while Music owns NVIDIA; keep AMD chat untouched.
- Never auto-download, auto-start, listen, poll, or continue after return.
- Limit pilot durations to 30, 90, and 180 seconds with explicit timeouts.
- Retain generated pilot output for human review and do not promote Music A1
  until the measured feasibility gates are reviewed.

## Excluded

- Music Studio dashboard UI.
- A persistent generation worker, queue, API, service, or model listener.
- Automatic GPU switching, fallback, idle loading, or unload.
- Third-party song ingestion, artist or voice cloning, training, or scraping.
- Claiming that setup verification proves the GTX 1070 pilot is feasible.

## Completion

This setup-boundary candidate is complete when deterministic checks pass. Full
Music A1 remains open until the environment, weights, and 30/90/180-second
foreground pilots are run and the operator reviews their stability, timing,
and audio usefulness.
