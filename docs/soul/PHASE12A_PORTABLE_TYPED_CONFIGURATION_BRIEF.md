# Phase 12A Candidate Brief: Portable Typed Configuration

```text
brief_status: approved
implementation_authorized: yes
human_review_required: yes
```

This Codex-drafted brief was explicitly approved by the human owner on 2026-07-14 before implementation began.

## Purpose

Create one portable, typed, source-aware configuration contract shared by Soul's CLI, conversation runtime, in-process application contracts, and future dashboard. Phase 12A replaces scattered configuration interpretation with deterministic resolution and inspection while preserving current provider environment variables and safe local behavior.

The public repository must run without the owner's IP addresses, hostnames, credentials, filesystem paths, or model aliases. Operator-specific values remain in an ignored local `.env` or process environment. The tracked `.env.example` contains documentation and safe placeholders only.

## Risk class

```text
Class 0: Read-only local or conversational
```

The runtime configuration surface reads invocation inputs, process environment, an optional project-local `.env`, and tracked defaults. It does not write local configuration. Repository implementation and documentation files are changed only as candidate source work subject to human review.

## Approved scope

Phase 12A may:

- define a canonical schema of interface-relevant settings with stable dotted keys;
- assign each setting a type, default, accepted values or range, description, behavioral effect, privacy or risk note, restart requirement, secrecy classification, primary environment name, and compatibility aliases;
- resolve values in this exact precedence order:

  ```text
  invocation-scoped CLI override
  → process environment
  → ignored project-local .env
  → tracked safe default
  ```

- parse booleans, integers, floats, strings, enumerations, URLs, ports, and project-relative paths deterministically;
- report the effective source and source key for each resolved setting;
- preserve existing provider environment names and documented compatibility aliases;
- expose read-only CLI commands to show, explain, and validate effective configuration;
- accept non-secret CLI overrides for the current invocation only;
- redact secret values from all general configuration responses, errors, logs, tests, and review artifacts;
- expose secret presence as a boolean without exposing the value;
- adapt provider selection and conversation limits to consume the typed configuration through a compatibility environment projection;
- keep existing callers that inject an environment-like hash working during the migration;
- update `.env.example` so it contains no operator-specific model alias, host, credential, or path requirement;
- add deterministic tests, documentation, roadmap status, and a human review artifact.

## Initial canonical settings

The first schema covers settings required by the current conversation runtime and the planned local interface:

```text
conversation.provider
conversation.mode
conversation.allow_cloud
conversation.max_messages
conversation.max_characters
conversation.max_tool_steps
conversation.temperature
conversation.max_output_tokens
conversation.timeout_seconds

artifact.approval_ttl_seconds
artifact.max_output_tokens

providers.local_openai.endpoint
providers.local_openai.model
providers.ollama.endpoint
providers.ollama.model
providers.cloud_openai.endpoint
providers.cloud_openai.model
providers.cloud_openai.credential_env
providers.cloud_openai.api_key

dashboard.bind_host
dashboard.port
```

`dashboard.bind_host` defaults to `127.0.0.1` and accepts loopback addresses only in Phase 12. `dashboard.port` is validated but unused until a separately approved foreground listener brief. Defining these values does not authorize opening a network listener.

Weather, download, model-installation, workflow-test, assessment-document, and deployment-service settings remain outside the initial interface schema unless implementation discovery proves one is required for compatibility. Unknown environment variables remain untouched and are not exposed through configuration inspection.

## Explicitly out of scope

Phase 12A must not:

- add a dashboard, HTTP server, socket, listener, frontend framework, service, daemon, watcher, scheduler, background process, polling loop, or automatic startup;
- write, generate, edit, delete, rename, move, chmod, or otherwise mutate the user's `.env`;
- provide a settings-save endpoint or persistent configuration editor;
- expose credentials, tokens, API keys, secret values, or the contents of unrelated environment variables;
- accept secret values through CLI arguments, because command lines may be visible to other processes or shell history;
- send configuration values to a model provider;
- probe endpoints, test credentials, download models, or start providers;
- change provider privacy classes, cloud opt-in requirements, artifact confirmation gates, or safety policy;
- make cloud conversation available merely because credentials are present;
- migrate runtime data, introduce a database, or redefine artifact, memory, approval, task, or chat storage;
- require owner-specific hostnames, IP addresses, model names, filesystem paths, or credentials;
- remove compatibility environment names before a separately reviewed deprecation phase;
- create skill-private memory or persist configuration in conversational memory.

