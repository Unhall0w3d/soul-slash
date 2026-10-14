# Continuity A22: LibreChat connection-ready foreground adapter

Date: 2026-10-12. The owner requests continuing through readiness to connect
LibreChat, and delegates reversible implementation choices rather than another
approval after each slice. This brief records that scope, not production release.

## Decisions and scope

- Reuse the qualified A19 direct-evidence chat profile, Qwen v9 configuration,
  journal, admission gate, fresh isolated worker and fixed localhost model route.
  Do not promote the marginal A20 prompt variant or change historical profiles.
- Provide a separate, opt-in OpenAI-compatible application and foreground entry
  point, reusing the existing loopback HTTP server. Do not change Soul dashboard
  routes, units, firewall, model/Core selection or the current LibreChat service.
  This replaces the earlier dashboard-first plan for this usability milestone.
- Retain only explicitly submitted new experimental conversations and selected
  corpus in the already approved experimental namespace. No existing chats,
  ordinary Soul memory, credentials or personal history are imported. Connection
  activation and its exact state root/retention remain the handoff gate.
- Use one local operator credential, supplied from a private local file, never
  in command arguments, model context, receipts or chat. A conversation identifier
  is a namespace, not authorization. This is not a multi-user deployment.
- Accept text-only linear conversations. Validate the complete supplied history
  against durable replies. Identical retries recover the same result; divergent
  edits, regeneration and history imports refuse without rewriting history.
  Explicit branching and attachments remain unsupported rather than guessed.
- Keep existing recent-context bounds explicit (at most three exchanges, further
  limited by bytes/tokens). Full transport history is evidence, not a promise
  that every previous message reaches the 4K model. No autonomous note-writing.
- Keep A21 deterministic selection available as its separate explicit CLI.
  Automatic free-form interpretation is not necessary to connect LibreChat and
  is not promoted by this work. Generated chat text is not a verified calculation.
  Do not silently substitute a model's interpreted request for the user's intent.
- Serve buffered completion/SSE only after a durable terminal reply. Partial
  tokens are not accepted answers. Client disconnect may leave only the current
  bounded foreground request completing; never a detached continuation/retry.

## Persistence and recovery contract

Primary owns transport identity, state containment, recovery and authorization.
The host adapter owns immutable per-conversation binding metadata and a separate
coordination lock around history validation plus the existing worker invocation.
The worker retains only its dedicated `store` directory. Sources/config/profile
are bound immutably; no client-provided paths, backend endpoints or tool authority.
Store initialization uses a staged directory and atomic promotion; interrupted
staging is retained and never automatically deleted. No broad cleanups.

Normal terminal results are durable before HTTP delivery. Missing/uncertain
model results must not be regenerated on retry: reconcile an already recorded
response with the existing Runtime recovery path; unresolved intent blocks for
review. Concurrent requests fail boundedly rather than queue without limit.
Store/root quotas and request ceilings refuse explicitly. Stopping the foreground
process cancels/reaps active workers; restarting is manual, with the same root.

The proposed activation is loopback-only, foreground, bounded by both a maximum
session duration (at most one hour) and request count. It requires a dedicated
quiet inference window; cooperative leases cannot exclude direct backend clients.
No service/timer, automatic model load, restart, fallback or all-day unattended
availability is created. Read-only inventory and bounded synthetic local socket
tests are in scope now; actual listener activation for LibreChat is not performed.

## Implementation and evidence

Add only A22 adapter/backend/launcher, focused verifier/qualification scripts,
synthetic configuration examples and handoff/review docs. Preserve dirty files,
all prior journal/profile formats and qualification evidence. Delegated work is
limited to the pure transport layer or tests with exact contracts; primary owns
host and persistence implementation and independent boundary review.

Required deterministic checks: authentication and origin rejection; strict JSON,
body/role/parameter bounds; model listing, errors, JSON and buffered SSE shape;
stable identities/retry/restart; complete history, edits and cross-conversation
isolation; busy/limit/failed/uncertain states; source/config drift; hostile paths,
symlinks and unsafe permissions; no model call on replay/refusal; no ordinary
memory or default service mutation. Exercise actual journal and isolated worker
boundaries rather than claiming mocks qualify them. Run affected existing
context, admission, recovery, helper and worker checks once after integration.

One bounded synthetic live-Qwen smoke window is authorized by the continued
implementation/testing request: at most six new generation calls and 10 minutes,
existing resident model only, fresh host observation, no concurrent GPU workloads
or model clients, no private inputs. Retain exact request/response and integrity
evidence; stop on admission/integrity failure. Routine deterministic repairs may
continue without new approval. Do not hide a live failure with a fixture result.

Finish with the installed LibreChat contract, exact proposed config/launch steps,
rollback/shutdown/recovery, limitations and deviations. Update the canonical
human/candidate review packets. Connection-ready requires a runnable adapter,
passing deterministic checks and stated live outcome; it does not mean LibreChat
has been connected, UI accepted, production activated, or continuity demonstrated.
