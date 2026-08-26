# AletheiaUC Vault to Dev Worker Context A5 Brief

## Brief status

```text
approved_by_human_owner: 2026-08-26
implementation_authorized: yes
operation: local reviewed-vault context assembly for bounded Dev Worker requests
repository_read_authority: no additional authority
vault_read_authority: reviewed project notes only
network_authority: existing loopback Dev Worker request only
mutation_authority: none
human_merge_review_required: yes
```

## Purpose

Allow primary Codex to describe a bounded development task and project, then
have Soul deterministically assemble a small local Knowledge Vault context
packet before using the existing GPT-OSS Dev Worker. This reduces repeated
manual note selection without granting the model direct vault, repository,
shell, network, Git, test, approval, or merge access.

The initial qualified project is AletheiaUC. The assembler is project-shaped so
other reviewed project corpora may use the same bounded contract later.

## Lifecycle

```text
caller writes one bounded vault request
-> preview validates the request without invoking the model
-> assembler searches only Projects/<vault_project>
-> at most three complete notes fit within 48 KiB
-> existing Dev Worker validates the assembled context and returns its digest
-> human or primary Codex reviews the exact receipt and confirmation
-> execute rebuilds the context from current bytes
-> any changed selection or note invalidates the preview digest
-> one existing Dev Worker request returns a terminal candidate
```

No request remains running after returning control.

## Request contract

`soul.dev_worker.vault_request.v1` retains the existing request ID, purpose,
task kind, informational repository paths, closed output schema, and timeout. It
replaces caller-supplied model context with:

- `vault_project`: one reviewed directory name below `Projects/`;
- `vault_query`: at most 200 characters describing the needed local evidence.

The project name cannot contain traversal or path separators. Request files
retain the existing owner, regular-file, no-symlink, location, and size checks.

## Retrieval and assembly policy

- Search only regular UTF-8 Markdown below the exact project directory.
- Inspect no more than 500 files; each file is at most 256 KiB.
- Ignore hidden directories, Obsidian state, Git state, Trash, and symlinks.
- Require lexical task-query matches; project location alone is not relevance.
- Prefer a matching project router or index note, then deterministic score and
  relative-path order.
- Include complete notes only; never silently truncate a note.
- Select at most three notes and at most 48 KiB of rendered context.
- Return `awaiting_input` when no reviewed note fits or matches.
- Do not broaden to another project, private evidence, or online research.

The model context labels every note as untrusted evidence rather than an
instruction or authorization. The receipt contains project, query digest,
context size, and note-relative path, byte count, and SHA-256. It contains no
note content or query text.

## Privacy and trust boundary

The assembler rejects note candidates stored in customer, artifact, private,
or evidence directories and candidates that contain recognizable private host
paths. The existing Dev Worker secret scanner independently rejects an assembled
packet containing obvious credentials, private keys, tokens, or secret
assignments.

These controls are defense in depth. The vault must continue to contain only
reviewed, non-secret project knowledge. Retrieval does not make a note current,
correct, authoritative, or safe to execute.

Primary Codex must verify proposed source paths, commands, tests, interfaces,
and implementation details against the current repository. Insufficient or
conflicting local context requires a separately scoped repository inspection or
primary-source research pass.

## Command surface

```text
bin/soul dev-worker-vault preview --request-file /tmp/request.json
bin/soul dev-worker-vault execute --request-file /tmp/request.json \
  --confirmation "RUN_SOUL_DEV_WORKER <request_id>" \
  --expected-digest <preview_digest>
```

This is foreground-only. It adds no service, timer, watcher, queue, listener,
retry loop, persistence layer, memory promotion, or background continuation.

## Required deterministic verification

- project traversal and invalid request fields fail before vault access;
- symlink notes and hidden state are excluded;
- an unrelated query returns `awaiting_input` without model invocation;
- selection and context digest are deterministic for identical bytes;
- a note change after preview invalidates the execute digest;
- receipts contain path/digest/size metadata but no note content;
- private-path notes are excluded and secret-bearing assembled context fails;
- note and aggregate limits remain enforced;
- the existing Dev Worker verifier remains green;
- no new model client, network client, process primitive, listener, persistence,
  retry, or background loop exists.
