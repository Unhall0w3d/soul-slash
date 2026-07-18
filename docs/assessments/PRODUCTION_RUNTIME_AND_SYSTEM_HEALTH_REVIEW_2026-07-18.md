# Production Runtime and System Health Review

Date: 2026-07-18

Status: candidate complete; awaiting final Operator review

Risk class: Class 3 — bounded local model and GPU mutation

## Outcome

Soul's supported production topology is now:

| Core | Chat engine | Music engine | GPU ownership |
| --- | --- | --- | --- |
| Daily | Gemma 4 12B Instruct Q4_K_M through Ollama | unavailable | AMD chat; NVIDIA available for bounded specialists |
| Music | Qwen3 8B Q4_K_M through llama.cpp | ACE-Step 1.5 4B LM / 2B Turbo Q8_0 | NVIDIA chat; AMD foreground music |
| AMD-Free | Qwen3 8B Q4_K_M through llama.cpp | unavailable | NVIDIA chat; AMD reserved for the Operator |

Ministral 3 14B is retired from the supported profile inventory, startup
selection, Core definitions, dashboard identity, and current documentation.
Its inactive legacy service and weights were not destructively removed.

The accepted ACE-Step Vulkan lane is integrated into the normal Music Studio
generation and revision path. It is a bounded foreground operation and creates
no service, listener, watcher, schedule, or resident model process.

## What was implemented

- Added a revision- and digest-pinned production Vulkan manifest for
  `acestep.cpp`, GGML, and all four model artifacts.
- Added a production generation backend with exact installation validation,
  bounded subprocess timeouts, cancellation, and explicit terminal states.
- Added pre-synthesis audio-code collapse detection. One approved operation may
  try at most three deterministic LM seeds. A third consecutive collapse stops
  as `blocked_for_human_review`; it does not synthesize or continue unattended.
- Pinned VAE chunking to 256 after the 1024-frame default caused an AMD compute
  ring timeout during qualification.
- Added 30-, 90-, and 180-second Music Core support. Successful output is a
  48 kHz stereo FLAC master plus MP3 listening copy. The selected WAV and LM
  attempt workspaces are removed only after successful conversion.
- Made the resource coordinator Core-aware. It reports Qwen on NVIDIA and
  ACE-Step on AMD Vulkan in Music Core without mislabeling NVIDIA telemetry as
  AMD state.
- Promoted Gemma to the default AMD profile and migrated the live Daily Core.
- Updated dashboard runtime, Core, and music identity text, including revision
  progress wording that no longer assumes NVIDIA generation.
- Replaced executable `.env` sourcing with a bounded literal key/value parser.
- Repaired temporary-directory leaks in music reference analysis verification.
- Made the runtime smoke test use a private temporary directory with cleanup and
  report the selected registry profile rather than a compatibility-era value.

## Live verification

- `soul-model-gemma.service`: active
- `llama-server.service`: inactive in Daily Core and available for Core switch
- legacy `soul-model-amd.service`: inactive and absent from supported profiles
- selected runtime: `amd-gemma`
- Gemma Ollama endpoint: healthy; exact local digest selected for login startup
- Gemma FAST response: `Soul FAST mode is online.`
- Dashboard: active; HTTP 200 after restart
- Live Music Core inventory: Qwen chat on NVIDIA, AMD Vulkan available, no
  conflicting lease; the production generation preview resolved to `amd-music`
- Final Core selection returned to Daily/Gemma after the Music Core check

## Commands and deterministic results

```text
ruby syntax check across repository Ruby files                         PASS
bash -n across repository shell scripts                               PASS
ruby scripts/verify-core-orchestration.rb                             PASS
ruby scripts/verify-gemma-core-dashboard.rb                           PASS
ruby scripts/verify-model-runtime-profile-switching.rb                PASS
ruby scripts/verify-model-runtime-selected-startup.rb                 PASS
ruby scripts/verify-ollama-model-runtime-deployment.rb                PASS
ruby scripts/verify-music-core-vulkan-feasibility.rb                  PASS
ruby scripts/verify-music-studio-a2.rb                                PASS
ruby scripts/verify-music-studio-a3.rb                                PASS
ruby scripts/verify-dashboard-click-approvals.rb                      PASS
ruby scripts/verify-phase12c-foreground-dashboard.rb                 PASS; human visual review boundary retained
make test-fast                                                        PASS
git diff --check                                                      PASS
```

