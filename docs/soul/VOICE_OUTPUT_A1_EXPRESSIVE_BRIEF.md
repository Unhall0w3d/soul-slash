# Voice Output A1 Expressive Brief

```text
date: 2026-07-24
human_authorization: approved in the active development conversation
implementation_authorized: yes
human_voice_selection_review_required: yes
risk: Class 3 - authenticated local synthesis with guarded accelerator time-sharing
```

## Objective

Add an explicit **Expressive** voice option to dashboard Chat while preserving
Supertonic as the immediate **Responsive** default. Expressive synthesis uses
the reviewed Chatterbox Original model as one bounded foreground process. It
may temporarily release an idle Qwen NVIDIA runtime only after Soul has
already completed and stored the text response, and must restore and
health-check the prior runtime before returning audio.

## Authorized vertical slice

- Keep the existing per-message explicit Speak/Stop interaction.
- Add a browser-local Responsive/Expressive quality selector independent of
  the feminine/masculine identity selector.
- Use Supertonic F3 or M3 to create a request-private conditioning clip.
- Run pinned Chatterbox Original one-shot on otherwise-free NVIDIA.
- When Qwen owns NVIDIA, require a verified idle state, hold Soul's existing
  model-runtime control lock for the complete release/synthesis/restore
  transaction, restore the exact prior profile in every ordinary terminal
  path, and health-check it before returning.
- Use bounded CPU Chatterbox only when NVIDIA cannot be safely claimed without
  changing the active chat runtime.
- Stream bounded lifecycle messages to the authenticated dashboard while the
  foreground request remains open.
- Preserve Supertonic as fallback when Expressive cannot safely begin.
- Provide portable check, plan, install, and verification targets.

## Lifecycle

```text
idle
-> explicit Speak click with Expressive selected
-> authenticated same-origin CSRF-protected stream
-> validate text, profile, pinned runtime, and exclusive request lock
-> create private Supertonic conditioning clip
-> inspect current Core/model ownership
-> direct NVIDIA / guarded temporary Qwen release / bounded CPU fallback
-> run one Chatterbox process
-> restore and health-check prior Qwen profile when released
-> delete private text, conditioning audio, and expressive WAV
-> stream terminal audio to browser
-> playback ended / explicit Stop / Chat exit / logout
-> revoke browser object URL
```

Terminal outcomes are:

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

## Resource and failure boundary

- A completed assistant response must exist before speech is requested; voice
  output never generates or mutates conversation text.
- Active model slots, deferred work, or leases block temporary Qwen release.
- The existing model-runtime control lock remains held while Qwen is released,
  preventing another runtime or specialist from claiming the resource.
- Chatterbox has a bounded timeout and is terminated with its process group.
- Qwen restoration is attempted even when Chatterbox fails or the browser
  disconnects.
- Failure to restore Qwen is a visible terminal failure and never reported as
  successful speech.
- No voice daemon, server, listener, queue, scheduler, automatic narration, or
  background continuation is added.

## Privacy and identity boundary

- The conditioning clip is synthesized from the reviewed local Supertonic
  profile and is not a recording of the Operator or a proprietary voice.
- Conditioning text, conditioning audio, response text, and result audio are
  request-private and deleted before the service returns.
- No voice material enters shared memory or conversation attachments.
- Chatterbox watermarking remains enabled.

## Required evidence

- pinned offline Chatterbox readiness and setup behavior;
- direct NVIDIA, guarded Qwen time-share, CPU fallback, busy, timeout,
  restoration-failure, and cleanup tests;
- authentication, Origin, CSRF, request-size, and streaming terminal behavior;
- explicit Responsive/Expressive and feminine/masculine choices;
- visible lifecycle states with no polling or background job;
- live Qwen release, expressive synthesis, restore, health, and browser
  playback review.
