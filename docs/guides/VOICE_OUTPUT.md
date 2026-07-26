# Voice Output

Soul can speak an eligible assistant message through an explicit control in
dashboard Chat. Speech is local and disposable. **Responsive** delivery uses
Supertonic on CPU; **Expressive** delivery uses Chatterbox Original on NVIDIA
when it is safely available and falls back to CPU without interrupting active
work. Neither engine remains resident afterward.

## Requirements

- `uv` installed through the host operating system.
- An installed Python 3.12 runtime visible to `uv`.
- The pinned Supertonic 3 package environment and model assets.
- For optional Expressive delivery, the pinned Chatterbox environment and
  roughly 3.2 GB of model assets.
- A current browser capable of WAV playback.

Inspect the local state:

```bash
make voice-synthesis-check
```

For a fresh clone, review and execute the exact install:

```bash
make voice-synthesis-plan
make voice-synthesis-install \
  EXPECTED_DIGEST=<digest-from-plan> \
  CONFIRM=INSTALL_SOUL_VOICE_SYNTHESIS
```

This creates an isolated environment under
`~/.local/share/soul/voice/runtime`, downloads the model revision pinned by
the manifest, verifies every inference and voice-profile digest, and exits. It
does not install a service or start a speech server.

Install the optional expressive engine through its separate reviewed gate:

```bash
make voice-expressive-plan
make voice-expressive-install \
  EXPECTED_DIGEST=<digest-from-plan> \
  CONFIRM=INSTALL_SOUL_EXPRESSIVE_VOICE
```

The public defaults may be overridden with `VOICE_EXPRESSIVE_ROOT`,
`VOICE_EXPRESSIVE_MANIFEST`, and `VOICE_EXPRESSIVE_REQUIREMENTS` in
`config/model_overrides.mk`. Runtime paths may be overridden in ignored
`.env` with `SOUL_VOICE_EXPRESSIVE_ROOT` and
`SOUL_VOICE_EXPRESSIVE_MANIFEST`.

## Operator flow

1. Open a Chat transmission containing a Soul response.
2. Click **Speak** beneath an eligible assistant message.
3. Choose **Responsive** for low latency or **Expressive** for higher quality,
   then wait while the live status reports preparation, rendering, and any
   guarded Core restoration.
4. Playback begins in the browser.
5. Click **Stop**, change transmissions, leave Chat, or log out to end
   playback and release its browser audio object.

Only one synthesis and one playback are permitted at a time. Typed Chat never
automatically reads a response; a completed push-to-talk action speaks exactly
its resulting reply. JSON payloads, oversized responses, and
messages without eligible prose do not expose or pass the speech boundary.
Markdown code blocks and raw URLs are excluded from synthesized prose.

## Voice selection

The reviewed runtime includes feminine profiles `F1` through `F5` and
masculine profiles `M1` through `M5`. Render the matched comparison set with:

```bash
make voice-synthesis-audition
```

The Chat composer exposes **Voice** and **Delivery** selectors. The current curated
pair is feminine `F3` and provisional masculine `M3`; changing it affects the
next Speak request immediately without a dashboard restart, resident engine,
or Core swap. The browser retains this non-sensitive preference locally.

The public default is `F3`. These are local voice profiles, not clones or
imitations of proprietary hosted voices.

Configure a reviewed preference in ignored `.env`:

```dotenv
SOUL_VOICE_SYNTHESIS_VOICE=F3
SOUL_VOICE_SYNTHESIS_SPEED=1.0
```

Portable deployments may also override:

```dotenv
SOUL_VOICE_SYNTHESIS_ROOT=/absolute/user-local/runtime/root
SOUL_VOICE_SYNTHESIS_MANIFEST=/absolute/path/to/manifest.json
```

The configured default may be `F1`–`F5` or `M1`–`M5`. Custom manifests must
preserve the exact runtime identity, model revision, available voice names,
and SHA-256 for every required model asset.

## Retention and resource behavior

```text
synthesis text file: deleted before request return
synthesized WAV file: deleted before request return
HTTP WAV body: private, no-store
browser audio object: revoked at stop/end/navigation/logout
resident TTS process: none
GPU allocation: none for Responsive; temporary and released for Expressive
memory update: none
```

Responsive synthesis has a 120-second timeout and a 2,000-character ceiling.
Expressive synthesis has a 240-second timeout and 600-character ceiling. If
the NVIDIA Core is serving idle chat, Soul releases it under the same runtime
control lock, renders, restores it, and verifies health before returning
audio. Active work is never interrupted; an occupied specialist resource
causes CPU fallback. A failed or timed-out request stops safely without
changing the conversation or invoking any skill.

## Present boundary

Voice output remains Operator-invoked, either through explicit **Speak** or one
completed push-to-talk round trip. It does not add general automatic narration,
streaming speech, interruption-aware turn taking, a wake word, global
push-to-talk, headless playback, or an always-available voice session.
