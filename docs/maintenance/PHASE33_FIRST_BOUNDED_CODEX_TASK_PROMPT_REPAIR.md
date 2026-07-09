
# Phase 33 Prompt Repair

This repair updates the first bounded Codex task package after a prompt-only review.

## Issues

The first Phase 33 prompt was structurally safe but less useful than it should be.

The review found three practical issues:

```text
the response schema did not require concrete proposed documentation text
the allowed output paths were narrower than the files Codex was asked to review
the prompt used files_changed while also saying Codex must not edit files
```

## Fix

The repaired task generator now:

```text
adds proposed_documentation_change as a required response section
requires exact proposed wording or a precise replacement section
allows the documentation files Codex is asked to review
clarifies that files_changed means proposed files a human may later change
updates local review instructions to inspect usefulness, not just structure
```

## Scope

This repair changes:

```text
lib/soul_core/first_bounded_codex_task.rb
scripts/verify-first-bounded-codex-task-phase33.rb
docs/maintenance/PHASE33_FIRST_BOUNDED_CODEX_TASK_PROMPT_REPAIR.md
```

It does not invoke Codex, apply patches, or write production implementation.
