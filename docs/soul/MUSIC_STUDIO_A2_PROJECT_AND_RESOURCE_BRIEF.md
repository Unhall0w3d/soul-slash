# Music Studio A2 Project and Resource Boundary Brief

Status: authorized by the repository owner after approval of Music A1

Authorization date: 2026-07-17

## Outcome

Add the first Soul-native, CLI-only Music Studio vertical slice: deterministic
private projects, explicit generation previews, one bounded foreground
ACE-Step invocation, linked FLAC/MP3 artifacts, read-only resource inventory,
and exact NVIDIA music leases with cancellation. Do not add the dashboard tab.

## Authorized local artifacts

Soul may create owner-private project records under the ignored
`Soul/music/projects/` root and transient coordination records beneath the
already ignored `Soul/runtime/music/` root. Generated audio, logs, inputs,
reviews, and exports remain local and untracked.

The previously approved, pinned ACE-Step environment and checkpoints under the
operator's configured `MUSIC_ROOT` may be invoked. A2 may apply one exact,
versioned overlay to the pinned profiler so it can read a validated absolute
project input file. It may not download, update, or start a server.

## Project contract

- Project IDs and candidate IDs are generated identifiers, never user paths.
- A project records title, intent, target duration, vocal mode, rights status,
  musical caption, lyrics, BPM, key, meter, language, seed, and timestamps.
- Creation rejects unknown fields, unsafe encodings, invalid numeric bounds,
  missing rights status, symlinked roots, collisions, and oversized input.
- Project writes use owner-only directories and atomic JSON replacement.
- Projects are task artifacts, not a private memory system.

## Generation contract

The lifecycle is:

```text
inspect resources
→ preview exact project/input/model/output scope
→ blocked_for_human_review
→ exact START_MUSIC_GENERATION confirmation and digest
→ acquire nvidia-music lease
→ one allowlisted foreground process group
→ bounded FLAC validation
→ bounded MP3 derivation and validation
→ atomically publish candidate receipt
→ release lease and model process
→ blocked_for_human_review
```

New project generation durations are the supported 30-, 90-, and 180-second
presets, batch size is one, the seed is explicit, and wall timeout is duration
plus 180 seconds. Older bounded 10–180-second project records remain readable
for compatibility but cannot be newly created through Soul. The operation uses the
pinned A1 model profile with strict offline mode, float32 Pascal compatibility,
CPU offload, and eight diffusion steps. It never performs a second model run
for MP3.

The canonical artifact is 48 kHz stereo FLAC. A bounded FFmpeg invocation
derives a LAME V2 MP3 proxy from that exact FLAC. Both files must be non-empty,
have the expected duration within one second, and receive SHA-256 receipts. A
valid FLAC is preserved visibly if MP3 encoding fails, but the candidate does
not become complete.

## Resource and cancellation contract

- Inventory is read-only and bounded. It reports the AMD conversation health,
  NVIDIA fallback user-unit state, NVIDIA GPU availability, and active named
  music lease without starting or stopping anything.
- `nvidia-fallback` and `nvidia-music` conflict; AMD conversation may coexist.
- Lease acquisition rechecks the fallback service, NVIDIA compute processes,
  lease integrity, project digest, and output nonexistence under one file lock.
- A lease records the foreground owner identity and, once spawned, the exact
  child PID, process start identity, and process group.
- Cancel preview is read-only. Exact `CANCEL_MUSIC_GENERATION` confirmation and
  digest may signal only the recorded, revalidated process group: TERM, a
  bounded wait, then KILL if necessary.
- Stale leases are removed only during bounded foreground inspection. No queue,
  watcher, polling service, retry loop, auto-preemption, or background worker is
  introduced.

## Failure and terminal states

Every invocation returns one of `complete`, `failed`, `awaiting_input`,
`canceled`, or `blocked_for_human_review`. Partial output remains quarantined
and is never listed as a valid candidate. Logs are bounded. A returned command
leaves no child process running except while a separately invoked foreground
generation command still owns its verified lease.

## Excluded

- Dashboard or HTTP changes.
- Persistent model workers, APIs, listeners, services, schedulers, queues, or
  automatic loading/unloading.
- Repaint, extend, stems, reference audio, publishing, voice cloning, training,
  downloads, or web research.
- Editing an existing project or overwriting an existing candidate.
- Promoting preferences into shared memory.

## Completion

A2 is candidate-complete when deterministic tests cover project validation,
path protections, preview/digest gates, resource conflicts, lease integrity,
cancellation identity, bounded generation outcomes, dual-artifact receipts,
and cleanup; the CLI remains foreground-only; and the human review artifact is
complete. A live project generation is a separate human gate after deterministic
candidate review.
