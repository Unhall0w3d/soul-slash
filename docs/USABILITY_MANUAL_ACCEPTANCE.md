# Usability Manual Acceptance

This is the manual acceptance workflow for the Phase 63 stopping point.

## Non-mutating checks

```zsh
ruby bin/soul assess usability-milestone-closeout
ruby bin/soul assess execution-adapter-registry
ruby bin/soul assess read-only-skill-gate
ruby bin/soul chat "clean up downloads"
ruby bin/soul chat "pending approvals"
ruby bin/soul chat "move approved downloads to trash"
```

The final command must request a token rather than execute.

## Approval and dry-run checks

```zsh
ruby bin/soul chat "approve downloads cleanup preview"
ruby bin/soul chat "dry run downloads move <token>"
ruby bin/soul chat "pending approvals"
```

Expected:

```text
approval token is pending
dry-run reports would-move counts
mutation is none
token remains pending
```

## Optional real-action acceptance

This command performs a real move to desktop trash:

```zsh
ruby bin/soul chat "move approved downloads to trash <token> confirm"
```

Run it only after reviewing the dry-run.

Expected:

```text
approved candidates move to trash
token becomes used
permanent_delete is false
filenames are omitted from the normal report
execution is recorded
```

## Final repository checks

```zsh
ruby scripts/verify-usability-milestone-phase63.rb
git status --short
git log -5 --oneline
```
