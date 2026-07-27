# YouTube Publication

Soul can turn one reviewed Music Studio upload package into one
operator-authorized YouTube upload. This is an optional foreground workflow;
it does not run from the Dashboard, at startup, on a schedule, or after package
export.

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
```

Engineering scope and owner authority are recorded in
[`YOUTUBE_AUTHENTICATED_UPLOAD_A0_BRIEF.md`](../soul/YOUTUBE_AUTHENTICATED_UPLOAD_A0_BRIEF.md).
