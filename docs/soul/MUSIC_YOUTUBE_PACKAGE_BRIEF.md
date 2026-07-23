# Music YouTube Package Brief

Status: owner-authorized implementation candidate

Authorization date: 2026-07-19

## Outcome

Turn one kept, finished Music candidate and its reviewed full-length Visual
Companion into a local, upload-ready package. The package is an additive
`youtube/` directory inside the existing `~/Music/soul-music/<song>/` export.

## Package

- `video.mp4` — exact reviewed H.264/AAC companion;
- `thumbnail.png` — exact approved base visual for a still companion, or one
  deterministic frame derived locally from the exact reviewed full-motion
  preview when no static base exists;
- `youtube-description.txt` — editable human-reviewed description sidecar;
- `upload.json` — title, category 10, private visibility, not-made-for-kids,
  synthetic-media disclosure, and explicit human-publication state.

The proposed description contains genre influence, intent, BPM, key, time,
intended lyrics when present, the Soul/ repository, NOC Thoughts, a local
generative/human-review disclosure, and a mode-appropriate Soul/ credit.
Genre influence is taken from the caption's complete leading genre clause,
using a colon or instrumentation transition as the semantic boundary rather
than cutting the text at an arbitrary character position.

## Authority and lifecycle

The candidate must already have a keep review and finished-song export. The
full visual companion must be `preview_ready`. The human edits the proposed
description, previews an exact digest, and clicks the prefilled
`EXPORT_YOUTUBE_PACKAGE` gate. Wrong or stale approval creates nothing. The
operation ends `complete`, `awaiting_input`, or `blocked_for_human_review` and
leaves no partial package.

No OAuth credential, Google account, network request, YouTube upload, channel
mutation, scheduling, or publication is included.

Generated-motion thumbnail derivation is part of the exact package scope. It
uses ffmpeg at a fixed one-second timestamp, performs no model inference, and
cannot substitute a different video or silently select another frame.

## Future authenticated upload boundary

The `upload.json` record deliberately matches a future private-only uploader.
Google currently locks videos uploaded by unaudited API projects created after
2020 to private viewing. A later Soul uploader therefore requires a dedicated
Google account, installed-app OAuth, YouTube Data API enablement, and a verified
or audited API project before it can support the intended private-to-human-
publish workflow. Soul must never publish automatically.
