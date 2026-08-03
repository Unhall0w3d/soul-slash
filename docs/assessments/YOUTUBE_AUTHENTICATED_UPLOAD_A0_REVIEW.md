# Authenticated YouTube Upload A0 Review

## Skill

Name: Authenticated YouTube upload

Risk class: Class 5 — security-sensitive OAuth authorization and external
account mutation

Branch/checkpoint: `codex/youtube-private-draft-upload`

Date: 2026-07-27

## Accepted status

```text
live_accepted
```

The implementation candidate preserved these gates. On 2026-07-30 the
Operator completed live OAuth consent and one deliberately selected private
upload through the Dashboard A1 surface; see
`docs/soul/YOUTUBE_OAUTH_CLIENT_DISCOVERY_A1_REVIEW.md`.

## Implementation summary

- Added a Desktop OAuth flow with PKCE, state validation, a one-callback
  loopback listener, three-minute timeout, exact authorization preview, and
  owner-only atomic credential storage.
- Kept the existing `YOUTUBE_DATA_API_KEY` resolver separate from the
  write-capable `soul-slash-local-publisher` OAuth project.
- Re-verifies authenticated channel ID
  `UCIY6AROma4bbum3jk2kfu-w` before every upload preview and execution.
- Revalidates the package receipt and all four package file digests.
- Binds channel, package, title, description digest, category, audience,
  synthetic-media declaration, visibility, byte sizes, and overwrite policy
  into one exact confirmation digest.
- Uses YouTube's resumable upload endpoint with acknowledged 8 MiB chunks,
  fixed retry limits, explicit timeouts, and one reviewed thumbnail.
- Records complete, partial-thumbnail, visibility-mismatch, cancellation, and
  idempotent-replay outcomes without tokens or client credentials.
- Provides a foreground CLI only. No OAuth secret or mutation operation is
  exposed through the Dashboard in A0.

## Files changed

```text
- Makefile
- README.md
- config/project_tracker_seed.json
- docs/CURRENT_STATE.md
- docs/ROADMAP.md
- docs/assessments/YOUTUBE_AUTHENTICATED_UPLOAD_A0_REVIEW.md
- docs/guides/MUSIC_STUDIO.md
- docs/guides/YOUTUBE_PUBLICATION.md
- docs/soul/YOUTUBE_AUTHENTICATED_UPLOAD_A0_BRIEF.md
- lib/soul_core/youtube_api_client.rb
- lib/soul_core/youtube_authenticated_upload_service.rb
- lib/soul_core/youtube_oauth_service.rb
- scripts/soul-youtube-publisher
- scripts/verify-youtube-authenticated-upload-a0.rb
```

## Commands run

```text
ruby -c lib/soul_core/youtube_api_client.rb
ruby -c lib/soul_core/youtube_oauth_service.rb
ruby -c lib/soul_core/youtube_authenticated_upload_service.rb
ruby -c scripts/soul-youtube-publisher
make verify-youtube-authenticated-upload
make verify-music-publication-package
ruby -rjson -e 'JSON.parse(File.read("config/project_tracker_seed.json"))'
git diff --check
```

## Deterministic test results

```text
Command: make verify-youtube-authenticated-upload
Result: pass
Notes:
- wrong authorization confirmation writes no credential
- valid callback stores owner-only credentials for the exact channel
- client secrets and OAuth tokens do not enter results or receipts
- stored-token refresh re-verifies the channel
- wrong callback state and callback timeout terminate safely
- upload preview defaults private and binds exact package/channel evidence
- wrong upload confirmation performs no API mutation
- video then thumbnail ordering records the returned private draft
- successful replay is idempotent
- thumbnail failure records a partial remote outcome
- cancellation after remote creation records the returned video ID and stops
- changed/unreceipted packages cannot reach the API
- transient failures stop at the fixed retry bound
- resumable upload honors acknowledged 8 MiB chunks
- all Google-facing tests use fake transports

Command: make verify-music-publication-package
Result: pass
Notes: Existing exact local package, description, thumbnail, and Dashboard
package-export behavior remains intact.

Command: project tracker JSON parse and git diff --check
Result: pass
```

## Local LLM eval results

```text
Eval command or method: not applicable
Model/endpoint: none
Result: not run
Notes: OAuth, path, digest, retry, channel, and mutation behavior is
deterministic. Model behavior grants no authority in this workflow.
```

## Eval prompts

```text
None. No model routes or conversational phrasing were added.
```

## Memory keys

Reads:

```text
- none
```

Writes/updates:

```text
- none
```

Forget behavior:

```text
Not applicable.
```

## Lifecycle states touched

```text
- complete
- failed (transport exception category)
- awaiting_input
- canceled
- blocked_for_human_review
```

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
launch agent added: no
Windows service added: no
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Skill-private memory store added: no
```

One loopback listener exists only during an explicitly confirmed foreground
OAuth invocation. It accepts one callback or times out, then closes before the
operation returns, as specifically authorized by the brief.

## Known weaknesses

```text
- OAuth authorization may need renewal or re-consent according to Google's
  token and application policy.
- Google may force the API project's uploads to private until an API audit.
- OAuth consent in Testing mode can expire after seven days.
- A0 is CLI-only and does not expose status or upload gates in Music Studio.
- Description synchronization is not implemented by this brief.
- Remote video deletion, replacement, visibility mutation, scheduling, and
  playlist management are intentionally absent.
- If transport is interrupted after Google creates a video but before returning
  its ID, Soul can report uncertainty but cannot identify or delete the remote object.
```

## Human review checklist

```text
[x] Matches approved brief
[x] No unapproved scope expansion
[x] No unapproved persistence/background behavior
[x] Risk class is correct
[x] Memory behavior is appropriate
[x] Confirmation gates are intact
[x] Deterministic tests are meaningful
[x] Local LLM evals are behavioral only
[x] Failure behavior is predictable
[x] Logs/reflection are useful
[x] Live OAuth channel identity is correct
[x] One selected private upload is acceptable
```

## Human review outcome

```text
Outcome: accepted
Reviewer: Operator
Date: 2026-07-30
Decision summary: Exact-channel OAuth and one exact private upload completed through the bounded Dashboard path; later publication remained human-controlled.
Required changes: none for accepted scope
```
