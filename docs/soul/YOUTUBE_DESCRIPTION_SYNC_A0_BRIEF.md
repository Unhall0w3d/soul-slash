# YouTube Description Sync A0 Brief

Status: owner-authorized implementation candidate

Draft date: 2026-07-27

Authorization date: 2026-07-27

## Outcome

Replace one exact NOC Thoughts URL block in each explicitly mapped Soul Slash
Synthesis video description through the official YouTube Data API. Every other
description byte and all unrelated video metadata remain unchanged.

The initial mapping covers the eight videos published on the channel as of the
authorization date. `Afterimage Current` links to the article that discusses
it directly; the other seven videos link to the Music Studio, Visual Studio,
and Core-swapping workflow article.

## Input contract

The operation accepts one reviewed JSON mapping file containing:

- the expected Soul Slash Synthesis channel ID;
- a bounded list of unique YouTube video IDs;
- the exact current URL expected below a standalone `NOC Thoughts` line; and
- the exact replacement NOC Thoughts article URL.

Only `https://nocthoughts.com/` URLs are accepted. A mapping may contain no more
than 50 videos. Missing, duplicate, malformed, redirected-domain, or unexpected
URLs block the entire preview.

## OAuth boundary

- Use the existing installed/Desktop OAuth transport and official YouTube Data
  API.
- Store description-sync authorization separately from upload authorization.
- Request only `youtube.readonly` and `youtube.force-ssl` for this credential.
- Keep the upload credential and its `youtube.upload` scope unchanged.
- Verify the authenticated channel is exactly
  `UCIY6AROma4bbum3jk2kfu-w` before preview and execution.
- Never print, log, package, or return client secrets, authorization codes,
  access tokens, or refresh tokens.
- Authorization is one bounded foreground browser-consent operation with one
  loopback callback and the existing fixed timeout.

## Managed description block

Each mapped description must contain exactly one standalone block:

```text
NOC Thoughts
<expected-current-url>
```

The synchronizer replaces only the URL bytes in that two-line block. It
preserves line endings and every byte before and after the URL. Descriptions
with no matching block, multiple `NOC Thoughts` lines, or an unexpected current
URL block the batch before mutation.

An already-correct replacement URL is an idempotent no-op.

## Preview and confirmation gate

Preview:

1. refreshes the description-sync OAuth credential;
2. verifies the exact channel;
3. fetches the current snippets for every mapped video in one bounded request;
4. verifies every video belongs to the expected channel;
5. constructs exact before/after descriptions in private local state;
6. binds the mapping digest, channel, video IDs, titles, categories, tags,
   language fields, and before/after description digests into one SHA-256
   scope; and
7. reports each changed or already-current URL without exposing credentials.

Execution requires:

```text
UPDATE_YOUTUBE_DESCRIPTIONS
```

and the exact preview digest. Execution re-fetches all current snippets and
rebuilds the scope. Any mapping, channel, title, category, tag, language, or
description change invalidates the preview and updates nothing.

## Mutation boundary

Each `videos.update` request uses `part=snippet` and sends back the exact current
title, category, tags, and supported language fields with only the description
URL replaced. The operation:

- never includes `status`, so it cannot change visibility, publication,
  audience, embedding, licensing, or synthetic-media declarations;
- never uploads, deletes, schedules, comments, announces, changes thumbnails,
  modifies playlists, or changes channel branding;
- never changes titles, categories, tags, or language metadata; and
- never edits videos outside the reviewed mapping.

Execution updates mapped videos sequentially. After each successful remote
mutation it atomically records progress. A failure or cancellation stops future
updates and reports the completed and remaining video IDs without blind retry.

## Rollback evidence

Before the first remote update, Soul writes an owner-only atomic snapshot under
ignored runtime storage containing the exact original and proposed snippets,
mapping digest, channel identity, and preview digest. The receipt references
that snapshot and records per-video outcomes.

A0 does not automatically roll back remote metadata. The snapshot is evidence
for a separately reviewed manual or future bounded restoration action.

## Runtime and persistence boundary

- Foreground invocation only.
- One bounded authorization, preview, or execution per invocation.
- No daemon, watcher, schedule, cron job, systemd unit, background continuation,
  polling loop, or automatic reaction to a new blog post or video.
- API calls use the existing timeouts, fixed retry count, response-size limit,
  and safe error redaction.
- Snapshot and receipt files are owner-only, atomic, and stored below ignored
  `Soul/runtime/youtube_description_sync/`.
- No shared-memory key is added.

## Lifecycle states

- `complete`
- `failed`
- `awaiting_input`
- `canceled`
- `blocked_for_human_review`

No invocation returns while work continues.

## Deterministic verification

Fake-transport tests must prove:

- upload and description-sync credentials remain separate;
- the description credential requires the exact approved scopes and channel;
- wrong confirmation, stale digest, wrong channel, changed metadata, duplicate
  mapping IDs, malformed URLs, missing/multiple managed blocks, and unmapped
  remote videos cause no update;
- only the managed URL bytes change;
- title, category, tags, language metadata, and status remain untouched;
- already-current mappings are idempotent;
- partial failure and cancellation stop future updates and retain owner-only
  rollback evidence;
- tokens and client secrets never enter output, snapshots, or receipts; and
- no real Google request occurs in the deterministic suite.

## Risk classification

Class 5: security-sensitive OAuth authorization and externally visible account
metadata mutation.

## Owner authorization checklist

```text
[x] Expected channel is UCIY6AROma4bbum3jk2kfu-w.
[x] Description sync uses a separate OAuth credential and broader metadata scope.
[x] Only exact mapped NOC Thoughts URL blocks may change.
[x] Every batch requires a fresh preview, exact digest, and confirmation phrase.
[x] Titles, tags, categories, language fields, status, and visibility are preserved.
[x] Owner-only rollback evidence may be stored in ignored runtime state.
[x] No automatic rollback, upload, publication, schedule, or background sync is authorized.
```