The aggregate Phase 12C curation gate passed after staging, including all
Phase 11A–12B regressions. It terminates at the designed human visual-review
boundary rather than self-approving the dashboard.

## Local model evaluation

Gemma's live FAST-mode response and endpoint identity were validated. Music
quality was evaluated through the human listening pilots recorded in
`MUSIC_CORE_VULKAN_FEASIBILITY_REVIEW.md`. Local model output was not used to
authorize GPU mutation, safety behavior, promotion, or merge readiness.

## Data lifecycle and temporary storage

### Correctly bounded today

- Reference source audio and raw transcription use block-scoped temporary
  directories and are not retained after analysis; reviewed derived evidence is
  retained with provenance.
- Successful Vulkan generation removes the selected WAV, request input, and LM
  attempt directories after FLAC/MP3 publication.
- Project deletion inventories and removes project-owned candidates, audio,
  inputs, logs, transcription, reviews, and history. Finished exports are
  intentionally outside that scope.
- Artist-profile deletion inventories provenance, evidence, synthesis revisions,
  and approval records.
- Permanent conversation forget removes the chat, history, linked evidence, and
  shared-memory associations; ordinary clear remains archival by design.
- Production skill promotion closes its proposal and superseded Beta while
  retaining the registered production skill.

### Inventory requiring an explicit Operator cleanup decision

- Approximately 1.1–1.2 GB of disposable review/build material exists in
  `/tmp`, led by old ACE-Step/llama Vulkan review trees. Some directories contain
  useful qualification evidence, so they were not deleted implicitly.
- `~/.local/share/soul/music` is approximately 23 GB: roughly 15 GB for the old
  Python ACE-Step lane, 8.2 GB for the production native lane, 482 MB for
  transcription, and retained pilot runs. The recovered and accepted pilot
  audio lives among those runs and must not be swept blindly.
- Failed/collapsed generation evidence is intentionally quarantined with no
  current expiry. It needs a bounded inventory-and-discard operation rather
  than an unattended cleaner.
- `Soul/logs` contains 62 files (~492 KB), including 56 older than seven days.
  This is small now, but no explicit retention policy exists.
- The legacy Ministral service file and weights remain installed but inactive.
  Removal should be a separate previewed destructive action.

Recommended next slice: add a read-only Storage & Retention inventory followed
by digest-bound, category-specific cleanup previews. Never combine private
projects, accepted pilots, failed diagnostics, model weights, or exports into a
single indiscriminate cleanup action.

## Host review

- Host uptime is approximately one week; last boot was 2026-07-11.
- Running and installed CachyOS kernel are both `7.1.3-2` with matching headers.
- Pacman nevertheless logged a reboot recommendation after core-package updates
  on July 15 and July 17. Soul's reboot detector is correct. Reboot at an
  Operator-chosen stopping point after saving work; no emergency restart was
  required for this promotion.
- No failed system or user units were found.
- Root storage: approximately 1.9 TB total, 317 GB used, 1.6 TB free.
- Memory: 62 GiB total, about 40 GiB available during review; swap had 7.5 GiB
  in use. Recheck swap residency after reboot.
- AMD RX 6900 XT: RADV/Mesa 26.1.5. NVIDIA GTX 1070: driver 580.173.02, 8 GiB.
- `checkrebuild` reports the foreign `cuda-12.9` package. Pacman reports 24
  orphan candidates and 12 foreign packages. These are review inventories, not
  permission to remove packages.
- Caddy's automatic local-root trust installation could not use sudo. This does
  not prevent the existing LAN HTTPS path; clients still need manual trust or an
  accepted local warning.
- One Caddy incomplete ranged-audio response corresponds to client cancellation,
  not a server failure.
- Dashboard RSS had grown to about 525 MB (810 MB peak) before restart and fell
  to about 29 MB afterward. This warrants request-by-request observation before
  concluding there is a leak.
- The qualification-time AMD ring timeout recovered successfully. Subsequent
  256-frame pilots were healthy, but future kernel/Mesa/backend upgrades require
  another 30/90/180 qualification pass.

## Repository and code health

### Healthy properties

- Git object verification is clean; no repository garbage was found.
- Private runtime and music directories are ignored and permissions are
  restrictive.
