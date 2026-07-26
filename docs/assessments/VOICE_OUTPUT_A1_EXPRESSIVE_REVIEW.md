# Voice Output A1 — Expressive Delivery Review

## Candidate summary

This slice adds an explicit, browser-local Responsive/Expressive delivery
choice to Chat. Expressive delivery creates a request-private Supertonic
reference, runs pinned Chatterbox Original as a one-shot process, streams
visible stages, and removes all temporary text and audio before return.

When the active NVIDIA chat engine is idle, the existing runtime-control lock
covers stop, Chatterbox rendering, restart, and health verification as one
transaction. Active work is not interrupted. When NVIDIA is otherwise
available, a bounded exclusive specialist lease is used; contention or
unavailability falls back to CPU.

## Files changed

- `lib/soul_core/voice_synthesis_service.rb`
- `lib/soul_core/model_runtime_control_service.rb`
- `lib/soul_core/dashboard_http_application.rb`
- `lib/soul_core/dashboard_command.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `config/voice_expressive_models.json`
- `config/voice_expressive_requirements.txt`
- `scripts/soul-voice-expressive`
- `scripts/soul-voice-expressive-runner.py`
- `scripts/verify-voice-synthesis-a1-expressive.rb`
- `Makefile`, `.env.example`, `config/model_overrides.example.mk`
- `docs/guides/VOICE_OUTPUT.md`

## Verification

```text
ruby -c relevant Ruby files: PASS
python -m py_compile scripts/soul-voice-expressive-runner.py: PASS
node --check assets/dashboard/dashboard.js: PASS
ruby scripts/verify-voice-synthesis-a0.rb: PASS
ruby scripts/verify-voice-synthesis-a1-expressive.rb: PASS
make voice-expressive-check: PASS
ruby bin/soul config validate: PASS
live F3 CUDA synthesis through Qwen release/restore: PASS
```

The setup installed pinned Chatterbox 0.1.7 and verified five model assets
against their declared byte sizes and SHA-256 digests. It added no service,
listener, scheduler, daemon, or resident process.

The live request returned a 541,520-byte WAV. The NVIDIA runtime receipt
reported `restored: true`, `health: ready`, and a 45.322-second guarded release
window.

## Memory, lifecycle, and risk

```text
Shared memory keys added or used: none
Conversation mutation: none
Lifecycle states: complete, failed, awaiting_input, canceled,
  blocked_for_human_review
Risk: temporary GPU resource mutation, guarded and health-verified
Persistent service added: no
Resident speech process: no
```

## Known weaknesses

- Expressive output is slower because model load occurs for every bounded
  request.
- The current voice identity is conditioned from the curated Supertonic
  F3/M3 profile, not a final licensed Soul performance corpus.
- Canceling the browser request does not yet send an early termination signal
  into an inference subprocess already between progress events; the subprocess
  remains bounded by its timeout and the Core restoration `ensure`.
- CPU fallback preserves work but can take roughly a minute for a short reply.

## Human review checklist

- [ ] Confirm Responsive playback still works for F3 and M3.
- [ ] Confirm Expressive playback exposes live status stages.
- [ ] Confirm NVIDIA chat is healthy after an Expressive request in Music Core.
- [ ] Compare the rendered identity and delivery with the bake-off sample.
- [ ] Confirm navigation/cancel never leaves a resident TTS process.
