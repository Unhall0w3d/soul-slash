# Codex–Soul Dev Worker A0 Brief

## Brief status

```text
approved_by_human_owner: 2026-08-01
implementation_authorized: yes
local_model: gpt-oss:20b
codex_native_subagent: no
repository_write_authority: no
git_authority: no
network_authority: loopback_ollama_only
human_merge_review_required: yes
```

## Purpose

Expose Soul's reviewed GPT-OSS Dev runtime as one bounded foreground reasoning
worker that a primary Codex agent may invoke. Soul receives an exact
parent-prepared context packet and returns structured analysis, critique, or
candidate unified-diff text. Codex remains the task owner and retains every
tool, repository write, test, safety, approval, Git, and merge decision.

This is not a Codex-native subagent model registration. Codex does not support
selecting the local Ollama model through its `model` configuration. A
project-local Codex skill documents how to invoke Soul's foreground CLI.

## Request lifecycle

```text
parent selects bounded context
-> preview validates request, context digest, output schema, and risk class
-> preview returns exact request digest and confirmation phrase
-> execute revalidates the unchanged request and confirmation
-> one Dev lease and one GPT-OSS request
-> structured candidate result and runtime receipt
-> terminal return to the primary Codex agent
```

Every invocation terminates as one of:

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

## Request contract

One `soul.dev_worker.request.v1` JSON object contains:

- `request_id`: bounded stable identifier;
- `purpose`: concise parent-owned task intent;
- `task_kind`: `analyze`, `critique`, or `draft_patch`;
- `repository_relative_paths`: informational paths selected by Codex;
- `parent_supplied_context`: the only repository or evidence content Soul may
  inspect, capped at 256 KiB;
- `expected_context_sha256`: exact digest of that context;
- `output_schema`: bounded JSON Schema for the candidate result;
- `timeout_seconds`: 1 through 300 seconds.

Request files must be regular non-symlink files below the repository or `/tmp`,
owned by the invoking user, and within the request-size cap. Repository paths
must be relative, traversal-free, and must not identify known secret stores.

The adapter rejects obvious credential material such as private keys, bearer
tokens, passwords, API keys, and secret assignments. This heuristic is a
defense in depth; Codex must not place secrets or private environment values in
the context packet.

## Task classes

| Task | Classification | Allowed output |
| --- | --- | --- |
| `analyze` | `read_only` | Structured evidence or synthesis |
| `critique` | `read_only` | Structured review findings |
| `draft_patch` | `write_candidate` | Unified-diff text only; never applied by Soul |

`draft_patch` output schemas must require a bounded `patch` string. Model text
does not authorize application of that patch.

## Authority boundary

Soul Dev Worker has no:

- repository reader or filesystem writer;
- shell, package, host-mutation, or arbitrary process tool;
- external network client;
- Git, commit, push, pull-request, merge, or release authority;
- safety classification or human-approval authority;
- automatic retry, repair loop, background continuation, daemon, watcher, or
  scheduled task.

The existing `DevCoreTaskOrchestrator` owns the lease and Core behavior. Dev
Core keeps GPT-OSS resident. A scoped eligible Core invocation starts the
runtime for the exact request and releases it at the terminal state. Creative
and Free Cores remain blocked by the existing policy.

## Result and receipt

The result records:

- request ID, task kind, purpose, classification, and context digest;
- structured candidate output;
- provider, model, duration, selected/borrowed Core behavior, placement, and
  model digest through the existing runtime receipt;
- creation timestamp and terminal lifecycle state;
- `mutation: none`.

No request context or secret value is copied into the receipt.

## Codex and Spark roles

- Primary Codex owns architecture, delegation, context selection, validation,
  file edits, tests, Git, and final reporting.
- Spark remains a native Codex subagent for fast repository exploration and
  small reversible implementation tasks with inherited Codex tools.
- Soul is a local tool-less worker for private bounded reasoning, structured
  critique, and candidate drafting.

The primary agent must inspect Soul output against source evidence. Soul output
must never be treated as proof that a command ran, a file changed, a test
passed, or a safety gate was satisfied.

## Required deterministic verification

- malformed, oversized, traversal, secret-bearing, or digest-mismatched
  requests fail before model invocation;
- preview performs no model or Core mutation;
- execute requires the exact request digest and confirmation phrase;
- only the three approved task kinds are accepted;
- output schema complexity is bounded and additional properties are disabled;
- `draft_patch` requires a bounded patch property and is classified
  `write_candidate`;
- provider failure and malformed structured output terminate visibly;
- successful results contain no supplied context and record the runtime receipt;
- CLI input remains file-bounded and produces JSON-only envelopes;
- no new persistence, listener, worker queue, retry loop, or memory store exists.

## Human review checklist

- [x] Analyze and critique requests produce useful bounded results.
- [x] Candidate patch text is never applied automatically.
- [x] Soul output is materially useful compared with the supplied evidence.
- [x] Spark and Soul delegation roles remain distinct in live use.
- [x] Scoped work restores the starting Core and selected Dev work stays resident.
- [x] No secret or private environment value appears in a receipt.
- [x] Primary Codex validation remains mandatory.
