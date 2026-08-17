# Voice Presence A4 Local Latency Review

## Candidate status

The first local-only latency slice is candidate-complete for deterministic and
live human review. It does not add a cloud dependency or a process that survives
the visible Voice Presence application.

## Implemented in this slice

- content-free in-memory timings for capture, transcription, Soul routing,
  synthesis, audio readiness, and first playback;
- a 0.95-second trailing-silence endpoint that preserves natural mid-sentence
  pauses and a 0.18-second wake-cue guard matching the existing 0.16-second
  static cue;
- an easier manifest-controlled `Hey Soul` calibration candidate at boost 3.5
  and threshold 0.15;
- exact active-session replay for narrow natural repeat requests, without a
  model call or new speech synthesis;
- replacement and close/restart cleanup of the one private replay WAV.
- one private-pipe Supertonic worker that validates and loads the pinned model
  once, then remains only as a child of the visible application;
- automatic one-shot synthesis fallback when warm preload was unavailable
  before a turn began.
- a separately pinned `base.en` Voice Presence default, leaving Music Studio's
  `small.en` vocal-analysis model unchanged.
- an interface-scoped local inference policy that disables hidden reasoning for
  ordinary Voice Presence conversation and caps it at 384 output tokens;
- explicit spoken deliberation phrases retain the selected model's normal
  reasoning path, while Dashboard text requests remain unchanged.

Warm streaming transcription and incremental sentence playback remain the next
A4 implementation slice. The verifier reports that explicitly rather than
claiming completion.

## Files changed

- `config/voice_presence_models.json`
- `lib/soul_core/voice_presence_turn_policy.rb`
- `lib/soul_core/voice_conversation_inference_policy.rb`
- `lib/soul_core/application_chat_service.rb`
- `lib/soul_core/conversation_runtime.rb`
- `scripts/soul-voice-presence-worker.py`
- `scripts/soul-voice-presence-bridge`
- `scripts/soul-voice-presence-app.py`
- `scripts/soul-voice-synthesis-worker.py`
- Voice Presence briefs, guide, deterministic verifiers, and this review.

## Required verification

```bash
ruby scripts/verify-voice-presence-a2.rb
ruby scripts/verify-voice-presence-a3.rb
ruby scripts/verify-voice-presence-a4-local-latency.rb
python -m py_compile scripts/soul-voice-presence-worker.py scripts/soul-voice-presence-app.py
python -m py_compile scripts/soul-voice-synthesis-worker.py
ruby -c scripts/soul-voice-presence-bridge
git diff --check
```

## Local timing evidence

One synthetic five-second English utterance was run through the exact installed
CPU paths without retaining the WAV. `small.en` took 1.74 seconds in direct
inference; `base.en` took 0.56 seconds and returned the same words. The complete
`base.en` transcription service, including private normalization, probing, and
integrity checks, took 1.23 seconds. The warm Supertonic worker loaded once in
0.50 seconds and then synthesized a 2.44-second response in 0.64 seconds.

These are controlled local measurements, not a substitute for microphone,
room-noise, conversational-model, or skill-routing review.

The active Soul-Lite Core Qwen3 8B path was also measured with the same small-
talk prompt. Default thinking took 6.28 seconds and generated 168 completion
tokens, including 671 characters of hidden reasoning. Explicitly disabling
thinking took 0.83 seconds and generated 12 completion tokens. Against the
full current 1,986-token Soul conversation context, the reviewed no-thinking
request took 2.72 seconds with a warm prompt cache and 7.33 seconds with a
deliberately cold prompt cache, compared with the prior live model latency of
17.35 seconds. These provider-only results do not include capture, STT, or TTS.

The first post-change live Voice Presence turn used the same `How are you
today?` prompt and returned the same visible response class in 4.78 seconds of
provider time with 30 completion tokens, down from 17.35 seconds and 275
completion tokens. Transcript submission through ready audio was approximately
7.4 seconds instead of 20.4 seconds. This proves the interface-scoped policy in
the real voice path; the remaining wake, explicit-deliberation, exact-replay,
and close-cleanup checks stay open for Operator review.

Subsequent live review found two candidate defects. The 0.65-second endpoint
could commit a turn during a natural pause, so the bounded endpoint is now 0.95
seconds. Wake attempts remained unreliable for two speakers, so the reviewed
calibration candidate moved to 3.5 / 0.15; false-wake review remains required.
The same review also proved that `What is a computer?` never reached Qwen: the
broad Instant Answer router intercepted it and the lookup miss failed closed.
Stable general-knowledge misses now fall back explicitly to the selected local
model, while current or source-dependent requests retain research routing.

## Privacy, authority, and lifecycle

- Latency evidence is in memory and contains no transcript or audio.
- The latest response WAV is request-private, mode-0700-directory scoped, and
  exists only for exact replay while the visible application remains open.
- Repeat grants no authority and performs no skill, Core, generation,
  publication, privileged, or destructive action.
- Ordinary Voice Presence no-thinking changes inference cost only. Explicit
  deliberation retains normal reasoning, and Dashboard requests are unchanged.
- No daemon, service, scheduler, network listener, cloud provider, or hidden
  microphone path was added.
- The warm synthesis child reads only private stdin requests and is terminated
  on pause, restart, or close.
- Lifecycle states remain existing complete, awaiting-input, failed, canceled,
  paused, listening, and follow-up paths.
- Risk: visible local microphone application with bounded session audio.

## Human review checklist

- [ ] Restart Voice Presence after installing the exact wake manifest update.
- [ ] Say `Hey Soul` naturally twenty times and record successful first tries.
- [ ] Leave ordinary music/conversation playing long enough to detect obvious
      false wakes.
- [ ] Compare displayed STT, Soul, TTS, and first-audio timings across three
      conversational and three deterministic-skill turns.
- [ ] Confirm an ordinary spoken small-talk turn reports materially lower Soul
      time than the previous 17.35-second Qwen turn.
- [ ] Say `think carefully about this` and confirm the model retains its normal
      slower reasoning path rather than silently applying the fast policy.
- [ ] Say `repeat that please` and confirm byte-identical immediate replay.
- [ ] Say `rephrase that` and confirm Soul creates a new response.
- [ ] Close Presence and confirm no response WAV or voice child remains.