- Ruby and shell syntax checks pass across the repository.
- Runtime mutation remains digest-bound and human-gated; music retry recovery
  stays within the already-approved candidate and never broadens authority.
- The Core abstraction now correctly separates chat ownership from specialist
  GPU ownership.

### Improvement opportunities

- `assets/dashboard/dashboard.js` is approximately 1,600 lines and contains
  many domain handlers. Split it by Chat, Music, Skills, Assessment, and shared
  transport/state modules before adding more large tabs.
- `ApplicationFacade` and `SkillStudioService` have accumulated broad dispatch
  responsibilities. Extract domain facades incrementally behind existing action
  contracts; avoid a wholesale rewrite.
- There are more than 150 deterministic verifier scripts and nearly 400 docs.
  Add a manifest-driven test runner and documentation index while preserving the
  existing focused verifiers as auditable units.
- `Soul/memory` currently mixes tracked seed/policy material with durable shared
  memory. Because this is a public repository, introduce an explicit migration
  that separates shipped defaults from ignored private user memory before more
  personal context accumulates. Do not silently move or erase current memory.
- Private music/runtime/proposal/reference state is intentionally outside Git and
  lacks one documented backup/export policy. Define an Operator-controlled local
  backup boundary distinct from source control.

## Current and future modality compatibility

### Current state

- Gemma's installed Ollama model advertises text completion, tools, thinking,
  and vision capabilities. Soul's current provider message contract is still
  text-only, so advertised vision is not yet an implemented or qualified image
  feature.
- Qwen3 fallback is currently integrated as a text chat/runtime model.
- Whisper.cpp `small.en` exists as a bounded CPU transcription backend for Music
  Studio. It starts for a task and exits, but it is not yet a general chat or
  microphone speech-input system.
- No production TTS output path exists.
- No continuous microphone, camera, or screen capture exists, which is the
  correct default boundary.

### Recommended architecture

1. Add an explicit attachment contract and private artifact lifecycle for images.
2. Add a provider capability registry so a qualified Gemma vision pilot can
   receive image parts without changing text-only Qwen behavior.
3. Implement screen understanding as a user-invoked, bounded screenshot skill;
   never silently capture or watch the desktop.
4. Generalize the bounded Whisper backend for explicit microphone/file input,
   with raw audio deleted by default after approved transcription.
5. Add TTS as a separate cancellable foreground specialist with explicit audio
   playback and retention controls.
6. Represent future specialists as independent leased runtime lanes. Do not
   overload the single selected chat-profile registry with vision, speech, and
   music process state.

The present Core and resource-coordinator design supports those additions: AMD
can host the Daily chat model or Music engine, while NVIDIA remains available
for bounded fit-to-task specialists. The missing work is primarily modality
contracts, artifact retention, and specialist registries—not another chat-model
migration.

## Memory and lifecycle declaration

```text
Shared memory keys read or written by this promotion: none
Skill-private memory stores added: none
Lifecycle states implemented/touched:
  complete, failed, awaiting_input, canceled, blocked_for_human_review
Persistent/background components added: none
Confirmation/destructive gates weakened: no
Cloud model or private-data transfer used: no
```

## Known weaknesses

- Music collapse heuristics identify severe token-plan degeneration; they do not
  guarantee musicality, genre adherence, vocal accuracy, or a clean outro.
- Failed evidence, old runtimes, logs, and pilot artifacts need an explicit
  retention interface.
- Dashboard memory growth needs measurement over real usage after reboot.
- Gemma tool, persona, and long-context behavior remains an ongoing empirical
  qualification, despite passing the promotion bake-off and live smoke test.
- The native Vulkan community backend must be requalified when its source,
  models, Mesa, kernel, or GPU driver changes.

## Human review checklist

```text
[x] Approved production brief implemented
[x] Gemma selected and healthy in Daily Core
[x] Ministral removed from supported runtime inventory
[x] Qwen reserve verified in Music Core
[x] ACE-Step production preview resolves to AMD Vulkan
[x] Collapse retry bounded to three LM attempts
[x] Existing exact generation/revision gates preserved
[x] No new persistence, listener, watcher, or schedule
[x] Deterministic tests pass
[x] Private data was not sent to a cloud provider
[ ] Operator completes final dashboard review
[ ] Operator chooses timing for recommended host reboot
[ ] Operator approves any future cleanup of legacy models or retained evidence
```
