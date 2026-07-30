# YouTube Dashboard Upload A1 Brief

Status: owner-authorized implementation candidate

Authorization date: 2026-07-30

## Outcome

Expose the already-merged authenticated YouTube uploader through the reviewed
Music Studio workflow. A human can inspect OAuth status, authorize the exact
Soul Slash Synthesis channel, select one already-exported YouTube package,
preview one exact upload, and click one explicit gate to upload it for human
review.

The existing A0 OAuth, package-validation, channel-identity, digest,
visibility, retry, receipt, and idempotence rules remain authoritative.

## Dashboard workflow

After a reviewed Music candidate and visual companion have produced an exact
local YouTube package, Music Studio may show:

1. non-secret OAuth status;
2. a bounded list of locally detected, already-valid owner-only Desktop OAuth
   client JSON files plus a manual local path field when authorization is not
   configured;
3. the exact authorization preview and one click-authorized foreground consent
   operation;
4. the authenticated channel title and ID;
5. an explicit visibility selector with `private` selected by default;
6. the exact upload preview; and
7. one click-authorized foreground resumable upload with bounded progress.

Successful and partial results link to YouTube Studio for human review. Soul
does not publish, schedule, announce, replace, delete, or later change the
video.

## Security and authorization boundary

- Dashboard authentication, changed-bootstrap-password, same-origin, CSRF, and
  application-operation allowlists remain mandatory.
- The Dashboard never receives, stores, renders, logs, or returns client
  secrets, authorization codes, access tokens, refresh tokens, or
  Authorization headers.
- Discovery examines at most 64 direct children of the Operator's Downloads
  directory, accepts only the standard Google Desktop client filename shape,
  and returns only validated path, filename, project, and application type.
  It never recursively scans, follows symlinks, or returns client contents.
- The OAuth client path is passed only to the existing A0 validator. The file
  must remain a regular non-symlink owner-only Desktop client JSON for the
  exact `soul-slash-local-publisher` Google project.
- Authorization keeps the existing exact preview digest and
  `AUTHORIZE_YOUTUBE` confirmation. The reviewed button click supplies the
  displayed phrase; model output grants no authority.
- Upload keeps the existing exact preview digest and
  `UPLOAD_YOUTUBE_VIDEO` confirmation. The reviewed button click supplies the
  displayed phrase; model output grants no authority.
- `private` is the default. `unlisted` and `public` remain visible solely
  because YouTube requires the choice, and selecting either is an explicit
  human publication decision bound into a new preview digest.
- Upload execution revalidates OAuth identity, package receipt, every package
  file digest, metadata, visibility, and expected channel immediately before
  contacting YouTube.

## Runtime boundary

- Foreground invocation only.
- One OAuth authorization or one upload per invocation.
- OAuth's temporary loopback callback listener closes after one callback or the
  existing three-minute timeout.
- Upload progress uses the authenticated bounded Music stream and terminates
  with the operation.
- No worker, queue, daemon, watcher, service, timer, automatic retry beyond A0's
  bounded transport retry, or automatic upload is added.
- Navigating away may terminate the browser request; it does not create a
  hidden Dashboard job. Any uncertain remote outcome remains blocked for human
  review under the A0 receipt rules.

## Application operations

```text
youtube.oauth.status
youtube.oauth.authorization.preview
youtube.oauth.authorization.execute
youtube.upload.preview
youtube.upload.execute
```

Only `youtube.upload.execute` is accepted by the bounded Music progress stream.
Every other operation uses the ordinary authenticated application call.

## Lifecycle states

- `complete`
- `failed`
- `awaiting_input`
- `canceled`
- `blocked_for_human_review`

No invocation may return while its OAuth or upload operation continues.

## Deterministic verification

The A1 verifier must prove:

- the application contract allowlists only the exact five operations;
- the facade delegates to injected A0 services without changing their gates;
- Dashboard controls appear only after an exact local package exists;
- private is the rendered default and all visibility choices remain explicit;
- authorization and upload previews precede execution;
- upload execution uses the authenticated, CSRF-protected bounded Music
  stream;
- no secret value appears in Dashboard source, application responses, or test
  output;
- partial outcomes and completed receipts link to YouTube Studio;
- existing A0 fake-transport verification still passes; and
- no live Google request occurs during deterministic verification.

## Risk classification

Class 5: security-sensitive OAuth authorization and externally visible account
mutation.

## Owner authorization

The Operator approved this Dashboard completion slice on 2026-07-30. That
approval authorizes candidate implementation and deterministic verification.
It does not authorize a live OAuth consent or live upload. Those remain
separate supervised acceptance gates using one deliberately selected package.
