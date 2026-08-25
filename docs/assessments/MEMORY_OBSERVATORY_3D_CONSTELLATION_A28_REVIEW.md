# Memory Observatory 3D Constellation A28 Review

Status: candidate-complete for human review, 2026-08-25

## Implemented

The Memory Observatory now has a third, optional **3D depth** presentation.
Canvas 2D projects the existing bounded metadata into deterministic XYZ space;
perspective scale, alpha, and explicit-link styling convey depth. Pointer drag,
arrow-key rotation, `R` reset, and a keyboard metadata list are available.
Constellation SVG and lifecycle SVG remain the fallback modes.

## Privacy and authority

The implementation is dashboard-only and leaves the backend projection schema
unchanged. It displays no memory content and creates no semantic or inferred
edges. Existing server caps of 240 nodes and 400 explicit links are retained,
with matching client-side bounds. The mode has no mutation authority and does
not poll, animate, or continue after the page returns control.

## Files

- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-memory-observatory-3d-a28.rb`
- `docs/soul/MEMORY_OBSERVATORY_3D_CONSTELLATION_A28_BRIEF.md`
- this review artifact

## Verification

- `node --check assets/dashboard/dashboard.js` — passed.
- `ruby scripts/verify-memory-observatory-3d-a28.rb` — passed (11 checks).
- `ruby scripts/verify-memory-observatory-dashboard-a2.rb` — passed (14 checks).
- `ruby scripts/verify-memory-observatory-facade-a2.rb` — passed (15 checks).
- Scoped `git diff --check` — passed.

These are deterministic machine checks, not approval for merge, release, or
unattended use.

## Known weaknesses and human checklist

- Canvas hit testing is intentionally approximate for small, overlapping nodes;
  keyboard metadata buttons remain the reliable inspection path.
- Browser review should confirm pointer rotation, reset, focus order, reduced
  motion expectations, and readable depth contrast at narrow widths.
- Human reviewer should confirm the visual composition, privacy-safe labels,
  explicit-link semantics, and that no approval/release decision is inferred
  from a passing verifier.
- The live Dashboard exposes the 3D Depth and Reset View controls; final pointer,
  keyboard, narrow-layout, and aesthetic review remains a human interaction.

Risk classification: low reversible presentation change; no lifecycle or
authority state is changed. Lifecycle touched: render-only mode selection and
bounded user interaction; no backend operation lifecycle is added. Memory keys:
none added or used.
