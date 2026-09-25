# Soul conversation and Voice Presence fidelity A1

Lifecycle: complete. Candidate implementation, unattended qualification, and
the September 25 attended wake-word and follow-up sequence passed. The
Operator approved merge on September 25; deployment remains a separate
decision. Risk: safety-related conversational claims and interpreted speech.

## Implementation summary

- Soul's Downloads restore-policy questions now take a narrow deterministic
  explanation path. It reads the actual preflight contract: an existing original
  path blocks restore and final confirmation cannot waive that refusal. This
  path does not execute a restore or intercept a restore action.
- Voice Presence resolves only direct sentence-opening “Sol, …”,
  “Sole, …”, or “Seoul, …” requests to the assistant name Soul. It displays
  the raw ASR text and labels the interpretation. Generic transcription and
  ordinary statements about Seoul remain unchanged.
- The Voice Presence guide now describes the AMD Whisper handoff and this
  interpretation. No restore implementation, GPU admission threshold, memory
  policy, Core selection, or persistent voice service changed.

## Changed paths

`lib/soul_core/downloads_restore_policy_answer.rb`,
`lib/soul_core/conversation_runtime.rb`,
`lib/soul_core/conversation_orchestration_contract.rb`,
`lib/soul_core/voice_presence_address_resolver.rb`,
`scripts/soul-voice-presence-bridge`,
`scripts/soul-voice-presence-app.py`,
`scripts/verify-downloads-restore-policy-answer.rb`,
`scripts/verify-voice-presence-address-context.rb`, and
`docs/guides/VOICE_PRESENCE.md`.

## Commands and deterministic results

- `rbenv exec ruby scripts/verify-downloads-restore-policy-answer.rb`: PASS,
  including action exclusions, unrelated Trash questions, policy text, and
  runtime routing in a temporary chat.
- `rbenv exec ruby scripts/verify-voice-presence-address-context.rb`: PASS,
  including genuine Seoul geography and visible raw transcript.
- `rbenv exec ruby scripts/verify-conversational-safeguard-fidelity.rb`:
  PASS; `verify-chat-intent-and-interaction-boundary.rb`: 35 PASS.
- `verify-voice-presence-a4-local-latency.rb`: exit 0;
  `verify-routed-voice-transcription.rb`: PASS.
- `verify-downloads-move-to-trash-phase62.rb --functional-only`: PASS after
  running with Soul's runtime write access. Its repository-curation gate was
  explicitly not checked. The sandbox-only first attempt failed on read-only
  `Soul/identity/interests.jsonl`, not on a restore assertion.

## Local behavior and held checks

A live Voice Presence chat request first omitted the no-overwrite safeguard.
Its follow-up incorrectly said a collision was blocked **unless** confirmed
with `--execute`. After this repair, the same request pair answered that the
existing original path blocks restore even after confirmation. An invented
backup-drive-enclosure-color question received an honest unknown answer. These
were synthetic text turns through the real local chat route; no file restore
was invoked.

With Elden Ring active, the AMD handoff refused a 5 GiB foreign Wine allocation
before transcription. After the Operator closed the game, retained address and
geography WAVs transcribed successfully with verified handoff restoration:
“Sol, what is the difference between memory and storage?” and
“Seoul is the capital of South Korea.” The full bridge preserved the first
raw transcript, interpreted the direct address as Soul, completed its chat
turn, and emitted a warm speech request. It did not exercise microphone
capture or speaker playback.

The visible Voice Presence window was opened for the attended check and reached
`listening`. It recorded no spoken turn during this pass, so the exact app
process was stopped; its microphone and worker processes exited and its status
marker disappeared. Confirm the wake phrase, spoken safeguard, five-second
follow-up, actual playback/pronunciation, and unknown-fact abstention in a new
attended session. The contextual resolver does not fix every
name misrecognition; it deliberately has a narrow address shape.

## Memory, lifecycle, and review

No explicit memory write, forget, projection rebuild, or restore mutation was
requested. Ordinary synthetic chat turns were recorded through canonical Chat.
The policy replies completed deterministically; the GPU guard failed safely
while the game held VRAM; subsequent handoffs completed and restored.

Human review: inspect the narrow routing and speech interpretation, confirm
the attended sequence, and decide merge/release readiness. Do not treat this
packet or local model behavior as approval of protected safeguards.

## September 25 attended result

With Warframe left running on AMD, a supervised Voice Presence session used the
explicit CUDA route described in
`WHISPER_WARFRAME_COEXISTENCE_REVIEW_20260925.md`. The visible window captured
and answered the spoken Downloads safeguard question, the natural follow-up
within its five-second window, and the unknown backup-enclosure-color question.
Both restore answers preserved the existing-path refusal; the invented fact was
not asserted. The temporary microphone window was closed after the test.
Canonical chat text was retained as expected, and no approved memory or
projection content changed. The shared memory ledger's timestamp-only touch
was reproduced and repaired in the read-only context builder, with a regression
check. This attended result qualifies the flow but does not approve merge or
release.

## Human review outcome — September 25

Outcome: approved for merge by the repository owner in the current conversation.
The approval covers the reviewed Voice Presence fidelity and related guarded
Whisper route changes. It does not authorize an unreviewed camera deployment
or a reboot. The Qwen cold-start defect is being handled separately.
