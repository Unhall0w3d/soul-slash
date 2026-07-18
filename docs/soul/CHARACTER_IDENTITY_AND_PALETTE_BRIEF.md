# Character Identity and Palette Brief

```text
date: 2026-07-18
human_authorization: approved in the active development conversation
implementation_authorized: yes
source_archive: ~/Downloads/soul-interface-character-assets-v2.zip
layout_redesign_authorized: no
human_visual_review_required: yes
risk: Class 1 - local visual assets and presentation only
```

## Objective

Make the approved character portrait the visible representation of Soul and
translate the dashboard's visual system to the portrait's graphite, indigo,
ice-blue, and aged-bronze palette. Preserve the established layout, feature
parity, semantic danger color, interaction gates, and responsive behavior.

## Reviewed source assets

```text
Soul-Full-Body.png                  941 x 1672 RGB
Soul-Shoulder-Portrait-Unmasked.png 941 x 1672 RGB
Soul-Shoulder-Portrait-Masked.png   941 x 1672 RGB
```

The archive contains only these three root-level PNG files. It has no path
traversal, executable, metadata sidecar, or nested archive. The source images
are copied byte-for-byte into the tracked brand assets; they are not regenerated
or sent to an external model.

## Authorized vertical slice

- Add the three exact source images beneath `assets/brand/character/`.
- Replace the geometric chat-rail familiar with a clipped shoulder portrait.
- Show the masked portrait, darkened and slightly desaturated, while Soul is
  idle, newly received, complete, or failed.
- Crossfade to the brighter unmasked portrait while Soul is actively reading,
  planning, inspecting, researching, synthesizing, drafting, reviewing, or
  finalizing.
- Use a CSS crossfade driven by the existing request-scoped `data-state`; add no
  timer, watcher, polling, animation loop, or new model inference.
- Keep the full-body image available as a reviewed brand asset without forcing
  it into a cramped dashboard surface in this slice.
- Translate shared colors and remaining old-theme literals across the entire
  dashboard, not only the Chat tab.
- Recolor the existing SVG micro-mark while keeping its viewbox, path geometry,
  strokes, widths, and topology unchanged.
- Keep the SVG micro-mark as the favicon, top-bar mark, and compact system glyph
  because the raster portrait is not legible at favicon scale.
- Add same-origin static routes, deterministic verification, documentation, and
  a human review artifact.

## Palette contract

```text
Abyss / near black       #0B0D13
Deep graphite-blue       #161B25
Slate                    #19222C
Raised graphite          #273746
Machine indigo           #303867
Indigo highlight         #4E6A9D
Cerulean                 #3AAEDF
Soft interface blue      #64A8D2
Pale luminous copy       #A9D1E4
Strong copy              #D4E2EA
Accessible muted copy    #93A5B9
Aged bronze              #A77B5B
Bronze shadow            #5B4033
Bronze highlight         #D0A785
Destructive crimson      #FF1744 (unchanged semantic role)
```

Pure white remains absent from large surfaces. Bronze replaces the prior
yellow-gold structural treatment; ice-blue replaces neon cyan; indigo becomes
a restrained material depth rather than a generic purple action color.

## Responsive and motion behavior

- The portrait chamber remains within the existing left rail and may not cover
  conversation titles or controls.
- `object-fit: cover` and an explicit focal position preserve the face at
  desktop, ultrawide, and narrow widths.
- The portrait change uses only opacity and the existing foreground state.
- `prefers-reduced-motion` removes the crossfade transition and all existing
  familiar motion remains absent because the geometric familiar is removed.
- Portraits are decorative; existing textual live status remains the accessible
  representation of Soul's activity.

## Hard boundaries

- No conversation, model, memory, skill, Core, service, authentication, or
  approval behavior changes.
- No external image generation, tracking pixel, remote font, CDN, or network
  asset dependency.
- No claim that the portrait represents embodiment or sensor evidence.
- No automatic state change beyond the existing request lifecycle.
- No destructive crimson recoloring into an ordinary decorative accent.

## Required evidence

- source and tracked SHA-256 equality for all three PNGs;
- same-origin static routes and authenticated dashboard delivery;
- unchanged SVG geometry with only reviewed color/description edits;
- palette-token presence and removal of the prior primary yellow/neon literals;
- readable text contrast for primary, secondary, muted, bronze, and cerulean
  roles against the principal dark surfaces;
- portrait state mapping for idle and active request states;
- no timer, polling, remote URL, or executable archive content;
- Phase 12C, Self Improvement, Music Studio, Core, and Gemma dashboard
  regressions;
- human desktop/ultrawide and later phone-width visual review.

## Human review outcome

```text
Outcome: implementation authorized
Reviewer: repository owner
Date: 2026-07-18
Decision summary: Use the supplied character representation and harmonize the dashboard palette; recolor the existing favicon without changing its design.
```
