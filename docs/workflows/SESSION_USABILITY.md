# Workflow Session Usability

## Purpose

Workflow sessions are durable state files under:

```text
Soul/workflows/sessions/
```

They let Soul continue confirmation-gated workflows across CLI invocations.

## Commands

Show the raw JSON for a workflow session:

```bash
ruby bin/soul workflow show latest
```

Show a human-readable summary and next action:

```bash
ruby bin/soul workflow status latest
```

List workflow sessions:

```bash
ruby bin/soul workflow list
```

List only active sessions:

```bash
ruby bin/soul workflow list --active
```

Plan cleanup of completed/cancelled/failed sessions:

```bash
ruby bin/soul workflow clear-complete
```

Actually remove completed/cancelled/failed session files:

```bash
ruby bin/soul workflow clear-complete --confirm CLEAR_COMPLETE
```

## Safety boundary

`workflow status`, `workflow show`, and `workflow list` are read-only.

`workflow clear-complete` is read-only unless the exact confirmation token is provided:

```text
CLEAR_COMPLETE
```

It only removes workflow session JSON files whose status is one of:

```text
complete
complete_no_action
cancelled
failed
```

It does not remove active waiting sessions.

## Verification

```bash
ruby scripts/verify-workflow-session-usability.rb
```
