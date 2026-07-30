# YouTube Publication

Soul can turn one reviewed Music Studio upload package into one
operator-authorized YouTube upload. The foreground CLI remains available, and
Music Studio now exposes the same OAuth, exact preview, and upload gates after
an upload package exists. It does not run at startup, on a schedule, or
automatically after package export.

The commands below are merged and executable. Authenticated upload has a
Dashboard A1 candidate; description synchronization remains an A0 CLI
candidate. Live acceptance is still open. Command or Dashboard availability
and deterministic tests do not count as live acceptance; every remote mutation
retains its exact foreground preview and human gate.

## Boundaries

- The existing Music candidate must already be kept, exported, paired with a
  reviewed full-length visual, and exported as an exact YouTube package.
- OAuth must resolve to the configured Soul Slash Synthesis channel.
- Private is the default upload visibility.
- YouTube requires upload clients to expose private, unlisted, and public
  choices. Any non-private choice is therefore an explicit Operator decision,
  displayed in preview and bound into the exact confirmation digest.
- Soul never changes visibility after upload and never schedules, publishes,
  announces, inserts into a playlist, comments, or deletes a YouTube video.
- Google may force uploads from an unaudited API project to remain private.
- A successful upload receipt blocks accidental duplicate upload of the same
  exact package.

## Use Music Studio

1. Keep and export the reviewed song.
2. Bind and render its reviewed full-duration visual.
3. Prepare the exact local YouTube package and review its description.
4. In **Authenticated YouTube draft**, inspect OAuth status.
5. If needed, enter the local path to the owner-only Desktop OAuth JSON and
   preview the exact authorization. Clicking **Authorize Soul Slash Synthesis**
   opens one bounded consent flow.
6. Leave visibility on **Private** unless you deliberately intend another
   state.
7. Preview the exact upload scope, then click **Upload private draft**.
8. Follow the returned link to YouTube Studio for final human review and any
   later publication.

The Dashboard displays all three visibility choices because YouTube requires
them, but never selects `unlisted` or `public`. The upload button is unavailable
until a package exists and the exact preview succeeds.

## Authorize the Desktop OAuth client

Use the downloaded Desktop OAuth JSON from Google project
`soul-slash-local-publisher`. Keep this file outside the repository.

```bash
chmod 600 ~/Downloads/client_secret_....json

scripts/soul-youtube-publisher authorize-preview \
  --client-json ~/Downloads/client_secret_....json
```

Review `preview_scope`, then execute the exact returned digest:

```bash
scripts/soul-youtube-publisher authorize-execute \
  --client-json ~/Downloads/client_secret_....json \
  --expected-digest <digest-from-preview> \
  --confirmation AUTHORIZE_YOUTUBE
```

Soul opens Google's consent page and creates one temporary loopback callback
listener. The listener terminates after one callback or three minutes. After
consent, Soul verifies channel ID `UCIY6AROma4bbum3jk2kfu-w` before storing the
OAuth client and refresh token under ignored owner-only runtime storage:

```text
Soul/runtime/youtube_auth/oauth.json
```

The status command reports only non-secret configuration:

```bash
scripts/soul-youtube-publisher status
```

Delete the ignored credential file and revoke the app from the Google Account
to remove local and remote authorization. A future dashboard control may
provide a reviewed revocation workflow; A0 does not mutate the Google grant.

## Preview one upload

Use the exact Music, candidate, and visual identifiers recorded by the package:

```bash
scripts/soul-youtube-publisher upload-preview \
  --project-id music_... \
  --candidate-id candidate_... \
  --visual-id visual_... \
  --visibility private
```

The preview re-hashes all four package files, refreshes OAuth, re-verifies the
channel, and binds the title, description, category, audience declaration,
synthetic-media declaration, selected visibility, sizes, and digests.

## Upload the exact preview

```bash
scripts/soul-youtube-publisher upload-execute \
  --project-id music_... \
  --candidate-id candidate_... \
  --visual-id visual_... \
  --visibility private \
  --expected-digest <digest-from-preview> \
  --confirmation UPLOAD_YOUTUBE_VIDEO
```

Soul starts one resumable upload, applies the exact reviewed thumbnail, records
YouTube's returned video ID and actual privacy state, and exits. The returned
Studio URL is the human review and publication handoff.

If the video succeeds but thumbnail application fails, Soul records the remote
video as a partial outcome and blocks. It does not delete the video or upload a
duplicate.

## Credential and logging policy

Client secrets, access tokens, refresh tokens, authorization codes, and
Authorization headers are never returned in CLI JSON, task logs, receipts,
tests, or dashboard data. Deterministic verification uses fake transports and
never contacts Google:

```bash
make verify-youtube-authenticated-upload
make verify-youtube-dashboard-upload
```

Engineering scope and owner authority are recorded in
[`YOUTUBE_AUTHENTICATED_UPLOAD_A0_BRIEF.md`](../soul/YOUTUBE_AUTHENTICATED_UPLOAD_A0_BRIEF.md).

## Synchronize NOC Thoughts article links

Description synchronization has a separate OAuth credential and confirmation
gate. It does not exercise the upload path and does not broaden or replace the
upload credential.

The reviewed initial mapping is:

```text
config/youtube_description_article_links.json
```

It identifies the exact video IDs, expected current homepage URL, and intended
article URL. Review that file before authorization.

Authorize the separate metadata scope with the same owner-only Desktop client
JSON:

```bash
scripts/soul-youtube-publisher description-authorize-preview \
  --client-json ~/Downloads/client_secret_....json
```

Review the returned scope and execute its exact digest:

```bash
scripts/soul-youtube-publisher description-authorize-execute \
  --client-json ~/Downloads/client_secret_....json \
  --expected-digest <digest-from-preview> \
  --confirmation AUTHORIZE_YOUTUBE_DESCRIPTION_SYNC
```

This consent requests `youtube.readonly` and `youtube.force-ssl` and stores the
refresh token separately at:

```text
Soul/runtime/youtube_auth/oauth-description-sync.json
```

Inspect non-secret status:

```bash
scripts/soul-youtube-publisher description-status
```

Preview the exact batch against fresh YouTube snippets:

```bash
scripts/soul-youtube-publisher description-preview \
  --mapping config/youtube_description_article_links.json
```

The preview verifies the Soul Slash Synthesis channel and binds every current
title, category, tag list, supported language field, and before/after
description digest. It replaces only the URL immediately below the single
standalone `NOC Thoughts` line. A changed title, tag, category, description,
mapping, or channel invalidates the digest.

Execute only the reviewed digest:

```bash
scripts/soul-youtube-publisher description-execute \
  --mapping config/youtube_description_article_links.json \
  --expected-digest <digest-from-preview> \
  --confirmation UPDATE_YOUTUBE_DESCRIPTIONS
```

Before the first update, Soul writes an owner-only rollback snapshot and an
atomic progress receipt below ignored
`Soul/runtime/youtube_description_sync/`. A0 does not automatically restore
remote metadata. Failure or cancellation stops the remaining batch and
requires human review.

Description sync sends `part=snippet` only. It preserves title, category, tags,
and supported language metadata and cannot change upload state, visibility,
publication, audience, thumbnail, playlist, or channel branding. It adds no
automatic or scheduled synchronization.

Engineering scope and owner authority are recorded in
[`YOUTUBE_DESCRIPTION_SYNC_A0_BRIEF.md`](../soul/YOUTUBE_DESCRIPTION_SYNC_A0_BRIEF.md).
