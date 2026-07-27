# Authenticated YouTube Upload A0 Brief

Status: owner-authorized implementation candidate

Draft date: 2026-07-27

Authorization date: 2026-07-27

## Outcome

Turn one exact, reviewed local YouTube package into one operator-authorized
YouTube upload through the official YouTube Data API. The package remains the
authority for the video, thumbnail, title, description, category, audience,
and synthetic-media disclosure.

The default and intended workflow uploads a private draft. Soul never chooses
to publish, schedule, or change an existing video's visibility.

## Existing input contract

The operation accepts only an existing package created by
`MusicPublicationPackageService`:

- `video.mp4`;
- `thumbnail.png`;
- `youtube-description.txt`;
- `upload.json`;
- the matching package receipt and exact recorded digests.

The uploader must reject symlinks, missing files, changed digests, paths
outside the finished export, descriptions beyond YouTube's limit, invalid
titles, and packages whose receipt does not identify the same project,
candidate, and visual.

## OAuth and credential boundary

- Use Google's installed/Desktop OAuth flow and the official YouTube Data API.
- The OAuth client JSON is operator-supplied from outside the repository.
- Client credentials, authorization codes, access tokens, and refresh tokens
  are never committed, printed, included in logs, returned through the
  dashboard, added to a package, or copied into review artifacts.
- The refresh token is written only after explicit browser consent into an
  owner-only local credential file under ignored runtime storage.
- Authorization is a bounded foreground operation. It opens one consent URL,
  accepts one loopback callback, verifies state and timeout, writes the token
  atomically, and terminates.
- No service account, API-key write attempt, credential acquisition,
  background refresh process, listener remaining after completion, or
  unattended authorization is allowed.
- Revoked, expired, malformed, missing, or wrong-scope credentials terminate
  safely and explain how the Operator can reauthorize.

The initial supplied Desktop client identifies Google project
`soul-slash-local-publisher`. The existing `YOUTUBE_DATA_API_KEY` remains
separate and read-only for `youtube.video_resolve`.

## Channel identity gate

After authorization, Soul calls `channels.list(mine=true)` and displays the
authenticated channel title and ID. Upload preview and execution are blocked
unless the returned channel ID exactly matches the locally configured expected
channel:

```text
UCIY6AROma4bbum3jk2kfu-w
```

Changing the expected channel is a separate operator configuration action and
cannot be inferred from an OAuth response, model output, package, or video
metadata.

## Preview and execution gate

Preview is read-only and includes:

- authenticated channel title and ID;
- exact package path and package receipt digest;
- title, description digest, category, audience declaration, synthetic-media
  declaration, and selected visibility;
- video and thumbnail digests and byte sizes;
- the exact confirmation phrase and expected scope digest;
- notice that YouTube may restrict uploads from an unaudited API project to
  private viewing.

Execution requires:

```text
UPLOAD_YOUTUBE_VIDEO
```

and the exact preview scope digest. A wrong, missing, or stale confirmation
uploads nothing. Any metadata, credential identity, channel identity, package
file, or digest change requires a new preview.

## Visibility and YouTube policy

YouTube's required minimum functionality says an upload client must let the
user choose `private`, `unlisted`, or `public`. The interface therefore
displays all three choices and never selects a non-private value on the
Operator's behalf.

`private` is the default. Choosing `unlisted` or `public` is an explicit human
publication decision and must be visible in the preview and bound into the
confirmation digest. The API project may still force the resulting upload to
private until Google completes the required project audit. Soul records the
visibility YouTube actually returns and never claims publication succeeded
when the returned state differs.

No later visibility mutation, scheduling, premiere configuration, playlist
insertion, comment, notification, or publication automation is included.

## Upload lifecycle

1. Revalidate the exact package and OAuth/channel identity.
2. Start one resumable `videos.insert` upload with the reviewed metadata.
3. Upload bounded chunks from the exact local video.
4. Retry only transient transport or server failures, with a fixed attempt
   limit and bounded backoff.
5. Verify the returned video resource belongs to the authenticated channel and
   record its actual privacy state.
6. Apply the exact reviewed thumbnail with `thumbnails.set`.
7. Write one private, atomic local receipt containing identifiers, digests,
   timestamps, actual privacy, and non-secret API outcomes.
8. Terminate.

Cancellation stops future chunks and leaves no Soul background process. If
YouTube has already created a partial or complete remote video, Soul reports
the returned video ID when available and blocks for human review; it does not
delete or retry blindly.

The operation is idempotent against a successful local receipt. Soul does not
upload the same exact package again unless a separately reviewed future brief
defines a safe replacement or retry workflow.

## Description synchronization boundary

The OAuth transport and token handling may be reused by a separate,
operator-invoked NOC Thoughts description synchronizer. That tool must:

- identify an explicit video-to-article mapping;
- preserve every existing description byte outside one marked managed block;
- preview every before/after change;
- require a separate exact confirmation;
- update only videos owned by the expected channel;
- perform no upload, visibility change, or unrelated metadata mutation.

Description synchronization implementation is not authorized by this brief;
only a reusable OAuth transport boundary is authorized.

## Runtime and persistence boundary

- Foreground invocation only.
- One authorization or one upload per invocation.
- No daemon, watcher, scheduled task, cron job, systemd unit, automatic upload,
  background continuation, or unbounded polling.
- Network calls use explicit connect/read/overall timeouts and bounded response
  sizes.
- Secrets are excluded from task logs, dashboard payloads, errors, receipts,
  assessments, and tests.
- No shared-memory key is added.

## Lifecycle states

- `complete`
- `failed`
- `awaiting_input`
- `canceled`
- `blocked_for_human_review`

No invocation may return while work continues in the background.

## Deterministic verification

Tests use a local fake transport and synthetic packages. They must prove:

- credentials and tokens never appear in output, logs, receipts, or fixtures;
- missing consent, wrong state, timeout, wrong channel, wrong scope, stale
  digest, changed package, symlink, and invalid metadata upload nothing;
- private is the default and visibility is operator-selected and digest-bound;
- transient retry count and total runtime are bounded;
- cancellation terminates without background work;
- an accepted upload records the exact returned video ID and actual privacy;
- thumbnail failure reports a partial remote outcome without deleting or
  duplicating the video;
- successful receipt replay is idempotent;
- no real YouTube request occurs in the deterministic suite.

A separately approved live acceptance run may upload one deliberately selected
package as private to the expected Soul Slash Synthesis channel.

## Risk classification

Class 5: security-sensitive OAuth authorization and externally visible account
mutation.

## Owner authorization checklist

Before implementation, the owner confirms:

```text
[x] Use project soul-slash-local-publisher for write-capable OAuth.
[x] Expected channel is UCIY6AROma4bbum3jk2kfu-w.
[x] Private remains the default visibility.
[x] Public and unlisted appear only because YouTube requires user choice.
[x] One exact confirmation may upload one reviewed package.
[x] Thumbnail upload is included.
[x] Soul never changes visibility after upload.
[x] OAuth tokens may be stored owner-only in ignored local runtime storage.
[x] No background, scheduled, or automatic upload is authorized.
[x] Live acceptance, if performed, requires a separately selected package.
```