## Inputs

Configuration resolution:

```text
Optional:
- canonical CLI overrides for non-secret settings
- process environment mapping
- explicit project root
- explicit .env path below the project root
- tracked schema defaults
```

CLI inspection:

```text
ruby bin/soul config show [--json] [--set canonical.key=value]
ruby bin/soul config explain <canonical.key> [--json] [--set canonical.key=value]
ruby bin/soul config validate [--json] [--set canonical.key=value]
```

An unknown key, duplicate CLI override, malformed `--set`, secret CLI override, invalid type, invalid range, invalid enumeration, invalid URL, non-loopback dashboard bind host, or `.env` path outside the project root terminates predictably without changing environment or files.

## Outputs

User-facing:

- a bounded list of known settings and effective redacted values;
- canonical key, effective source, source key, type, validation status, behavior, privacy/risk effect, restart requirement, and recommended default;
- a concise validation summary with actionable errors;
- explicit indication when a secret is configured, without revealing it;
- explicit indication that configuration inspection is read-only.

Structured:

```text
ok
lifecycle_state
settings
error_count
errors
source_counts
dotenv_loaded
dotenv_path (project-relative only)
mutation: none
```

General responses must not include an absolute home path, secret value, unrelated process environment, or raw `.env` content.

## Source and alias behavior

- CLI overrides use canonical dotted keys only.
- Process environment and `.env` use each setting's primary environment name or approved compatibility alias.
- The primary environment name wins over its aliases within the same source layer.
- Process environment always wins over `.env`, even when `.env` uses a primary name and the process uses an alias.
- Empty values are treated according to the setting definition; required model identifiers remain unconfigured rather than inheriting an operator-specific model.
- Alias use is reported as source metadata but does not emit a warning containing the value.
- `.env` parsing must not interpolate commands or variables, execute shell syntax, or overwrite process environment.

## Secret behavior

`providers.cloud_openai.api_key` is secret. Internally it may be resolved from the configured credential environment name for provider compatibility, but public configuration projections return only:

```text
configured: true | false
value: [REDACTED] | null
source
source_key
```

The resolver must not enumerate arbitrary environment keys named by untrusted input. The credential environment name is validated as an uppercase environment identifier. Cloud use still requires the existing explicit `conversation.allow_cloud` gate.

## Memory behavior

```text
Reads: none
Writes: none
Updates: none
Forget behavior: not applicable
```

Configuration is runtime input, not conversational memory.

## Task lifecycle

Each show, explain, or validate invocation terminates as one of:

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

Expected flow:

```text
invoked
→ parse bounded inputs
→ resolve known settings
→ validate and redact
→ complete / failed / awaiting_input / canceled / blocked_for_human_review
→ exit
```

No process remains alive after configuration output returns.

## First-use behavior

With no `.env` and no relevant process environment, `config show` and `config validate` return tracked safe defaults, identify unconfigured optional providers, and exit `complete`. They do not create `.env`, invent a model name, probe a provider, or start a process.

If `.env` exists, it is read once during invocation with bounded file size and line count. Missing `.env` is normal. Unsafe file type, excessive size, invalid encoding, or a path outside the project root returns a bounded failure without partially applying values.

## Follow-up behavior

Configuration commands are explicit foreground CLI invocations. There is no retained task awaiting a setting value and no conversational memory update.

```text
config show                 → all public settings
config explain <key>        → one public setting
config validate             → validation summary
config ... --set key=value  → invocation-only non-secret override
```

Missing `config explain` key returns `awaiting_input`. A cancel request returns `canceled` without mutation.

## Provider and dependency behavior

