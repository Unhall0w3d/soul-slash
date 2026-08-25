# Memory Observatory Starmap A32 Brief

## Authority

This brief records the human-approved visual refinement of the existing Memory Observatory. It does not authorize a new memory store, inferred relationships, memory mutation, remote dependencies, network requests, or background work outside the visible Dashboard page.

## Objective

Replace the flat default visualization with a more legible star-system presentation while retaining the existing privacy-safe bounded metadata contract. The view groups nodes visually by their declared memory layer, displays only explicit relationships supplied by the backend, and keeps the existing 2D constellation and lifecycle views as fallbacks.

## Bounded behavior

- The view consumes at most 240 nodes and 400 explicit edges.
- Node coordinates, layer anchors, starfield, colors, and labels are deterministic for the same input.
- Layer grouping is presentation only and does not create semantic or authoritative memory relationships.
- Automatic rotation uses one `requestAnimationFrame` chain only while 3D mode is visible and the document is not hidden.
- Leaving the panel, switching modes, hiding the document, or disabling rotation cancels the animation frame and removes listeners.
- Reduced-motion preference disables automatic rotation.
- Drag, pointer selection, arrow keys, Space, R, wheel zoom, reset, and fullscreen are local presentation controls only.
- The existing accessible metadata list and 2D SVG views remain available.

## Privacy and authority

The renderer receives identifiers and existing lifecycle metadata only. It must not expose memory content, configured paths, credentials, private projection records, or inferred similarity. It must not call Soul operations, perform fetches, mutate memory, or select winners.

## Lifecycle

The visualization starts when the authenticated Memory Observatory panel enters 3D mode and terminates when that mode or panel is left. It has no service, timer, worker, listener, persistence, polling, or continuation outside the browser page.

## Acceptance

The candidate must pass the A32 verifier, the existing A28 and A2 Observatory verifiers, JavaScript syntax validation, memory facade validation, and `git diff --check`. Human review remains required for visual clarity and merge approval.
