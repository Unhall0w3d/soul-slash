# Soul/ Intent + Workflow overlay

This overlay adds the first natural-language workflow command:

```bash
ruby bin/soul do "cleanup files in my downloads folder older than 30 days"
```

Current scope is intentionally narrow:

- recognizes Downloads cleanup requests
- extracts `older than X days`
- runs `downloads.cleanup_plan`
- presents the Markdown plan
- writes a workflow state file
- stops before execution

It does not move files from natural language yet.

Execution remains explicit through:

```bash
ruby bin/soul skill downloads.move_to_trash -- --latest-plan --execute --confirm MOVE_TO_TRASH
```

## Commands

```bash
ruby bin/soul do "cleanup files in my downloads folder older than 30 days"
ruby bin/soul do "clean up downloads older than 7 days"
ruby bin/soul workflows
ruby bin/soul workflow show latest
```

## State files

Workflow state files are written to:

```text
Soul/workflows/pending/
```

The workflow state records:
- original user text
- parsed intent
- extracted parameters
- skill run result
- task log path
- recommended next commands