- No model call, endpoint probe, network request, subprocess, or new gem is required.
- Resolution is deterministic and bounded.
- Existing provider registry and conversation runtime tests must continue to accept injected hashes.
- Current compatibility names such as `SOUL_OPENAI_BASE_URL`, `OPENAI_BASE_URL`, `SOUL_MODEL_ALIAS`, `SOUL_LOCAL_MODEL`, `OLLAMA_HOST`, and `OLLAMA_MODEL` remain supported where already documented.
- Compatibility projection must not leak the cloud API key into a public result.

## Safety and confirmation gates

- Inspection and invocation-only non-secret overrides are read-only and require no mutation confirmation.
- Invalid configuration never weakens cloud opt-in, privacy filtering, artifact approvals, destructive-action protection, or human review gates.
- A configured cloud credential is not authorization to use cloud conversation.
- Dashboard binding remains loopback-only and inert in this phase.
- Secret CLI overrides are rejected before resolution.
- Configuration errors report canonical keys and reasons, not raw secret values.

## Bounded execution

- At most 64 schema settings are resolved in Phase 12A.
- `.env` is capped at 64 KiB and 512 lines.
- At most 32 invocation overrides are accepted.
- At most 100 validation errors are returned.
- No retry, polling, network access, background continuation, or recursive directory scan is allowed.

## Deterministic tests required

- safe defaults resolve without `.env`, mutation, or provider access;
- precedence is CLI override over process environment over `.env` over default;
- primary environment names beat aliases within one source layer;
- a process alias beats a `.env` primary because the process layer has higher precedence;
- booleans, integers, floats, enums, URLs, ports, and project-relative paths validate deterministically;
- invalid values fail with canonical-key errors and do not expose raw secret material;
- secret values are redacted from text and JSON output while presence remains visible;
- secret CLI overrides are rejected;
- unknown and duplicate CLI overrides fail;
- `.env` command substitution, interpolation, malformed lines, unsafe type, invalid UTF-8, excessive bytes, excessive lines, and outside-root paths do not execute or partially apply;
- inspection does not mutate the caller's process environment;
- provider registry behavior remains compatible with current primary and alias names;
- cloud use still requires explicit opt-in;
- dashboard bind validation permits loopback only and opens no listener;
- configuration commands return explicit terminal lifecycle states;
- tracked `.env.example` contains no credential or required operator-specific values;
- Phase 11A through 11D regressions pass;
- no forbidden persistent or background primitive is added.

## Local LLM evals

No local LLM evaluation is required. Phase 12A is a deterministic configuration contract and must not send configuration data to a model. Human-readable output is covered by deterministic assertions.

## Failure behavior

- Missing explain key: `awaiting_input`; no mutation.
- Unknown key or malformed override: `failed`; no partial override application.
- Invalid setting value: `failed`; report canonical key and bounded reason.
- Unsafe or excessive `.env`: `blocked_for_human_review`; apply no `.env` values.
- Missing `.env`: normal `complete` result using higher layers and defaults.
- Secret inspection: `complete` with redacted value and presence only.
- Internal schema inconsistency or duplicate environment ownership: `blocked_for_human_review`.
- Cancellation: `canceled`; no mutation.

## Logging and review

- Do not create a separate configuration event store.
- Do not log raw `.env` content, absolute home paths, secrets, CLI values, or unrelated environment variables.
- Create `docs/assessments/CONVERSATIONAL_SOUL_PHASE12A_PORTABLE_TYPED_CONFIGURATION.md` as the implementation review artifact.
- Update the canonical configuration documentation, `.env.example`, and roadmap status.

## Done criteria

- This brief is explicitly approved by the human owner.
- One canonical typed schema and resolver implement the approved precedence.
- Read-only show, explain, and validate commands are available.
- Existing provider and conversation behavior remains compatible.
- Secret and operator-specific values remain private and redacted.
- Deterministic tests and Phase 11 regressions pass.
- No local LLM or cloud provider receives configuration data.
- No listener, service, watcher, scheduler, or background behavior is added.
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
