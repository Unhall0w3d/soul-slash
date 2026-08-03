# Repository Inspect

`repository.inspect` is Soul's bounded foreground Git-evidence skill. It is
available through authenticated Chat, Voice Presence, and the application API.
It requires no Core change and performs no repository or file mutation.

## Configuration

The portable default approves only this project:

```dotenv
SOUL_REPOSITORY_INSPECT_ROOTS=project=.
```

Additional repositories require explicit ignored local configuration:

```dotenv
SOUL_REPOSITORY_INSPECT_ROOTS=project=.;notes=/absolute/path/to/repository
```

Conversation cannot enroll a repository or reveal configured paths.

## Chat and Voice requests

```text
show approved repository roots
inspect repository root project
```

Ordinary conversation about repositories, branches, commits, or Git does not
invoke inspection.

## Application operations

```text
repositories.roots
repository.inspect    root_id
```

One inspection returns the branch or detached state, HEAD, up to 100 visible
status entries, ten recent commits, and bounded staged and working-tree unified
diffs. Output identifies truncation, omitted secret-shaped paths, or withheld
credential-like content.

## Safety boundary

The repository must be an exact configured, non-symlink Git top level. Git runs
through one fixed absolute executable with argv-only commands, a five-second
deadline, no pager, external diff, text conversion, shell, hook, or network
operation. Each diff is limited to 24 KiB.

The skill provides no checkout, switch, restore, reset, clean, stage, commit,
tag, stash, merge, rebase, fetch, pull, push, configuration change, arbitrary
path access, credential collection, memory write, watcher, service, schedule,
retry, or background work. All returned content is untrusted point-in-time
reference material. Every request reaches a terminal lifecycle with
`mutation: none`.
