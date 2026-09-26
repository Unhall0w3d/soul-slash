# Soul camera session A0

Lifecycle: blocked_for_human_review. Candidate implementation, synthetic
browser qualification, physical NexiGo capture, and an attended open-palm
demonstration are complete. Risk: camera privacy and browser execution policy.
Candidate branch: `codex/soul-camera-session-a0`. Merge and resident-dashboard
deployment remain pending owner review.

## Implementation summary

- Chat's **Camera** button opens a separate authenticated window. Its camera
  starts only after pressing **Start camera**. Stop, capture, page hide/close,
  opener close, and a two-minute timeout stop the video tracks.
- **Capture preview to Chat** transfers one bounded JPEG through an exact
  same-origin, popup-source, random-session-token check. The existing removable
  picture preview and optional retention checkbox then apply. Nothing enters
  the vision model until an explicit question is sent.
- An optional, browser-local MediaPipe gesture recognizer displays only
  open palm, thumbs up, or victory feedback. It cannot send Soul commands,
  control the OS, or perform facial recognition.
- The model and WebAssembly runtime are installed under ignored
  `Soul/runtime/gesture` from pinned official package/model digests.
  Authenticated routes verify exact bytes before serving them. No cloud
  inference, daemon, watcher, or recurring camera capture was added.
- The main dashboard retains `camera=()` and its original script policy.
  Only the separate camera page enables `camera=(self)` and
  `wasm-unsafe-eval`; JavaScript `unsafe-eval` remains prohibited.

## Changed paths

`assets/camera/index.html`, `assets/camera/camera.css`,
`assets/camera/camera.js`, `assets/dashboard/index.html`,
`assets/dashboard/dashboard.js`,
`lib/soul_core/camera_gesture_assets.rb`,
`lib/soul_core/dashboard_http_application.rb`,
`scripts/install-camera-gesture-assets.rb`,
`scripts/verify-camera-session-a0.rb`,
`scripts/verify-camera-session-a0.js`, and
`docs/guides/PICTURE_UNDERSTANDING.md`.

## Validation

- Pinned package SHA-256:
  `ee318eaa3d42230aa10910d114faf2a488c577c4e4d33c7cb04126924aca505f`.
  Pinned model SHA-256:
  `a966b1d4e774e0423c19c8aa71f070e5a72fe7a03c2663dd2f3cb0b0095ee3e1`.
- Installer accepted those exact assets; `verify-camera-session-a0.rb`
  passed asset digests, authentication, scoped policies, exact routes and
  Chat-message validation. `verify-camera-session-a0.js` passed explicit
  start/stop, one-frame transfer, hidden-window shutdown, and intermittent
  open-palm acceptance with low-score and no-gesture rejection.
- `verify-perception-a1.rb` and `verify-perception-a2.rb` passed existing
  picture analysis, retention, and screen-preview boundary checks.
- Real headless Chromium with a synthetic 640×480 camera started/stopped the
  isolated page, loaded the pinned local gesture model to Ready, and passed a
  captured 8,497-byte JPEG into the real Chat preview through the popup.
  These tests did not use a physical webcam or recognize a real hand.
- The temporary fixture server and ChromeDriver were stopped after testing.
- The broad historical Phase 12C foreground verifier still fails on a
  pre-existing SVG namespace URL in baseline dashboard JavaScript and on the
  repository curation gate for unrelated untracked files. Its source at HEAD
  contains the same URL. The scoped camera checks and existing perception A1/A2
  checks above passed.

## Physical acceptance and limits

After the Operator reconnected the webcam, `lsusb` identified the NexiGo N60
FHD Webcam (`3443:60bb`) and V4L2 exposed `/dev/video0` and `/dev/video1`.
A single local FFmpeg capture from `/dev/video0` produced a valid 640×480
room frame. It was visually inspected for actual scene content, found to be
quite dark, and deleted after verification.

A temporary local Chromium session used the actual NexiGo, with no synthetic
video device: the browser reported a 640×480 live track labelled
`NexiGo N60 FHD Webcam`, brightness 29/255 with nonblank range 219, and the
local gesture runtime reached Ready. Stopping the page changed the track to
`ended` and its indicator to Camera off. The browser profile and fixture
server were temporary. No USB or system configuration was changed.

