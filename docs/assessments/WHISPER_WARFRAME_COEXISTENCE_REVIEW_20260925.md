# Whisper and Voice Presence beside Warframe — September 25, 2026

Lifecycle: complete. The supervised session passed and the repository owner
approved merge on September 25. Deployment and cold-boot qualification remain
separate. The ordinary voice route remains AMD.

## Scope and implementation

The Operator authorized Whisper transcription while Warframe occupies AMD.
An initial proposed AMD admission exception was rejected by automatic approval
review because it bypassed the existing foreign-allocation and compute checks.
That patch was not applied. Instead, a session-only
`SOUL_WHISPER_GPU_BACKEND=cuda` choice selects the pinned GTX 1070 adapter and
its existing bounded NVIDIA handoff. Invalid values refuse; no CPU fallback
was added. The CUDA handoff now applies the same selected-Core check as AMD,
including a fresh check under the model-control lock. It does not stop or
reconfigure Warframe.

Changed paths for this slice:

- `lib/soul_core/routed_voice_transcription_service.rb`
- `lib/soul_core/cuda_whisper_runtime_handoff.rb`
- `scripts/verify-routed-voice-transcription.rb`
- `scripts/verify-cuda-whisper-routing.rb`
- `docs/guides/VOICE_PRESENCE.md`

The acceptance run also exposed a metadata-only memory write from default
chat-context construction. The read path now opens the shared memory ledger
with `create: false`; a focused verifier checks that a default chat context
does not change its bytes or modification time. Changed paths:

- `lib/soul_core/conversation_context_builder.rb`
- `scripts/verify-semantic-memory-chat-context-a3.rb`

## Deterministic checks

`verify-cuda-whisper-routing.rb`,
`verify-routed-voice-transcription.rb`,
`verify-whisper-runtime-handoff.rb`,
`verify-cuda-voice-transcription.rb`,
`verify-semantic-memory-chat-context-a3.rb`, and
`verify-conversational-safeguard-fidelity.rb` all passed. A temporary fixture
reproduced the memory-ledger timestamp change before the fix and preserved the
timestamp after it. `git diff --check` passed.

The CUDA route status identified the pinned release
`whisper-v1.9.1-cuda-sm61-20260905`, large-v3-turbo, and the reviewed GTX
1070 UUID. The first live retained-audio call refused before work because
Qwen's active service had no NVIDIA allocation. There was no pending receipt.
The current boot journal showed CUDA initialization failure at service startup,
and Qwen was running on CPU. A bounded restart under Soul's model-control lock
checked the selected Core, idle slots, empty leases, zero active work, and free
NVIDIA compute ownership. Qwen changed PID 1509 to 477888, returned healthy,
and had 5,278 MiB on the expected UUID; the selected `amd-free` Core was
unchanged.

The retained-audio call then completed in 17.55 seconds with verified CUDA
execution and a transcript. The handoff released Qwen in 242 ms, spent 3,741 ms
in recognition, restored Qwen in 7,720 ms, and returned a
`restored: true` receipt. A later GPU check showed the Qwen service again
allocated 5,296 MiB on the reviewed UUID. No pending Whisper receipt remained.

## Attended microphone result

A visible temporary Voice Presence window inherited the CUDA session setting
and reached `listening`. The Operator completed the three-part spoken sequence.
The canonical Voice Presence chat recorded:

1. A Downloads-to-Trash safeguard question. Soul answered that it requires
   selection and final confirmation, and that an existing original path blocks
   restore even after confirmation.
2. The original-path follow-up, captured during the natural follow-up window
   without another wake phrase. Soul said confirmation and `--execute` cannot
   override the existing-path refusal.
3. An invented backup-enclosure-color question after wake listening resumed.
   Soul said it did not know the enclosure color.

The temporary window and microphone workers were closed after the test;
Warframe remained running. The seven-file memory baseline showed identical
bytes and SHA-256 for all files. One ledger modification time changed during
chat context construction, which prompted the read-only fix above. The
approved-memory index, projection generation and reconciliation files, and
lifecycle journals retained their baseline fingerprints. Ordinary text turns
remain in the canonical Voice Presence chat as documented.

## Remaining risk and review

Qwen's cold-boot CUDA discovery failure is still unresolved. It can leave an
active CPU-backed service, which the NVIDIA handoff correctly refuses. The
bounded one-time restart repaired current placement only. A durable startup
readiness repair needs separate design and human review. CUDA transcription
also has a measurable Qwen release/reload delay per spoken turn; this trial
shows working behavior, not a latency target or benchmark.

Human review should assess the explicit CUDA route, lock-time Core policy,
metadata-only memory fix, and whether the measured voice delay is acceptable.
No merge, release, default-route change, unit edit, or reboot was performed.

## Human review outcome

Outcome: approved for merge by the repository owner in the current
conversation. This approves the explicit CUDA route and memory read-path fix
reviewed here. The boot-time Qwen readiness repair is a separate change.
