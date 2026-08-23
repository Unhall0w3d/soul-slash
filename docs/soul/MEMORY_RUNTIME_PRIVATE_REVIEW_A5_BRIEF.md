# Memory Runtime and Private Review A5 Brief

Status: Operator-approved implementation scope, 2026-08-23

## Objective

Add one bounded foreground qualification surface for the two semantic-memory
questions left open after A4: what embedding runtime is actually available in
the selected Core, and whether retrieval behaves usefully against an explicit
owner-authored private review set.

This slice gathers evidence. It does not install, start, stop, enable, schedule,
or select a model runtime and does not mutate canonical memory.

## Approved operations

### `memory.observatory.runtime`

Return one read-only observation of the configured embedding endpoint:

- exact configured profile, protocol, and dimensions;
- endpoint reachability;
- whether the exact model is installed and currently loaded when the reviewed
  Ollama inspection API can provide that evidence;
- selected Core identity; and
- an explicit compatibility disposition.

The observation may issue bounded loopback `GET` requests only. It must not
embed probe text, load or evict a model, mutate Core selection, or invoke
`systemctl`.

Free Core must never be reported as compatible with a loaded embedding model.
Soul Core, Soul-Lite Core, Creative Core, and Dev Core remain
`qualification_required` until a separate live coexistence review approves the
exact accelerator and residency policy.

### `memory.observatory.private_review`

Run one explicit foreground retrieval evaluation using the fixed owner-private
case file:

`Soul/private/memory/retrieval_review_cases.json`

The case file is a regular non-symlink file inside the project root, at most 64
KiB, with schema `soul.memory_retrieval.private_review.v1`. It contains 1–32
cases. Each case has an opaque ID, a query of at most 500 characters, one to
eight expected approved-memory IDs, optional forbidden approved-memory IDs,
and a result limit from one to eight.

The operation may read current approved memory through the shared canonical
memory store and may call the already configured loopback embedding endpoint.
It returns only:

- case IDs and query SHA-256 digests;
- expected, forbidden, and returned memory IDs;
- per-case hit, reciprocal-rank, forbidden-hit, and abstention evidence;
- aggregate recall, reciprocal rank, forbidden-hit count, and abstention
  counts; and
- the case-file digest, current approved-memory source digest, retrieval
  profile, index availability, and terminal lifecycle state.

It must not return query text or memory content, write evaluation results,
approve, reject, supersede, forget, or promote memory, rebuild the index, or
select a winner automatically.

## Dashboard boundary

Memory Observatory may expose:

- a **Refresh runtime evidence** control for the read-only observation;
- a **Run supervised private review** control that executes the fixed bounded
  review set; and
- privacy-safe results and explicit human review guidance.

The Dashboard must not accept arbitrary paths, case JSON, model names,
endpoints, Core changes, or memory lifecycle decisions.

### Memory visualization

The read-only summary may project an original Soul-styled constellation and
lifecycle visualization. It is capped at 240 ledger nodes and 400 explicit
exact-duplicate or supersession edges. Nodes may expose only memory ID,
lifecycle state, layer, provenance kind, and timestamp. The projection must not
return memory content, create inferred relationships, animate or poll in the
background, or provide mutation controls.

## Lifecycle and bounds

Both operations terminate as `complete`, `failed`, `awaiting_input`, or
`blocked_for_human_review`. Requests use existing loopback client timeouts and
bounded response limits. No retry loop, polling, watcher, daemon, scheduled
task, background continuation, or persistent process is added.

## Explicit non-goals

- Installing or enabling an embedding service or systemd unit.
- Starting, stopping, loading, unloading, or downloading a model.
- Automatically rebuilding the disposable index.
- Automatic Core switching or lease acquisition.
- Declaring NVIDIA, AMD, or CPU coexistence safe without live evidence.
- Sending private cases or memory to a cloud endpoint.
- Changing canonical memory or treating retrieval quality as authorization.

## Acceptance

- Runtime inspection uses only bounded loopback `GET` requests and cannot load
  a model.
- Missing, malformed, remote, or incompatible configuration fails safely.
- Free Core and unqualified Core residency are described truthfully.
- Private case paths, symlinks, schema, size, IDs, counts, and text are bounded.
- Private evaluation returns no query or memory content and performs no writes.
- Existing lexical fallback, semantic Chat admission, Memory Observatory, and
  Core orchestration verifiers continue to pass.
- A human review artifact records commands, deterministic evidence, risks,
  lifecycle states, privacy behavior, and the remaining live coexistence gate.
