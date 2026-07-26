# Accepted Stream Disconnect Completion A0 Brief

## Objective

Preserve the terminal lifecycle of an already-accepted bounded foreground
operation when its dashboard client disconnects during streamed response
delivery.

## Boundary

- A disconnect while writing response headers still aborts before the stream
  body begins.
- Once response headers have been written and the stream body is being
  consumed, a broken client socket disables further writes but does not abandon
  the accepted operation.
- The existing request thread continues consuming only that bounded response
  enumerator and terminates when the operation reaches its normal terminal
  state.
- No detached worker, queue, retry, persistence, polling, or background
  continuation is introduced.

## Acceptance

- Connected clients receive the existing fixed-length or chunked response.
- A body-write disconnect causes no additional writes to the dead socket.
- The accepted response body still reaches completion.
- Header-write disconnects retain the existing `ClientDisconnected` behavior.
- Responsive-chat CSRF verification checks every current recovery guard instead
  of relying on an obsolete number of call sites.
- Phase 12C static-route verification validates bounded allowlisted assets and
  their type-specific directories without freezing an obsolete asset count.

## Risk

Low to moderate. This restores the original accepted-stream lifecycle while
retaining bounded request-thread ownership.
