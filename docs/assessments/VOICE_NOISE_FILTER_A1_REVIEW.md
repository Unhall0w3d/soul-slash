# Voice Noise Filter A1 Review

## Candidate summary

This slice turns the installed `noise-suppression-for-voice` RNNoise LADSPA
plugin into one system-wide mono PipeWire virtual microphone. The generated
filter is bound to the exact raw source shown in the plan and becomes the user
default only after successful activation.

The filter is available to Soul, browsers, Discord, Steam, Webex, and other
PipeWire/Pulse clients. It is not a Soul-only capture path.
Its virtual output is normalized to 100% so browser automatic gain does not
spend the beginning of a short recording compensating for persisted virtual
source attenuation.

## Files changed

- `scripts/soul-voice-noise-filter`
- `scripts/verify-voice-noise-filter-a1.rb`
- `docs/soul/VOICE_NOISE_FILTER_A1_BRIEF.md`
- `docs/guides/VOICE_INPUT.md`
- `Makefile`

## Verification

```text
ruby -c scripts/soul-voice-noise-filter: PASS
ruby scripts/verify-voice-noise-filter-a1.rb: PASS
live PipeWire activation and default-source validation: PASS
```

The deterministic test verifies a read-only digest plan, exact confirmation,
mode-0600 installation, mono RNNoise graph, reviewed source binding, and
rollback source. It suppresses the live audio restart in its fixture.

## Lifecycle and risk

```text
new service/daemon/listener/scheduler: none
persistent state: one user PipeWire configuration
audio retained or transmitted: no
memory keys: none
lifecycle: complete, failed, canceled, blocked_for_human_review
risk: brief interruption of existing user audio during activation
```

## Human review checklist

- [ ] Confirm the virtual source appears.
- [ ] Confirm it is the default input.
- [ ] Confirm voice remains intelligible with music playing.
- [ ] Compare background-music rejection in Soul and Discord.
- [ ] Confirm no echo, clipping, or excessive gating.
