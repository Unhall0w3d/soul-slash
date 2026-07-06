# Security Model

Soul/ treats local automation as potentially dangerous.

## Core assumptions

- The LLM is useful but not trusted.
- LLM output must be validated.
- Filesystem writes require explicit workflow approval.
- Permanent deletion is not supported.
- Trash is the terminal cleanup state for current cleanup workflows.

## Risk levels

Recommended skill risk levels:

```text
read_only
write_trash
write_file
network_read
network_write
shell_exec
destructive
```

Early Soul/ should avoid:

```text
shell_exec
destructive
```

## Downloads cleanup policy

The current Downloads cleanup workflow:

1. Scans top-level entries only.
2. Considers files and top-level folders.
3. Protects project-related terms.
4. Produces a cleanup plan.
5. Requires user selection.
6. Requires final confirmation.
7. Moves approved items to Trash.
8. Treats Trash move as job complete.
9. Does not empty Trash.
10. Does not permanently delete files.

## LLM intent safety

The LLM may suggest:

```json
{
  "intent": "downloads.cleanup",
  "slots": {
    "target_path": "~/Downloads",
    "older_than_days": 30
  }
}
```

Soul/ validates:

- intent is registered
- target path is allowed
- age threshold is sane
- workflow requires confirmation
- execution skill is known
