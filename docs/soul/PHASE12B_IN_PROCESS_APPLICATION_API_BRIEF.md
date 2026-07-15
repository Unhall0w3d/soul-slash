# Phase 12B Candidate Brief: In-Process Application API Contracts

```text
brief_status: approved
implementation_authorized: yes
human_review_required: yes
```

This Codex-drafted brief was explicitly approved by the human owner on 2026-07-14 before implementation began.

## Purpose

Create a versioned, interface-independent application facade over Soul's existing Chat, workspace, inbox, configuration, system-status, skill, approval, and activity services. Phase 12B gives the CLI and future dashboard one bounded request/response contract without adding HTTP transport, a listener, a frontend, or a second assistant runtime.

The facade must delegate to existing domain services. It must not duplicate conversation orchestration, artifact identity, approval authority, memory, skill execution, system collection, or configuration resolution.

## Risk class

```text
Class 2: Local state write, non-destructive
```

Read operations are Class 0. Chat creation and message exchange append local chat state; pin state and inbox seen/dismissed operations update existing bounded local operational state. The phase does not delete, overwrite, move, rename, upload, publish, execute skills, or alter user artifact bytes.

## Approved scope

Phase 12B may:

- define one `v1` in-process application facade with explicit operation names and structured envelopes;
- expose bounded Chat list, detail, message-history, create, send, pin, and unpin operations;
- route Chat send through the existing `ConversationRuntime` and persist the same user/assistant exchange used by the CLI;
- attach one caller-supplied request ID to message metadata and prevent duplicate Chat sends for the same chat and request ID;
- refactor the CLI Chat command to call the same application-level chat exchange path;
- expose existing workspace list, current-chat workspace, artifact detail, inbox list, explicit delivery, seen, and dismissed operations;
- expose manual system-status refresh through the existing bounded collector;
- expose redacted Phase 12A configuration show, explain, and validate projections;
- expose bounded read-only skill catalog, pending approval summary, and recent activity summary projections;
- return availability metadata for later Skill Studio and unified approval/activity behavior without implementing those workflows;
- use dependency injection so deterministic tests can supply fake runtimes, clocks, collectors, and stores;
- add deterministic tests, a direct local-model behavioral eval for the Chat exchange boundary, documentation, and a human review artifact.

## Explicitly out of scope

Phase 12B must not:

- add an HTTP server, TCP or Unix socket, listener, Rack/Sinatra/Rails server, browser code, HTML, CSS, JavaScript frontend, websocket, SSE stream, daemon, service, watcher, scheduler, polling loop, or automatic startup;
- add authentication, cookies, sessions, CORS, CSRF, TLS, reverse proxy, LAN binding, or remote access;
- create a second conversation runtime, artifact registry, inbox store, approval system, configuration format, memory store, system-status collector, skill registry, or execution history;
- read arbitrary filesystem paths or artifact content outside the existing Phase 11B contract;
- expose credentials, approval token values in general lists, hidden reasoning, raw exception backtraces, unrelated environment variables, absolute home paths, or private execution messages;
- add settings writes or edit `.env`;
- execute, install, generate, register, promote, or merge skills;
- approve, revoke, consume, or clear approval tokens through the general Phase 12B approval summary;
- clear, prune, export, or delete chats, activities, memory, artifacts, approvals, or history;
- add chat archiving, branching, attachments by arbitrary path, file upload, voice, streaming tokens, multi-user behavior, or remote synchronization;
- weaken provider privacy, cloud opt-in, artifact confirmation, approval, destructive-action, memory-promotion, or human-review gates;
- keep a process alive awaiting a user, model, refresh, or follow-up.

## Versioned request envelope

Every invocation accepts a bounded request shaped as:

```text
schema_version: soul.application.v1
request_id: caller-supplied stable ID
operation: explicit registered operation name
parameters: operation-specific object
context:
  interface: cli | dashboard_test | internal
  current_chat_id: optional
```

Constraints:

- request ID: 8–128 characters matching `[A-Za-z0-9_.:-]+`;
- operation: one registered exact name, not arbitrary method dispatch;
- parameters: at most 64 keys after recursive shape validation;
- string input: at most 64 KiB per field and 128 KiB total request JSON;
- nesting depth: at most 8;
- unknown operations and unknown parameters fail closed;
- no Ruby symbolization of untrusted keys and no dynamic constant or method lookup.

## Versioned response envelope

Every invocation terminates with:

```text
schema_version: soul.application.v1
request_id
operation
ok
lifecycle_state
data
errors
warnings
meta:
  generated_at
  mutation
  idempotent_replay
  limits
```

Allowed lifecycle states:

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

Responses must not contain hidden reasoning, raw backtraces, credential values, arbitrary environment data, unsafe absolute paths, or unbounded domain records.

