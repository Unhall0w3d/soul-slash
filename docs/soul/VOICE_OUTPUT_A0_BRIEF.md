# Voice Output A0 Brief

```text
date: 2026-07-24
human_authorization: approved in the active development conversation
implementation_authorized: yes
human_voice_selection_review_required: yes
risk: Class 3 - authenticated local synthesis of conversation text
```

## Objective

Give Soul a bounded local voice through an explicit `Speak` control attached
to each eligible assistant message in dashboard Chat. Playback begins only
after the Operator requests it and can be stopped immediately. Voice A0 does
not automatically narrate responses or create a resident speech process.

## Authorized vertical slice

- Evaluate small, matched sets of current locally runnable feminine and
  masculine voices.
- Select one reviewed high-quality profile in each range while keeping the
  engine, exact model, default voice, and speaking rate configurable.
- Allow the Operator to hot-swap between the curated profiles per request
  without restarting the dashboard or changing Cores.
- One authenticated, same-origin, CSRF-protected synthesis route.
- A strict text ceiling, one foreground synthesis at a time, bounded inference
  timeout, bounded output size, and explicit busy/failure behavior.
- Request-private text and audio files removed at every terminal outcome.
- Per-assistant-message `Speak` / `Stop` controls in dashboard Chat.
- One active playback at a time; starting another stops and disposes the first.
- Portable check, plan, install, and audition commands plus public dependency
  documentation.

## Lifecycle

```text
idle
-> explicit Speak click
-> authenticated bounded request
-> eligibility and text-size validation
-> one foreground local synthesis
-> complete / awaiting_input / failed / canceled / blocked_for_human_review
-> delete request-private synthesis files
-> browser playback
-> ended / explicit Stop / Chat exit / logout
-> revoke the browser object URL
```

## Restraint and privacy boundary

- No automatic narration, wake word, always-speaking mode, queue, daemon,
  server, new listener, scheduler, watcher, or background continuation.
- Soul and the local model cannot decide to activate the voice.
- Code blocks, machine payloads, raw URLs, and control/confirmation phrases are
  excluded from spoken text rather than treated as prose.
- Speech never bypasses intent classification, skill routing, Core changes,
  destructive previews, or confirmation gates.
- Synthesis input and output are disposable request material and are not
  written to shared memory or retained as conversation artifacts.
- The selected voice must be an available local profile. This work does not
  clone, impersonate, or claim access to a proprietary hosted voice.

## Portable dependency contract

The reviewed default uses a pinned, open local ONNX speech engine in a
user-local isolated runtime. Installation occurs only through the explicit
Make target. Public clones can override the runtime root, exact manifest, voice
profile, and speaking rate. Unknown or altered assets fail closed.

The dashboard does not depend on host-specific audio output packages: it
returns a standard WAV response and the authenticated browser performs
playback.

## Required evidence

- deterministic readiness, synthesis, timeout, busy, invalid-text, and cleanup
  behavior;
- authentication, Origin, CSRF, content-type, and request-size enforcement;
- one active synthesis and one active playback at a time;
- explicit Speak/Stop behavior, reduced-motion support, and Chat-exit cleanup;
- no automatic narration, persistence, or new resident process;
- local audition files for human voice selection;
- live browser playback review through the authenticated dashboard.
