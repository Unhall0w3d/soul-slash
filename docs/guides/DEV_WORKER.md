# Soul Dev Worker

Soul Dev Worker exposes the local GPT-OSS 20B Dev runtime as a bounded,
foreground reasoning assistant for primary Sol. It is not a Codex-native
subagent and it does not inherit Codex tools.

Use it when Codex has already selected a small, non-secret evidence packet and
wants structured analysis, critique, or candidate unified-diff text. Use a
native Codex subagent when the task requires repository exploration or a
tool-using implementation. Spark, Luna, and Terra routing is defined in
[Codex Native Subagents](CODEX_SUBAGENTS.md). Keep architecture, security, credentials,
privileged or destructive work, final edits, tests, Git, and merge decisions
with primary Sol.

## Authority boundary

Soul receives only the exact `parent_supplied_context` in the request. Path
names are receipt metadata, not permission to inspect the repository. The
worker has no repository reader, filesystem writer, shell, external network,
Git, test, approval, or merge authority. A candidate patch is text only and is
never applied automatically.

Every request is bounded by:

- a 256 KiB context cap and exact SHA-256 digest;
- a closed, size-limited output schema;
- one of `analyze`, `critique`, or `draft_patch`;
- a timeout of 1–300 seconds;
- an exact preview digest and confirmation phrase;
- one local model request and one terminal lifecycle result.

## Prepare a request

Create a JSON file below the repository or `/tmp` using
`docs/soul/schemas/dev_worker_request.schema.json`. Compute the context digest
over the exact UTF-8 context string. Do not include credentials, `.env`
content, private keys, tokens, passwords, private memory, or unrelated user
data.

The output schema must be a closed object with
`additionalProperties: false`. A `draft_patch` request must require a bounded
`patch` string containing unified-diff candidate text.

## Preview and execute

From the repository root:

```bash
bin/soul dev-worker preview --request-file /tmp/soul-dev-worker-request.json
```

Review the classification, context digest, request digest, confirmation phrase,
timeout, and model. If the file is still exact:

```bash
bin/soul dev-worker execute \
  --request-file /tmp/soul-dev-worker-request.json \
  --confirmation "RUN_SOUL_DEV_WORKER <request_id>" \
  --expected-digest <preview_digest>
```

The result is a JSON envelope. `data.candidate` remains untrusted candidate
material. Primary Sol must verify its claims against source, decide whether
to reproduce any edit, and run the normal tests.

## Core behavior

- Selected Dev Core keeps GPT-OSS resident.
- Scoped work from Soul or Soul-Lite starts the reviewed Dev runtime for the
  exact task and releases it after the terminal result.
- Creative and Free Cores block scoped Dev work.
- A failure is visible; there is no automatic retry or background queue.

GPT-OSS uses Ollama's documented `low` thinking level for these structured
requests. Ollama does not support disabling thinking for GPT-OSS with a boolean;
named levels preserve a separate reasoning trace and a schema-constrained final
answer. Soul consumes and independently validates only the final answer.

See the approved contract in
`docs/soul/CODEX_SOUL_DEV_WORKER_A0_BRIEF.md`. Ollama's provider behavior is
documented in [Thinking](https://docs.ollama.com/capabilities/thinking) and
[Structured Outputs](https://docs.ollama.com/capabilities/structured-outputs).