## Initial operation registry

### Bootstrap and capability shape

```text
application.bootstrap
```

Returns schema version, available operations, configured provider summaries, redacted configuration validity, dashboard product tabs, and whether manual status has been collected during this invocation. It does not collect system status automatically.

### Chat

```text
chats.list
chats.get
chats.messages
chats.create
chats.send
chats.pin
chats.unpin
```

Bounds:

- chat list: at most 50 records;
- message history: at most 200 messages;
- chat title: at most 120 UTF-8 characters;
- one send request appends at most one user message and one assistant message;
- send message: non-empty UTF-8, at most 64 KiB;
- no delete, archive, bulk mutation, or background response.

`chats.send` must use one request ID as an idempotency key within the selected chat. A repeated request ID with the same message returns the already persisted exchange with `idempotent_replay: true`. Reuse with different content or chat identity returns `blocked_for_human_review` without another provider call or appended message.

The request ID is operational provenance, not authorization. Model output cannot change it or bypass duplicate-send protection.

### Workspace and inbox

```text
workspace.list
workspace.chat
workspace.detail
inbox.list
inbox.deliver
inbox.mark_seen
inbox.dismiss
```

These operations delegate to the Phase 11D service and retain its 50-record cap, canonical artifact identity, active/attached delivery boundary, metadata-only projection, append-only state, privacy filtering, and provenance blocking.

### System status

```text
system_status.refresh
```

Refresh is explicit and foreground-only. It invokes the existing bounded collector once, returns host identity, collection time, scope, collected facts, claims, unknowns, and command outcomes, then exits. Bootstrap and other operations must not trigger it implicitly.

### Configuration

```text
configuration.show
configuration.explain
configuration.validate
```

These operations delegate to Phase 12A. Values retain type, source, validation, privacy/risk, restart, and redaction metadata. Phase 12B does not add configuration writes or secret inputs.

### Skills, approvals, and activities

```text
skills.list
approvals.pending
activities.recent
```

- Skills are read-only registry projections capped at 100.
- Pending approvals are capped at 50 and expose stable existing approval identity, skill, status, issued/expiry time, and a bounded redacted scope summary. General lists do not expose an approval token value or full sensitive scope.
- Activities are capped at 100 and expose timestamp, skill ID, status, risk, execution, confirmation, and bounded failure classification. They do not expose original private request messages or export paths.
- Approval mutation and Skill Studio workflows remain Phase 12D/12E work.

## Chat identity and persistence behavior

The existing chat ID remains canonical. The facade does not introduce a dashboard-only conversation ID.

Chat message metadata added by this phase may include:

```text
application_request_id
application_schema_version
interface
responder mode
provider ID
bounded runtime metadata already approved for Chat
```

It must not include credentials, hidden reasoning, approval token values, full configuration, or unrelated environment data.

Duplicate-send lookup must be bounded. It may add a narrowly scoped append-only request receipt index or bounded chat-store lookup, but must not duplicate full chat content into a second private store. Any receipt state must use shared runtime infrastructure, contain only identity/digest/message IDs/terminal state, and have explicit record and file-size limits.

## Inputs and validation

Missing required parameters return `awaiting_input`. Invalid types, excessive input, unknown fields, malformed IDs, or unsupported operations return `failed`. Provenance, privacy, or idempotency conflicts return `blocked_for_human_review`.

The facade must distinguish:

```text
missing input
invalid input
unknown canonical identity
privacy/provenance conflict
dependency failure
provider failure
successful empty result
successful mutation
idempotent replay
```

Raw exceptions are converted to bounded deterministic failure envelopes.

## Memory behavior

```text
Reads: only through the existing conversation runtime where already approved
Writes/updates: only through existing shared memory controls where already approved
New durable memory keys: none
Forget behavior: unchanged
```

The application facade must not treat request context, interface state, configuration, status, or dashboard selections as durable memory.

## Task lifecycle

```text
invoked
→ validate envelope and operation
→ resolve canonical domain identities
→ execute one bounded foreground domain call
→ normalize result
→ complete / failed / awaiting_input / canceled / blocked_for_human_review
→ exit
```

No operation stays running after it returns. Provider calls retain existing timeouts and no unbounded retry. Manual status refresh retains per-command timeouts.

## First-use behavior

- Empty chats, workspace, inbox, approvals, and activities return useful empty `complete` responses.
- `application.bootstrap` reports available capabilities without creating a chat or collecting system status.
- `chats.create` creates one chat only when explicitly invoked.
- `chats.send` without a chat ID or message returns `awaiting_input` without creating state or calling a provider.
- Missing `.env` uses Phase 12A safe defaults and does not create configuration.

## Cancellation behavior

An explicit application cancellation request returns `canceled` before domain execution. It does not attempt to interrupt a completed or already-running provider call in this phase. No cancellation watcher or background task is added.

