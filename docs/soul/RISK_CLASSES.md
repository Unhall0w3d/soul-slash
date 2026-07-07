# Soul Risk Classes

Every skill should have a risk classification in its design brief and review artifact.

Risk class determines required gates, tests, confirmations, and review expectations.

## Class 0: Read-only local or conversational

The skill reads local non-sensitive state, answers a question, summarizes available context, or performs no external lookup.

Examples:

- System status summary
- Local configuration inspection
- Skill help text

Requirements:

- Deterministic tests where practical
- Bounded runtime
- Clean failure behavior

## Class 1: Read-only external lookup

The skill performs external data lookup but does not write remote state or modify local state except approved logs, task state, memory, or reflection.

Examples:

- Weather lookup
- Public documentation lookup
- Package version lookup

Requirements:

- Provider failure handling
- Timeouts
- Deterministic tests using fixtures/mocks where practical
- Local LLM evals for intent behavior where relevant
- Memory documentation if durable context is used

## Class 2: Local state write, non-destructive

The skill writes local files, logs, config drafts, generated artifacts, task state, or memory. It does not delete, move, overwrite, or alter user data without explicit approval.

Examples:

- Create a draft config file
- Save a report
- Store default location after user provides it

Requirements:

- Clear output path
- No silent overwrite unless approved
- Tests for path behavior
- Review artifact documenting files written

## Class 3: Local user-data modification

The skill moves, renames, edits, archives, or otherwise changes user-owned data.

Examples:

- Downloads cleanup moving files to Trash
- Renaming batches of files
- Updating local project files

Requirements:

- Planning and execution split
- Verified plan required
- Explicit confirmation required
- Dry-run or preview where practical
- Logs of all changed paths
- Restore or rollback visibility where practical
- No permanent deletion unless separately approved

## Class 4: External write/action

The skill changes state outside the local machine.

Examples:

- Send email
- Create calendar event
- Modify a ticket
- Post to an API

Requirements:

- Explicit target/action preview
- Confirmation where appropriate
- Audit log
- Provider error handling
- Human review before new external-action skills are trusted

## Class 5: Privileged, destructive, persistent, or security-sensitive

The skill requires elevated privileges, persistent background execution, service installation, security-sensitive actions, destructive actions, credential handling changes, or privileged system modification.

Examples:

- Installing a service
- Creating a scheduled task
- Running as root/admin
- Permanent deletion
- Modifying firewall rules
- Background monitoring

Requirements:

- Explicit human-authored approval in the brief
- Dedicated review
- Dedicated tests
- Clear rollback plan
- No Codex self-approval

By default, Soul skills must not enter Class 5 behavior.
