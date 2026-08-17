# Voice Presence A4 - Local Realtime Optimization

```text
date: 2026-08-16
human_authorization: explicitly approved in the active development conversation
implementation_authorized: yes
cloud_voice_provider_authorized: no
risk: Class 4 - visible application-owned local microphone and warm inference lifecycle
```

## Objective

Make the existing local Voice Presence conversation feel substantially closer
to a natural spoken turn without making cloud speech a base dependency. Preserve
the ordinary Chat, skill, Core, confirmation, and privacy boundaries.

## Authorized sequence

1. Record bounded in-memory timing evidence for capture, transcription,
   routing, synthesis, and first playback without retaining spoken content.
2. Tune the existing `Hey Soul` keyword score and threshold through the exact
   manifest, and shorten avoidable wake and end-of-speech delays while retaining
   explicit ceilings.
3. Treat an unambiguous request to repeat the last response as exact replay of
   the active session's most recent WAV. Do not call the model or synthesize it
   again. Explicit rephrase or regeneration requests remain ordinary turns.
4. Permit one transcription worker and one responsive-synthesis worker to stay
   warm only as children of the visible Voice Presence application. They must
   use private pipes or private session files, expose no network listener, and
   terminate when the window pauses, restarts, fails terminally, or closes.
5. Allow incremental response playback only after deterministic ordering and
   cleanup tests prove that chunks cannot overlap, reorder, or survive the
   visible application.
6. Permit ordinary Voice Presence conversation to request the selected local
   provider's reviewed no-reasoning mode and a 384-token spoken-response
   ceiling. An explicit request to think carefully, reason through a problem,
   analyze in depth, or take time must retain the provider's normal reasoning
   path. Dashboard text and deterministic skill routing remain unchanged.

## Lifecycle and retention

The visible PySide application remains the sole residency boundary. No login
unit, daemon, scheduler, network listener, hidden microphone process, or
background continuation is authorized.

The latest successfully spoken response WAV may remain owner-private inside
the active application's mode-0700 temporary directory solely for exact
replay. It is replaced by the next successful response and deleted on restart
or close. No continuous audio, command audio, transcript file, pronunciation
sample, or latency record is retained.

## Bounds

- `Hey Soul` remains the only wake phrase.
- Wake calibration remains manifest-controlled and must be human-tested for
  both successful activation and tolerable false activation.
- Speech start remains at most four seconds; natural follow-up remains exactly
  five seconds; an utterance remains at most thirty seconds.
- Trailing-silence endpoint may be reduced no lower than 0.5 seconds.
- Warm children accept one request at a time and have the existing inference
  timeout ceilings plus explicit termination on parent exit.
- Failure terminates visibly; there is no automatic cloud fallback.
- Low-latency inference is an interface-scoped request policy, not a server
  reconfiguration or a claim that every model supports reasoning control.

## Authority

Latency optimization changes no invocation or approval semantics. A wake phrase,
repeat request, or follow-up never inherits authority. Destructive, privileged,
persistent, Core-changing, publishing, and generation actions retain their
existing human gesture or gate.

## Required evidence

- deterministic timing-stage, exact-replay, no-regeneration, cleanup, wake,
  silence-endpoint, failure, and child-termination checks;
- a before/after local timing sample recorded without speech content;
- a live wake calibration with ordinary room noise;
- proof that repeat replays byte-identical audio and explicit rephrase does not;
- proof that closing Voice Presence leaves no warm inference child;
- updated guide, current-state record, timeline item, and human review artifact.
