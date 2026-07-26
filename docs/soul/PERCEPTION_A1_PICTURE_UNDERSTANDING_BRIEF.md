# Perception A1 - Picture Understanding Brief

## Purpose

Let the authenticated Operator attach one bounded local PNG or JPEG to Chat, ask
one explicit question, and receive a local Gemma observation in ordinary
conversation continuity.

## Implementation

- A dedicated authenticated NDJSON endpoint accepts at most one base64 image.
- The ordinary application envelope and text-only provider contract remain
  unchanged.
- Magic bytes, declared media type, dimensions, decoded pixels, bytes, question,
  chat identity, and request identity are validated before inference.
- Daily Core and its reviewed Ollama profile are required.
- The native local Ollama image API receives one message-local image.
- The result records model, profile, dimensions, digest, latency, usage, retention,
  and the `untrusted_evidence_only` authority classification.
- Request receipts prevent repeat inference for the same request ID.
- Staged pixels are deleted in `ensure` on success and failure.

## Retention

Ephemeral is the default. Explicit retention stores one digest-named owner-private
file under ignored conversation state. Authenticated serving uses exact chat ID,
digest, and extension. Permanent conversation deletion includes retained images
in its preview and execution scope.

## Exclusions

- no screenshot or camera capture;
- no image URL retrieval;
- no cloud provider;
- no hidden Core transfer;
- no downstream skill or tool execution;
- no SVG, PDF, animation, WebP, or multi-image input;
- no background worker or resident vision model.

## Acceptance

See `scripts/verify-perception-a1.rb` and
`docs/assessments/PERCEPTION_A1_PICTURE_UNDERSTANDING_REVIEW.md`.
