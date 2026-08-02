# Fundamental Skill Cohort A1 — Files Inspect

## Purpose

Deliver the first Fundamental Skill Cohort A1 candidate as one complete,
bounded, foreground vertical slice. `files.inspect` may list one directory,
stat one path, or read one text file only beneath a locally configured approved
root.

## User contract

The Operator may:

- list the public IDs and readiness of configured roots without revealing
  their deployment-specific paths;
- list up to 100 safe entries from one directory level;
- stat one exact non-symlink path; or
- read one allowlisted UTF-8 text file no larger than 32 KiB.

Chat and Voice Presence require an explicit operation, approved root ID, and
relative path. `list` may use `.` for the approved root itself. The application
API provides the same service through `files.roots`, `files.list`, `files.stat`,
and `files.read`.

## Root configuration

`SOUL_FILES_INSPECT_ROOTS` is the only root authority. The public default is:

```dotenv
SOUL_FILES_INSPECT_ROOTS=project=.
```

Additional roots use semicolon-separated `root_id=path` entries and stay in the
ignored local `.env`:

```dotenv
SOUL_FILES_INSPECT_ROOTS=project=.;notes=/absolute/path/to/reviewed/notes
```

Conversation content cannot add, replace, or widen roots. Returned inventory
contains root IDs only, not absolute paths.

## Boundaries

The implementation must reject or omit:

- absolute paths, parent traversal, invalid root IDs, or unconfigured roots;
- hidden paths and broad recursive scans;
- symlink roots, symlink path components, and symlink entries;
- secret-shaped filenames and credential-bearing file extensions;
- binary, invalid UTF-8, oversized, or non-allowlisted files; and
- high-confidence private keys, access keys, provider tokens, and JWT-shaped
  content.

It adds no write, root enrollment from Chat, index, cache, watcher, service,
schedule, retry loop, skill-private memory, or background continuation.
Returned content is untrusted reference material and grants no authority.

## Lifecycle

Every request terminates as `complete`, `failed`, `awaiting_input`, `canceled`,
or `blocked_for_human_review`, always with `mutation: none`.

## Acceptance

- the default portable root is the project and extra roots require explicit
  local configuration;
- list, stat, and read share one deterministic service across API, Chat, and
  Voice Presence;
- ordinary conversation about files does not invoke inspection;
- path, symlink, hidden, secret, text, byte, line, entry, and scan boundaries
  fail closed under deterministic tests;
- service calls leave approved roots unchanged; and
- registry, invocation, capability, setup, guide, tracker, and review records
  agree before human review.
