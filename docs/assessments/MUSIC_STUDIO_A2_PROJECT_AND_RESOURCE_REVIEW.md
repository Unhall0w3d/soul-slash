# Music Studio A2 Project and Resource Review

Status: candidate-complete; human review required

Date: 2026-07-17

## What was implemented

- Added strict project and generation JSON schemas.
- Added owner-private, ignored `Soul/music/projects/` storage with generated
  IDs, bounded fields, rights status, fixed duration/seed inputs, atomic JSON,
  and symlink/path protections.
- Added CLI-only create, list, inspect, generation preview/execute, resource
  inventory, and cancellation preview/execute operations.
- Added a read-only four-lane resource projection for AMD conversation, NVIDIA
  fallback, NVIDIA music, and CPU audio.
- Added one-owner `nvidia-music` leases with PID/start identity, child process
  group attachment, TTL cleanup, exact cancel digests, bounded TERM/KILL, and
  no queue or automatic preemption.
- Registered Music work in Soul's existing model-runtime lease store and made
  unloaded-profile loads honor active work, preventing NVIDIA fallback from
  loading across a Music run.
- Added one strict-offline, foreground ACE-Step invocation from validated
  project inputs. The runtime rechecks the pinned source revision, exact A1
  overlay markers, all checkpoint sizes and SHA-256 digests, resource state,
  and the preview digest before spawning.
- Added 48 kHz stereo FLAC validation and bounded LAME V2 MP3 derivation. Both
  artifacts receive size, SHA-256, codec, duration, sample rate, channel, and
  lineage receipts before atomic candidate publication.
- Added public Make targets without changing general setup or adding a
  dashboard, service, listener, worker, watcher, timer, or scheduler.

## Files changed

- `.gitignore`
- `Makefile`
- `config/music_project_schema.json`
- `config/music_generation_schema.json`
- `lib/soul_core/music_project_store.rb`
- `lib/soul_core/music_resource_coordinator.rb`
- `lib/soul_core/music_generation_service.rb`
- `lib/soul_core/model_runtime_control_service.rb`
- `scripts/soul-music-studio`
- `scripts/verify-music-studio-a2.rb`
- `scripts/verify-model-runtime-portability.rb`
- Music A2 brief, architecture, roadmap/state, and this review artifact.

## Commands run

- Ruby syntax checks for every new Ruby file.
- `ruby scripts/verify-music-studio-a2.rb`
- `ruby scripts/verify-model-runtime-portability.rb`
- Existing profile deployment, switching, selected-startup, and identity
  migration verifiers.
- Live `make music-resources` read-only inventory.
- `git diff --check`

## Deterministic test results

Pass. The A2 verifier covers:

- missing rights, unknown fields, and write-free rejection;
- private permissions, generated IDs, typed records, and atomic publication;
- symlinked storage rejection;
- read-only preview, exact confirmation, and changed-state boundaries;
- strict-offline argument arrays and one model invocation;
- linked FLAC/MP3 receipts and master digest lineage;
- quarantined/published candidate visibility;
- live-lane inventory shape and active fallback conflicts;
- one-owner leases and cross-runtime lease visibility/removal;
- exact recorded-process-group cancellation; and
- absence of a listener, service, daemon, queue, or polling worker.

All relevant existing model-runtime verifiers pass after the cross-runtime load
guard was added.

## Live read-only result

The bounded host inventory reported:

```text
AMD conversation health: ok
NVIDIA fallback: inactive
NVIDIA music GPU: available
NVIDIA free memory: 8,095 MiB
NVIDIA compute processes: 0
Active Music lease: none
Can acquire nvidia-music: yes
```

No project or audio candidate was created and no live generation or cancellation
was executed. Those remain separate human gates.

## Local LLM eval results

Not run. Project schemas, path protections, lease identity, process signaling,
audio receipts, and confirmation behavior are deterministic control-plane
properties, not language-model behavior.

## Known weaknesses

- The real A2 project-input path and FLAC-to-MP3 chain have not yet run against
  the live ACE-Step environment. Deterministic tests use bounded fake process
  and media adapters.
- Cancellation is deterministically validated against exact fake process
  identities and signals but has not interrupted a live model generation.
- The CLI verifies all 7.71 GB of checkpoint hashes before every generation.
  This is conservative and measurable but adds startup latency.
- MP3 defaults to LAME V2. Browser playback and the exact size/quality tradeoff
  still require a live candidate review.
- Failed or canceled candidates remain in hidden `.candidate.partial`
  quarantine directories with bounded receipts. A later reviewed cleanup
  operation is needed; A2 never deletes them automatically.
- Project editing, dashboard integration, repaint, extend, stems, references,
  research, and export remain later phases.

## Memory keys added or used

None. Music projects are task artifacts in ignored project storage. No private
memory store or shared-memory promotion was added.

## Task lifecycle states touched

- `complete`: project creation/list/inspection and resource inventory.
- `awaiting_input`: missing or invalid fields and identifiers.
- `failed`: bounded process, transcode, or media-validation failure.
- `canceled`: timeout or exact process-group cancellation.
- `blocked_for_human_review`: previews, conflicts, integrity failures, and
  successfully generated candidates awaiting listening review.

Every operation terminates. Generation remains in the foreground and owns one
bounded process group until return or a separately confirmed cancellation.

## Risk classification

- Project and candidate local writes: Class 2.
- Read-only hardware/service inventory: Class 1.
- Foreground GPU generation and audio transcoding: Class 2.
- Exact recorded process-group cancellation: Class 3 destructive-to-owned-task.

## Human review checklist

- [ ] Confirm the A2 project fields and 10–180 second duration bound.
- [ ] Confirm FLAC master plus LAME V2 MP3 proxy behavior.
- [ ] Confirm NVIDIA music/fallback exclusion and AMD coexistence.
- [ ] Confirm exact preview, digest, generation, and cancellation gates.
- [ ] Confirm failed output quarantine without automatic deletion.
- [ ] Approve one live Soul-native project generation.
- [ ] Review both live artifacts and their receipt.
- [ ] Approve, revise, or reject Music A2 before Music A3 dashboard work.
