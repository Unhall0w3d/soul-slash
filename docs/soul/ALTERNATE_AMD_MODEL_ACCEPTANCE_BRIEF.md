# Alternate AMD Model Acceptance Brief

## Brief status

```text
approved
implementation_authorized: yes
temporary_loopback_listener_authorized: yes
live_provider_cutover_authorized: no
```

## Objective

Evaluate the verified Ministral 3 14B Q4_K_M candidate through Soul's real
OpenAI-compatible provider contract on the RX 6900 XT while the existing
NVIDIA/Qwen3-8B production runtime remains available and unchanged.

This slice decides whether Ministral is ready to become an AMD runtime profile.
It does not make that profile primary.

## Explicit temporary-listener authorization requested

The evaluation harness may start exactly one child `llama-server` process with
these bounds:

```text
binary: version-pinned b9851 Vulkan build selected by exact absolute path
model: digest-verified Ministral 3 14B Q4_K_M selected by exact absolute path
device: Vulkan0 / RX 6900 XT
host: 127.0.0.1 only
port: 18082 only
alias: soul-ministral-3-14b-candidate
maximum child processes: 1
startup timeout: 180 seconds
per-request timeout: 60 seconds
total harness timeout: 1,200 seconds
background continuation after harness exit: prohibited
```

The child is part of one foreground evaluation invocation. The harness owns its
PID, installs cleanup in `ensure`, requests graceful termination only after
slots are idle, waits a bounded interval, and reports failure if cleanup cannot
be verified. It must never adopt, stop, signal, or inspect an unrelated PID.

## Approved implementation scope requested

- Add a foreground-only Ruby acceptance harness using argv-based process launch
  without a shell.
- Require exact expected SHA-256 values for the candidate model and server
  binary before process launch.
- Refuse to start if port `18082` is already occupied.
- Bind the candidate server to loopback and never expose it through Caddy, LAN,
  firewall configuration, a service unit, or provider `.env` changes.
- Confirm the existing production endpoint before, during, and after the pilot.
- Build an in-memory provider definition pointing only to the alternate port.
- Use temporary chat, memory, lease, artifact, and operation roots.
- Disable cloud fallback and omit private chats, memory, credentials, artifacts,
  repository content, and user files from prompts.
- Run a bounded Soul-specific matrix covering persona, multi-turn continuity,
  clarification, execution honesty, capability gaps, structured JSON, and a
  small tool-selection proposal fixture without executing model-proposed tools.
- Measure startup time, request latency, prompt/output token counts when
  reported, throughput, slot-idle recovery, and clean shutdown.
- Record GPU memory only if an already-installed bounded read-only host utility
  exposes it; absence of such a utility is reported as `not_collected`.
- Retain only synthetic transcript excerpts, hashes, measurements, and review
  observations in the repository review artifact.

## Explicitly excluded

- No change to `.env`, configured provider endpoint, model alias, dashboard
  configuration, Caddy, UFW, or either existing user service.
- No new systemd unit, service, daemon, timer, watcher, scheduled task, cron job,
  persistent listener, auto-start behavior, or background polling loop.
- No automatic model selection, failover, load, unload, or profile switching.
- No production NVIDIA model stop, restart, unload, or file replacement.
- No AMD driver, Vulkan package, Ollama, ROCm, model, or dependency installation.
- No cloud provider or Internet request during evaluation.
- No split inference across AMD and NVIDIA.
- No tool execution, host mutation, memory promotion, proposal approval, skill
  creation, or artifact write based on model output.
- No vision projector test in this slice unless separately approved after the
  text/runtime gate passes.

## Evaluation matrix

### Conversation and persona

- the eight-turn live persona matrix;
- one twenty-turn synthetic continuity thread;
- concise success, supportive tone, self-description, and practical-first voice;
- no canned closing, fabricated intimacy, embodiment, or consciousness claim.

### Operational judgment

- missing inspection requests clarification rather than invention;
- thinking and doing remain distinct;
- unavailable tools do not become fabricated execution;
- hypothetical limitations do not create capability-gap intake;
- one actual synthetic missing capability is classified as a candidate without
  implementing or approving anything.

### Structured output

- exact object schema with required fields and no additional properties;
- array output through the general JSON-value artifact schema;
- one proposal-shaped schema containing lifecycle, risk, memory, tests, and
  human-gate fields;
- JSON parses directly with no fence normalization.

### Tool selection

The model receives three synthetic tool definitions and must select at most one.
The harness records the proposed tool call but does not execute it. Invalid,
multiple, or unauthorized proposals fail the behavioral check without mutation.

### Runtime behavior

- startup reaches `/health` within the fixed timeout;
- `/slots` becomes idle after each request;
- one deliberately short client timeout is observed, followed by bounded idle
  recovery before any shutdown attempt;
- graceful termination leaves port `18082` closed;
- production endpoint `127.0.0.1:8082` remains healthy throughout.

## Lifecycle

```text
validate_inputs
→ verify_digests
→ verify_production_health
→ verify_port_free
→ start_candidate
→ await_health
→ evaluate
→ await_idle
→ terminate_candidate
→ verify_cleanup
→ complete / failed / canceled / blocked_for_human_review
```

Every path terminates. No process remains alive waiting for input or review.

## Failure and cleanup behavior

- Validation or digest failure: `blocked_for_human_review`; no child process.
- Occupied port: `blocked_for_human_review`; never signal the occupant.
- Startup or health timeout: terminate only the owned child and report `failed`.
- Request failure: record the bounded failure, wait for owned server slots to
  become idle, then continue cleanup.
- Slot state unknown or still busy: do not send a normal shutdown signal until
  the bounded idle check completes; report the condition explicitly.
- Graceful termination timeout: report `blocked_for_human_review` with owned PID
  and evidence. A force-kill is not authorized by this brief.
- Production endpoint degradation: stop the pilot after candidate idle recovery,
  preserve the production service, and report `blocked_for_human_review`.

## Deterministic tests required

- refuses wrong binary/model digest;
- refuses non-loopback host, different port, or occupied port;
- uses argv launch with no shell interpolation;
- owns and cleans only its child PID;
- cleanup runs after success, exception, timeout, and interrupt;
- refuses cloud providers and private input fixtures;
- caps turns, bytes, time, retries, and retained excerpts;
- never writes provider configuration or service files;
- structured responses parse against their schemas;
- model-proposed tools are recorded but never executed;
- production health is checked without controlling the production service;
- existing model-runtime lease, conversation, artifact, authentication, and
  Phase 13 aggregate regressions remain passing.

## Completion artifact

Create:

```text
docs/assessments/ALTERNATE_AMD_MODEL_ACCEPTANCE.md
```

It must record implementation, files changed, commands, deterministic results,
local-model results, measurements, known weaknesses, memory keys, lifecycle
states, risk, safety/persistence checks, and a human review checklist.

## Human approval requested

Approval of this brief authorizes only the bounded implementation and temporary
foreground listener described above. It does not authorize an AMD profile,
service installation, `.env` change, dashboard switch, or production cutover.

```text
Outcome: approved
Reviewer: repository owner
Date: 2026-07-16
```
