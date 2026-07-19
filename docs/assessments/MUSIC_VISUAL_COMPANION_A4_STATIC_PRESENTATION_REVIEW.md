# Music Visual Companion A4 Static Presentation Review

Status: candidate-complete; human dashboard review required

## Implemented

- `static-hold-v2` is the active companion profile;
- contain/cover framing, matte color, and fade controls are digest-bound;
- the 12-second encoder path contains no displacement or creative effect;
- the full render extends the approved still and muxes exact candidate audio;
- the full render returns to the lossless PNG, uses one CRF-16 still-image
  encode, and applies restrained dark-gradient dithering to reduce banding;
- generated motion is visible but unavailable pending Visual Studio A3;
- legacy effect profiles cannot advance.

## Files changed

- `lib/soul_core/music_visual_companion_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-music-visual-companion.rb`
- `docs/soul/MUSIC_VISUAL_COMPANION_A3_LOCKED_CAMERA_BRIEF.md`
- `docs/soul/MUSIC_VISUAL_COMPANION_A4_STATIC_PRESENTATION_BRIEF.md`
- `docs/assessments/MUSIC_VISUAL_COMPANION_A4_STATIC_PRESENTATION_REVIEW.md`
- `docs/ROADMAP.md`

## Deterministic verification

`ruby scripts/verify-music-visual-companion.rb` verifies exact source/audio
binding, static-only filtering, contain framing and matte, no displacement,
immutable artifact digests, selected fade application, generated-motion UI
boundary, and absence of publication or resident model infrastructure.

## Local LLM evaluation

Not applicable. No LLM output authorizes presentation, encoding, or promotion.

## Memory keys

None.

## Lifecycle states

- `complete`
- `awaiting_input`
- `blocked_for_human_review`

## Risk classification

Bounded local encoding is low operational risk. Cross-studio binding remains an
exact human gate. Generated motion and external publication remain unavailable.

## Known weaknesses

- the short static MP4 is mechanically necessary for the existing review and
  final-render pipeline, even though it contains no motion;
- generated motion has not yet been qualified;
- cropping and matte choices require human visual review.

## Human review checklist

- [ ] confirm the card says **Static visual presentation**;
- [ ] inspect contain and cover framing options;
- [ ] confirm the generated-motion boundary is unavailable;
- [ ] preview one exact static encode;
- [ ] verify the frame has no procedural movement;
- [ ] approve, request changes, or reject the slice.
