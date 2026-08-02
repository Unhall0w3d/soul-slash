# Inspect Files Candidate Review

## Skill

Name: `files.inspect`

Risk class: bounded read-only local file access

Branch/checkpoint: `codex/fundamental-files-inspect-a1`

Date: 2026-08-02

## Candidate status

```text
accepted
human_review_complete
```

## Implementation summary

The skill lists one directory level, stats one exact path, or reads one bounded
UTF-8 text file beneath a root explicitly approved in local configuration. The
portable default exposes only the project root. Chat and Voice Presence share
the same exact deterministic request path, while the application API exposes
the same service through `files.roots`, `files.list`, `files.stat`, and
`files.read`.

## Commands and deterministic results

See `docs/assessments/FUNDAMENTAL_FILES_INSPECT_A1_REVIEW.md` for the complete
command and result inventory.

## Local LLM eval

Not used. Request recognition, root authority, path validation, and content
limits are deterministic.

## Memory keys

None.

## Lifecycle states

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

## Persistence and safety

```text
Persistent service added: no
Daemon or watcher added: no
Scheduled task added: no
Background continuation added: no
Mutation path added: no
Skill-private durable memory added: no
Arbitrary conversational root authority added: no
```

## Known weaknesses

- Root configuration uses a compact semicolon-separated `.env` value; paths
  containing semicolons are intentionally unsupported.
- The reviewed text allowlist is conservative and may reject uncommon text
  formats until separately reviewed.
- Chat returns at most 8,000 characters even when the bounded application read
  contains more.

## Human review checklist

```text
[x] Only configured roots are available
[x] Traversal, absolute paths, hidden paths, and symlinks fail closed
[x] Secret-bearing names and high-confidence credential content fail closed
[x] Directory and file reads remain bounded
[x] Ordinary file conversation does not invoke inspection
[x] Chat, Voice Presence, API, registry, invocation guide, and docs agree
[x] No writes, index, cache, watcher, service, or private memory were added
```

## Human review outcome

```text
Outcome: approved
Reviewer: human owner
Date: 2026-08-02
Decision summary: Accepted the bounded files.inspect vertical slice as presented.
Required changes: none
```
