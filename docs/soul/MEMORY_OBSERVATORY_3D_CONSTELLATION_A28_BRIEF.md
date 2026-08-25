# Memory Observatory 3D Constellation A28 Brief

Status: bounded candidate implementation scope, 2026-08-25

## Objective

Add a privacy-safe, client-only depth presentation to the existing Memory
Observatory. The existing SVG constellation and lifecycle views remain the
accessible fallback; the new view is a deterministic Canvas 2D projection of
the same bounded metadata.

## Contract

- Consume the existing `visualization.nodes` and `visualization.edges` schema
  unchanged.
- Render at most 240 nodes and 400 explicit edges.
- Use only memory ID, lifecycle state, layer, source kind, and timestamp already
  supplied by the summary. Do not show content or infer relationships.
- Derive stable XYZ coordinates from the opaque node ID and existing metadata.
- Communicate depth using perspective scale, alpha, and link styling.
- Support pointer drag and bounded keyboard rotation, plus an explicit reset.
- Render on demand only. No animation frame loop, timer, polling, watcher, or
  background continuation is permitted.
- Provide a reduced-motion media treatment; there is no automatic camera
  movement or transition to suppress.
- Detach Canvas listeners when leaving 3D mode. Keep the SVG keyboard metadata
  inspection path and provide a bounded keyboard metadata list for 3D mode.

## Non-goals

No backend/schema change, route change, semantic clustering, content display,
network graph, mutation control, WebGL dependency, or automatic Core/memory
behavior is included.

## Acceptance

`node --check assets/dashboard/dashboard.js`, the existing Observatory facade
and dashboard verifiers, and `ruby scripts/verify-memory-observatory-3d-a28.rb`
must pass. A scoped `git diff --check` must pass. Human review must still
confirm the visual result and accessibility in a browser.
