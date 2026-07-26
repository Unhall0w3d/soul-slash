# Weather Speech and Fresh Screen A1 Brief

## Human direction

Weather spoken through Dashboard Chat or Voice Presence is too fast, lacks
useful pauses, and pronounces display abbreviations such as `°F` as letters or
phonemes rather than "degrees Fahrenheit."

The observed Voice Presence exchange also exposed two adjacent deterministic
routing failures: an affirmative weather follow-up transcribed as `- Yeah.`
fell into the general model, and the natural request `What am I looking at?`
reused an old conversational screen description instead of capturing the
current active window.

## Candidate scope

- Preserve the compact weather text shown in Chat.
- Derive speech context from deterministic `weather.report` orchestration
  metadata rather than asking the language model to rewrite evidence.
- Add one bounded speech-presentation layer before local synthesis.
- Expand temperature, speed, percentage, air-quality, and cardinal-direction
  abbreviations only for weather speech.
- Turn compact comma-separated weather data and detailed forecast rows into
  measured spoken sentences.
- Use a slightly slower responsive synthesis speed for weather reports.
- Apply the same behavior to explicit Dashboard Speak, push-to-talk round
  trips, and Voice Presence.
- Unknown speech contexts fail before synthesis.
- Accept a harmless speech-to-text bullet prefix only when evaluating an
  affirmative follow-up to retained weather evidence.
- Route `What am I looking at?` and its close natural variant to one fresh
  active-window capture.
- Mark voice-requested screen analysis with a deterministic fresh-screen
  response policy. Remove literal UI/title claim lines that quote or emphasize
  names absent from the fresh compositor/OCR evidence.

## Explicitly excluded

- Changing displayed weather facts or weather-provider behavior.
- Model-authored paraphrasing of weather evidence.
- SSML, a resident TTS process, streaming narration, or automatic playback
  outside the already reviewed voice paths.
- Global speaking-rate changes for ordinary conversation.
- New services, listeners, watchers, schedulers, or background loops.
- General fuzzy screen routing, periodic capture, conversation-history vision,
  or treating OCR as authorization.

## Lifecycle and authority

Speech remains one bounded foreground request. Presentation text and WAV
output remain request-private and are removed at terminal return. Speech
presentation cannot invoke a skill, change a Core, approve an action, or alter
the retained conversation. Fresh-screen understanding remains one ephemeral
capture and one bounded local inference. The claim guard may remove an
unsupported literal assertion; it cannot add evidence or perform control.
