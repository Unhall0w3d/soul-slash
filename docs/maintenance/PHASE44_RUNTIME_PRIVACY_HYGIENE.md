
# Phase 44 Runtime Privacy Hygiene

Phase 44 adds a privacy boundary for Soul runtime data.

## Purpose

Phase 41 and Phase 42 introduced local chat transcripts under:

```text
Soul/runtime/chats/
```

Phase 43 also reinforced that generated task and review material should remain local unless intentionally promoted.

This phase updates `.gitignore` and documents the boundary.

## Added / changed

```text
.gitignore
docs/RUNTIME_PRIVACY_HYGIENE.md
docs/maintenance/PHASE44_RUNTIME_PRIVACY_HYGIENE.md
scripts/verify-runtime-privacy-hygiene-phase44.rb
```

## Ignored paths

```text
Soul/runtime/
Soul/codex/tasks/
Soul/codex/responses/
Soul/codex/reviews/
*.soul.local
```

## Scope

This phase does not:

```text
delete runtime data
move chat transcripts
create backups
configure Proxmox
change chat behavior
change skill behavior
```

## Result

Private owner-specific Soul data is protected from accidental Git commits.
