# Music YouTube Package Human Review

Status: candidate-complete; owner review required

## What was implemented

- deterministic editable YouTube-description draft;
- exact additive local package gate;
- upload-ready MP4, thumbnail, description sidecar, and future upload metadata;
- deterministic thumbnail extraction from an exact reviewed motion preview when
  the companion has no static `base.png`;
- truthful instrumental/vocal credit selection;
- semantic genre-clause extraction without partial words or cut-off lists;
- explicit private, synthetic-media, no-upload, and human-publication fields;
- Music Studio controls after a full Visual Companion is ready.

## Deterministic verification

```sh
ruby scripts/verify-music-publication-package.rb
ruby scripts/verify-music-visual-companion.rb
ruby scripts/verify-phase12b-in-process-application-api.rb
node --check assets/dashboard/dashboard.js
git diff --check
```

## Local LLM evaluation

Not applicable. Description assembly, path validation, digest gating, and file
copying are deterministic. No model output grants export or publication
authority.

## Memory keys

None.

## Lifecycle states

- `complete`
- `awaiting_input`
- `blocked_for_human_review`

## Risk classification

Medium local file-write risk. The package is additive and cannot overwrite an
existing `youtube/` directory. External upload/publication remains unavailable.

## Known weaknesses

- the genre influence is deterministically derived from the leading genre
  clause and may still benefit from human editing for unusually structured
  captions;
- YouTube API upload is intentionally absent;
- the default generated-motion thumbnail is the frame at one second; later
  thumbnail selection remains a separate human-reviewed enhancement;
- a new unaudited Google API project cannot support later manual publication of
  its API-uploaded video without completing Google's audit requirements.

## Human review checklist

- [ ] Record `keep` for the intended Music candidate and export the song.
- [ ] Play the full Visual Companion and confirm audio/video identity.
- [ ] Open the proposed description and review genre, intent, links, and credit.
- [ ] Confirm instrumental descriptions omit lyrics and lyric credit.
- [ ] Preview the exact package scope and export it.
- [ ] Inspect all four files under the song's `youtube/` directory.
- [ ] Confirm no network request, upload, scheduling, or publication occurred.
