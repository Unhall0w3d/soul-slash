# Music Instrumental Section Scripts Brief

## Objective

Allow an instrumental Music Studio project to send a bounded temporal section script to ACE-Step without implying sung lyrics.

## Contract

- Instrumental projects may leave the Lyrics and section markers field empty.
- A non-empty instrumental script may contain only bracketed section markers, one marker per non-empty line.
- Free prose, lyric lines, and other vocalizable text remain invalid in instrumental mode.
- The marker-only script is preserved in the exact generation input and digest.
- Vocal projects retain their existing lyric behavior.
- Sound and Structure remains the overall sonic portrait. BPM, key, and dominant time signature remain dedicated fields.
- ACE-Step still receives one dominant time-signature value. Section markers may request bounded transitions to other meters, but do not claim simultaneous polymeter support.
- No generation, service, queue, watcher, or background process is started by this change.

## Lifecycle and risk

Malformed instrumental prose terminates as `awaiting_input`. Valid project creation terminates `complete`; generation remains separately `blocked_for_human_review` behind its exact gate.

Risk classification: low. This changes text conditioning for explicitly instrumental projects and may affect musical output, but does not weaken authorization or resource controls.
