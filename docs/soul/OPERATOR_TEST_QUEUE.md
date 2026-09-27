# Soul operator test queue

Snapshot: September 26, 2026, after the owner-approved dashboard restart.
This tracks the current Camera, Voice, and Qwen acceptance cycle. Historical
assessment checkboxes retain their original evidence date. A passing component
test, merged commit, or active service is not an attended result.

## C1 — Camera in the resident dashboard: attended test pending

**Now:** Camera A0 is merged and pushed. `soul-dashboard.service` restarted
September 26 at 20:55 EDT as PID 1025202. Live `/` serves the Camera control
hidden by default, dashboard/camera assets match merged source, and
unauthenticated `/camera` plus gesture resources return 401. In-process
authenticated-route and synthetic browser tests pass. No webcam was opened for
the resident read-back.

**Operator test:** Sign in, confirm Camera appears, and open its separate page.
Confirm the camera starts off and requires an explicit **Start camera** click.
With the NexiGo, check Stop, one-frame capture into a removable Chat preview,
and the camera-off indicator after capture or close. Gesture feedback in usable
light is useful, but model inference is unnecessary for this check.

**Unattended preparation:** Read-only service, headers, asset, and pinned-digest
checks passed. Closing C1 needs an authenticated browser session and visible
capture. The earlier physical NexiGo demonstration produced an open-palm cue;
other lighting and poses remain optional quality follow-up. Face recognition
and desktop control are outside Camera A0.

## V1 — Voice/Whisper after resident reload: attended smoke pending

**Now:** Voice A1 and guarded CUDA Whisper routing are merged. Their September
25 attended wake, five-second follow-up, and abstention sequence passed in a
temporary Voice Presence window. The resident dashboard now started after the
merge, but this exact combination has not had an attended voice turn. Ordinary
Whisper remains AMD; CUDA is an explicit session choice.

**Operator test:** Launch one visible Voice Presence window and confirm a
spoken turn and natural follow-up reach the refreshed dashboard. If testing
beside an AMD game, choose the reviewed session-only CUDA route and check Qwen
restoration. Close the window and confirm capture and workers stop.

**Unattended preparation:** Deterministic and earlier attended results are
retained. There is no need to repeat the broad suite or open the microphone
unattended before this focused smoke.

## Q1 — Qwen selected startup: next cold boot pending

**Now:** The guard was merged September 25 at 20:19 EDT. This host booted
September 22 at 23:36 EDT, so the guard has not been exercised by a boot.
Current Qwen PID 484511 holds 5,296 MiB on the reviewed NVIDIA GPU; that proves
current placement only. The selected one-shot is enabled.

**Operator event:** At the next normal cold boot, let the existing selector
run. It must complete only after the exact `llama-server.service` MainPID holds
at least 4,500 MiB on the CUDA-visible GPU UUID. A CPU-backed active unit is a
failure, even if HTTP health succeeds later.

**Unattended follow-up:** After that boot, collect the boot time, same-boot
`soul-model-runtime-selected.service` result and journal, selected profile,
`llama-server.service` MainPID, and `nvidia-smi` compute allocation for that PID
and UUID. No reboot, model transition, or new background monitor is needed now.

## Other roadmap decisions

The [Roadmap](../ROADMAP.md) separately lists artistic review of the retained
variable-duration Music Studio cohort, Software/Storage Steward A0–A1,
Incident Narrator A0, and Fleet Observability A2/A3. YouTube description-link
sync still needs its reviewed live OAuth batch; track-aware production is
paused for FL Studio and its A0 interchange proof. These are separate scopes,
not prerequisites for C1, V1, or Q1. Their assessment files and current dirty
working-tree changes need individual review before promotion.

## Update rule

Mark a gate passed only with its named live or attended evidence and date.
Record status and headers for the dashboard without saving frames or browser
credentials. Keep merged-code, service-reload, and end-to-end evidence distinct.
This queue grants no automatic approval, camera activation, restart, or reboot.
