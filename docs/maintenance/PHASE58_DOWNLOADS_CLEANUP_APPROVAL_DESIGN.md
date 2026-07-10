# Phase 58 Downloads Cleanup Approval Design

Phase 58 is a design-only phase for future Downloads cleanup approval mechanics.

## Added / changed

```text
lib/soul_core/downloads_cleanup_approval_design_assessor.rb
lib/soul_core/app.rb
docs/DOWNLOADS_CLEANUP_APPROVAL_DESIGN.md
docs/USABILITY_RETARGET_BACKLOG.md
scripts/verify-downloads-cleanup-approval-design-phase58.rb
```

## Scope

This phase adds:

```text
approval stage design
approval-token safety rules
mutation boundary documentation
future execution requirements
usability backlog stopping point
assessment command
```

This phase does not add:

```text
approval token generation
downloads.move_to_trash execution
file movement
file deletion
background jobs
```

## Status

design-only

## Result

Soul has a documented safety boundary for moving from preview-only Downloads cleanup to future approval-gated mutation.
