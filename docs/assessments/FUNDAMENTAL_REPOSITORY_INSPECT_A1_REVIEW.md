# Fundamental Skill Cohort A1 — Repository Inspect Review

Date: 2026-08-02

Branch: `codex/fundamental-repository-inspect-a1`

Status: human-approved; merge authorized

## Implementation

`RepositoryInspectionService` owns all repository authority and Git execution.
`SOUL_REPOSITORY_INSPECT_ROOTS` declares at most eight ID-to-path mappings; the
portable default is `project=.`. A selected path must be an existing,
non-symlink directory and the exact Git top level.

Inspection runs only fixed absolute, argv-only read commands for repository
identity, HEAD, branch, porcelain status, recent log, staged diff, and
working-tree diff. Paging, color, external diff, text conversion, optional
locks, and configured filesystem monitoring are disabled. Each command has a
five-second deadline and bounded captured output.

Chat and Voice Presence share two exact forms: list approved repository IDs or
inspect one named ID. The application contract exposes `repositories.roots`
and `repository.inspect` over the same service.

## Authority and privacy

Conversation cannot enroll or reveal a repository path. The skill cannot use
an arbitrary path or invoke checkout, switch, restore, reset, clean, stage,
commit, tag, stash, merge, rebase, fetch, pull, push, hooks, a shell, or a
network-capable Git operation.

Status returns at most 100 visible paths and omits secret-shaped paths. Each
diff returns at most 24 KiB, excludes secret-shaped pathspecs, and is withheld
if unsafe UTF-8 or high-confidence credential material remains. Commit metadata
and diffs are explicitly untrusted, point-in-time reference material.

## Deterministic evidence

The focused verifier creates an actual temporary Git repository, commits one
fixture, leaves separate staged and working-tree changes, inspects it, and
proves HEAD and porcelain status remain byte-for-byte unchanged. Injected
command results additionally cover exact argv, result caps, secret omission,
credential and invalid-text withholding, command timeout, root mismatch,
symlink rejection, exact conversational routing, application envelopes, and
ordinary-conversation restraint.

## Results

```text
make verify-fundamental-repository-inspect
19 checks passed

quick_validate.py Soul/skills/repositories/inspect-repository
Skill is valid

make verify-invocation-catalog
15 checks passed

make verify-operator-capability-catalog
passed

make verify-fundamental-files-inspect
17 checks passed

make verify-fundamental-network-diagnose
19 checks passed

Chat intent and interaction-boundary verifier
35 checks passed

make test-soul
passed

documentation registry refresh verifier
passed

assistant skill catalog verifier
passed

Phase 12B in-process application API verifier
candidate-ready

Project Timeline A1 verifier
passed

Skill Studio conversation verifier
10 checks passed

live project smoke
lifecycle: complete
branch: codex/fundamental-repository-inspect-a1
Chat: complete
mutation: none
before/after porcelain status: unchanged
```

## Known weaknesses

- exact natural-language grammar is intentionally narrow;
- large repositories may reach the command deadline;
- untracked content, submodules, upstream divergence, tags, remotes, and
  per-file history are not inspected;
- credential-pattern matching may conservatively withhold example material;
  and
- visible evidence is retained in the local requesting transcript.

## Memory and lifecycle

No memory key, private store, cache, or index is added. Requests terminate as
`complete`, `awaiting_input`, `failed`, or `blocked_for_human_review`; the
shared application cancellation path remains available. Mutation is always
`none`.

## Human review

The Operator approved this candidate on 2026-08-02 after reviewing repository
authority, fixed argv, extension-point suppression, result bounds, privacy
behavior, conversational restraint, and the absence of mutation, networking,
persistence, retries, or background work.
