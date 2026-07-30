# YouTube Dashboard Upload A1 Review

## Candidate

Name: Music Studio authenticated YouTube draft upload

Risk class: Class 5 — OAuth authorization and external account mutation

Status: candidate implementation; deterministic and human review pending

## Implemented scope

- Added five explicit application operations for non-secret OAuth status,
  authorization preview/execute, and upload preview/execute.
- Reused the merged A0 OAuth and upload services without weakening channel,
  package, digest, visibility, retry, receipt, or idempotence gates.
- Added Music Studio controls only after an exact local YouTube package exists.
- Preserved `private` as the selected default while rendering YouTube's required
  `unlisted` and `public` choices as explicit human decisions.
- Added bounded upload progress through the authenticated Music stream.
- Added YouTube Studio handoff links for complete, partial, and idempotent
  receipts.
- Added `~/` expansion for the existing owner-entered OAuth client path.

## Files changed

```text
Makefile
assets/dashboard/dashboard.css
assets/dashboard/dashboard.js
config/project_tracker_seed.json
docs/assessments/YOUTUBE_DASHBOARD_UPLOAD_A1_REVIEW.md
docs/guides/MUSIC_STUDIO.md
docs/guides/YOUTUBE_PUBLICATION.md
docs/soul/YOUTUBE_DASHBOARD_UPLOAD_A1_BRIEF.md
lib/soul_core/application_contract.rb
lib/soul_core/application_facade.rb
lib/soul_core/dashboard_http_application.rb
lib/soul_core/youtube_oauth_service.rb
scripts/verify-music-studio-a3.rb
scripts/verify-youtube-dashboard-upload-a1.rb
```

## Commands and deterministic results

```text
ruby -c lib/soul_core/application_contract.rb
ruby -c lib/soul_core/application_facade.rb
ruby -c lib/soul_core/dashboard_http_application.rb
ruby -c lib/soul_core/youtube_oauth_service.rb
ruby -c scripts/verify-youtube-dashboard-upload-a1.rb
node --check assets/dashboard/dashboard.js
make verify-youtube-dashboard-upload
make verify-youtube-authenticated-upload
make verify-music-publication-package
ruby scripts/verify-phase12b-in-process-application-api.rb
ruby scripts/verify-music-studio-a3.rb
make verify-project-timeline
ruby -rjson -e 'JSON.parse(File.read("config/project_tracker_seed.json"))'
git diff --check
```

All commands passed. The Dashboard verifier uses injected fake OAuth and upload
services and the A0 suite uses only fake Google transports. No live OAuth,
upload, or other Google mutation occurred.

The Music Studio A3 verifier's global browser-source assertion was narrowed to
exclude the already-reviewed maintenance-only polling delay. The original
assertion had become stale before this slice and failed against `origin/main`
despite Music Studio adding no timer.

## Local LLM evaluation

Not applicable. Model output grants no authority and does not participate in
OAuth, package validation, channel selection, visibility, or upload execution.

## Memory

No shared-memory keys are read or written. OAuth credentials remain in the
existing ignored owner-only A0 credential store.

## Lifecycle states

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

## Persistence and safety

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Background queue added: no
Automatic upload added: no
Confirmation gate weakened: no
Secret Dashboard surface added: no
```

The only listener remains A0's one-callback OAuth loopback listener. It closes
after one callback or the existing three-minute timeout.

## Known weaknesses

- Live OAuth consent is not yet accepted.
- No selected package has completed a supervised private upload.
- Dashboard authorization opens the consent page on the Soul host and is
  intended for at-computer acceptance.
- Navigating away does not create a hidden continuation job.
- Google may force unaudited API-project uploads to private.
- Remote deletion, replacement, scheduling, playlist changes, and later
  visibility mutation remain unavailable.

## Human review checklist

```text
[ ] OAuth status contains no secret material.
[ ] Authorization preview identifies soul-slash-local-publisher and the exact channel.
[ ] Consent opens only after the explicit authorization click.
[ ] Authenticated channel is Soul Slash Synthesis.
[ ] Upload controls appear only for an exact local package.
[ ] Private is selected by default.
[ ] Non-private visibility requires an explicit human selection and fresh preview.
[ ] Upload scope identifies the exact package, title, channel, files, and visibility.
[ ] One selected private draft uploads once and returns the exact YouTube Studio link.
[ ] Refreshing or replaying the same package does not duplicate the upload.
[ ] Partial thumbnail or visibility mismatch remains blocked for human review.
```

## Human review outcome

```text
Outcome: pending
Reviewer: Operator
Date:
Decision summary:
Required changes:
```