The first low-light live runs reported `Closed_Fist`/`None` or intermittent
`Open_Palm` scores around 0.50–0.71. The original 0.80 score requirement and
then a three-consecutive-frame requirement suppressed the visual cue. The
candidate now requires three matching labels with score at least 0.50 among
eight recent frames; the cue remains local text only. The JavaScript regression
covers low-score, unsupported-label, intermittent-positive, and no-gesture
cases. A visible Chromium run with the physical NexiGo reached gesture Ready,
showed `Open palm · hello · local visual cue only`, and confirmed the camera
track ended and indicator returned to Camera off. The final window used no
synthetic video source and closed after the cue. Actual recognition in other
lighting, poses, and distances is not qualified.

## Low-light follow-up

The NexiGo reports automatic exposure mode 3 (automatic exposure time with
manual aperture) and gain 5 on a 0–100 control. With the webcam idle, a
local no-file FFmpeg signal-statistics comparison measured mean frame luma:
gain 5 at 15 fps, 105; gain 15 at 15 fps, 107; gain 30 at 15 fps, 99;
gain 5 at 10 fps, 100; and gain 5 at 5 fps, 98. These are sequential room
samples, not a controlled gesture-accuracy comparison. They did not justify
a persistent gain or frame-rate override. Gain was read back at its original
value 5 afterward; automatic exposure was left as found. The candidate camera
page and guide now give practical camera-side lighting and framing guidance.
A future image-preprocessing mode would require paired accuracy and latency
tests before adoption.

## Unattended lifecycle hardening — September 25

Review found that an opened video track waited for `video.play()` to resolve
before the Stop button and two-minute deadline were enabled. A stalled playback
promise could therefore keep the camera track open without that deadline. The
candidate now enables Stop, attaches the track-ended handler, and schedules the
deadline immediately after the stream opens, before awaiting playback. A
missing video track also closes the session.

The JavaScript verifier now holds `video.play()` pending and checks that Stop
is enabled and the deadline stops the track. The same verifier failed on the
saved pre-fix camera JavaScript and passed on the revised candidate.

A second failure path left the track running when Capture was pressed before a
frame was ready or canvas encoding failed. The candidate now ends the session
on every capture attempt, including those failures. It also requires current
video frame data before encoding, so dimensions left over from an earlier
stream cannot be sent as a new preview. The added no-frame and stale-frame
tests failed before their fixes and passed afterward; the canvas-error case
also passes. `node --check` accepted the changed scripts. These were synthetic
regressions only; the physical webcam was not opened for this follow-up. Human
camera code and deployment review remains open.

Automatic approval review rejected an earlier proposal to expand camera and
WebAssembly permissions across the entire dashboard. The isolated-page
implementation above keeps that broader policy change out of scope.

No face recognition, identity matching, child access, or desktop action was
implemented. No camera pixels were promoted to memory in qualification.
Human review: inspect the isolated page/transfer boundary and visible framing,
then decide merge and deployment readiness. Source edits have not restarted
the resident dashboard; the physical demonstration used a temporary local
fixture serving the candidate camera page and assets.


## Isolated branch validation — September 25

Thirteen exact candidate files were copied into the camera branch and
byte-checked against the original working tree. The 42 MB gesture runtime was
copied only to the branch's ignored `Soul/runtime/gesture` directory for tests;
it is not part of the candidate commit. The camera Ruby and JavaScript
verifiers, Perception A1/A2 regressions, JavaScript syntax checks, and
`git diff --check` passed in that isolated worktree. No webcam or resident
dashboard service was started for this validation.

## Live dashboard boundary — September 25

The resident dashboard Ruby process began on September 23, before this camera
candidate. Its HTML and dashboard JavaScript are read from the working tree on
each request, while its route table was loaded when the process started. A
read-only loopback check found the Camera button and script exposed from the
dirty working tree but `GET /camera` returned 404 from the older process.
That was an inconsistent partial exposure, not camera deployment.

After preserving the 13 candidate files in this committed branch and an exact
hash-checked local backup, the five tracked camera-related main-tree files
were returned to committed `HEAD` and the six untracked camera entries were
moved to the backup. A fresh loopback check found no Camera control or camera
JavaScript in the main dashboard, and `GET /camera` remained 404. The
resident dashboard was not restarted; unrelated dirty work and the ignored
pinned gesture runtime were left in place.

A later approved merge needs a coordinated dashboard restart and read-back:
the main page should expose the control, unauthenticated `/camera` should
return 401, and authenticated capture should reach a removable Chat preview.
Do not treat copying source files into this live checkout as deployment proof.

## Human review outcome

```text
Outcome: pending
Reviewer:
Date:
Decision summary:
```