## Provider and dependency behavior

- The facade performs no provider selection of its own; Chat delegates to `ConversationRuntime`.
- Deterministic operations do not call a model.
- Chat retains configured local/cloud eligibility, privacy filtering, explicit cloud opt-in, timeout, and deterministic fallback behavior.
- The first implementation requires no new gem, database, network request, or frontend dependency.
- Tests use fake/injected dependencies except the separately labeled direct local-model behavioral eval.

## Safety and confirmation gates

- Application operation names are routing requests, not mutation authorization.
- Existing approval tokens, confirmation syntax, artifact scope binding, privacy checks, and destructive-action gates remain authoritative.
- The facade must not turn a generic UI click, model response, or prior request ID into approval.
- Read summaries of approvals do not approve or execute them.
- Inbox delivery and state changes retain Phase 11D identity and attachment checks.
- Configuration remains read-only and secrets remain redacted.
- Status remains manual and read-only.

## Deterministic tests required

- every operation returns the versioned terminal envelope;
- unknown operation, unknown parameter, malformed ID, excessive size, excessive depth, and invalid UTF-8 fail without domain calls;
- bootstrap is bounded and does not collect status, create chat state, call a provider, or expose secrets;
- empty lists complete successfully;
- chat create produces one canonical chat and no message;
- chat send appends exactly one user/assistant pair and uses the existing runtime;
- CLI and in-process Chat send use the same application exchange path;
- same request/chat/message replays without another provider call or append;
- request ID reuse with changed message or chat blocks without mutation;
- chat, message, skills, approvals, and activity results are capped and stably ordered;
- chat IDs and request IDs are validated and cannot escape storage boundaries;
- workspace/inbox operations preserve Phase 11D identity, privacy, provenance, delivery, and state behavior;
- manual status refresh invokes one bounded collection and bootstrap never refreshes it;
- configuration output remains redacted and read-only;
- approval summaries omit token values and sensitive scope content;
- activity summaries omit original private messages;
- raw dependency exceptions become bounded failures without backtraces or absolute home paths;
- complete, failed, awaiting-input, canceled, and blocked-for-review paths are represented;
- no listener, socket, service, watcher, scheduler, polling loop, or background continuation is added;
- Phase 11A–11D and Phase 12A regressions pass.

## Local LLM eval required

One direct local-model evaluation validates the Chat application boundary only:

- create a temporary Chat through the application facade;
- send a benign multi-turn message through `chats.send` using the configured local-only provider;
- confirm the response is useful, the provider call remains local, request/provider metadata is bounded, and exactly one user/assistant pair is persisted;
- replay the same request ID and confirm no second provider call or message pair;
- reuse the request ID with changed content and confirm deterministic blocking before provider invocation.

The local LLM eval validates conversation usefulness and interface continuity only. It does not approve idempotency safety, privacy, persistence, authorization, or merge readiness.

## Failure behavior

- Missing required parameter: `awaiting_input`; no domain call or mutation.
- Invalid or excessive request: `failed`; no domain call or mutation.
- Unknown chat/artifact/delivery identity: `awaiting_input` or the existing stricter domain lifecycle.
- Request-ID conflict or provenance/privacy mismatch: `blocked_for_human_review`.
- Provider failure: existing deterministic fallback or bounded `failed` result; no silent background retry.
- Status dependency timeout: bounded status result identifying unknown collection.
- Internal dependency exception: `failed` with safe class/category and no raw backtrace.
- Cancellation before execution: `canceled`; no mutation.

## Logging and review

- Reuse existing chat, artifact, inbox, approval, activity, configuration, and evidence stores.
- If an idempotency receipt index is necessary, document its exact path, permissions, schema, cap, replay behavior, and recovery limitations in the review artifact.
- Never log secrets, full approval tokens, hidden reasoning, private configuration, or raw request bodies in a new general application log.
- Create `docs/assessments/CONVERSATIONAL_SOUL_PHASE12B_IN_PROCESS_APPLICATION_API.md` as the implementation review artifact.

## Done criteria

- This brief is explicitly approved by the human owner.
- One versioned in-process facade implements the approved operation registry.
- CLI Chat uses the shared application exchange path.
- Bounds, idempotency, redaction, and lifecycle behavior are deterministic.
- Existing domain safety and identity remain authoritative.
- Deterministic tests and regressions pass.
- The direct local-model behavioral eval passes or its limitation is documented.
- No HTTP transport, listener, service, frontend, or background behavior is added.
- Documentation and review artifact are candidate-complete.
- A separate human merge decision remains required.

## Human brief approval

```text
Outcome: approved
Reviewer: human owner
Date: 2026-07-14
Approved changes: brief approved as written
Required changes: none
Implementation authorized: yes
```
