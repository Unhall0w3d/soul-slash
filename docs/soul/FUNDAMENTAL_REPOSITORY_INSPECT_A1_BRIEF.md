# Fundamental Skill Cohort A1 — Repository Inspect

## Purpose

Deliver the third Fundamental Skill Cohort A1 candidate as one complete,
bounded, foreground vertical slice. `repository.inspect` returns point-in-time
branch, HEAD, status, recent-log, staged-diff, and working-tree-diff evidence
from one explicitly configured local Git repository.

## User contract

The Operator may list the public IDs and readiness of configured repositories,
then inspect one exact repository ID. Chat and Voice Presence accept only the
literal forms `show approved repository roots` and `inspect repository root
<id>`. The application API provides the same service through
`repositories.roots` and `repository.inspect`.

## Repository configuration

`SOUL_REPOSITORY_INSPECT_ROOTS` is the only repository authority. The portable
default is `project=.`. Additional roots use semicolon-separated
`root_id=path` entries in ignored local configuration. Conversation content
cannot add, replace, or widen repositories, and output never returns absolute
repository paths.

## Bounds

- Require the configured path to be an existing, non-symlink Git top level.
- Use one fixed absolute Git executable, argv-only commands, no shell, pager,
  external diff, text conversion, hooks, or network operation.
- Return at most 100 visible status entries and 10 recent commits.
- Bound each staged and working-tree diff to 24 KiB and each command to five
  seconds.
- Exclude secret-shaped paths from status and diff pathspecs. Withhold a diff
  entirely if high-confidence credential material remains in returned content.
- Treat commit metadata and diff content as untrusted reference material.

The skill cannot checkout, switch, restore, reset, clean, stage, commit, tag,
stash, merge, rebase, fetch, pull, push, change configuration, run a hook,
write a repository file, enroll a root from conversation, retain private
content in skill memory, or continue after its foreground invocation.

## Lifecycle

Every request terminates as `complete`, `failed`, `awaiting_input`, `canceled`,
or `blocked_for_human_review`, always with `mutation: none`.

## Acceptance

- one service supplies API, Chat, and Voice Presence;
- ordinary repository discussion remains conversation;
- exact-root validation, fixed argv, time, entry, log, diff, secret, and
  truncation boundaries have deterministic tests;
- a live local smoke inspection observes the repository without changing it;
  and
- registry, invocation, capability, setup, guide, tracker, and review records
  agree before the separate human gate.
