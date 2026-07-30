# YouTube OAuth Client Discovery A1 Review

Status: candidate-complete; awaiting human review

## What was implemented

- The unauthenticated YouTube draft panel now lists locally detected Google
  Desktop OAuth client JSON files that already pass the existing exact project,
  application type, endpoint, file type, size, and owner-only permission checks.
- The selected detected path is copied into the existing manual path field.
  Manual entry remains available.
- The authenticated resumable uploader now emits the repository-wide
  single-object progress event shape. This repairs the live dashboard failure
  that occurred before the first video chunk was sent.
- Discovery is non-recursive, follows no symlinks, and examines at most 64
  direct children of the Operator's Downloads directory.
- Dashboard responses include only the validated path, filename, project ID,
  and application type. Client IDs, client secrets, and file contents are never
  returned.

## Files changed

- `lib/soul_core/youtube_oauth_service.rb`
- `lib/soul_core/youtube_api_client.rb`
- `assets/dashboard/dashboard.js`
- `scripts/soul-youtube-publisher`
- `scripts/verify-youtube-dashboard-upload-a1.rb`
- `docs/soul/YOUTUBE_DASHBOARD_UPLOAD_A1_BRIEF.md`
- `docs/soul/YOUTUBE_OAUTH_CLIENT_DISCOVERY_A1_REVIEW.md`

## Commands run

- `ruby -c lib/soul_core/youtube_oauth_service.rb`
- `ruby scripts/verify-youtube-dashboard-upload-a1.rb`
- `ruby scripts/verify-youtube-authenticated-upload-a0.rb`
- `git diff --check`

## Deterministic results

- Ruby syntax check passed.
- YouTube Dashboard Upload A1 verifier passed, including valid-client
  discovery and unsafe-permission, wrong-project, symlink, and secret-leak
  rejection.
- Existing authenticated YouTube upload A0 verifier passed.
- The A0 verifier now exercises the real chunked client with a unary Dashboard
  callback and verifies one structured progress event per chunk.
- `git diff --check` passed.

## Local LLM evals

- Not applicable. Client discovery and validation are deterministic and must
  not depend on model output.

## Known weaknesses

- Only the conventional Google `client_secret_*.apps.googleusercontent.com.json`
  filename shape in the Operator's Downloads directory is automatically
  detected. Valid files elsewhere remain usable through the manual path field.
- Browser consent remains dependent on the desktop browser successfully
  completing Google's loopback redirect within three minutes.

## Memory keys

- None.

## Lifecycle states touched

- `complete`
- `awaiting_input`
- `blocked_for_human_review`

## Risk classification

Class 5: security-sensitive OAuth authorization support. Discovery itself is
read-only and does not authorize or upload anything.

## Human review checklist

- [ ] Detected file is shown without exposing client contents.
- [ ] Manual path entry remains available.
- [ ] Authorization still requires the exact preview and explicit button gate.
- [ ] Authorization binds to the exact Soul Slash Synthesis channel.
- [ ] No upload occurs during authorization or deterministic verification.
