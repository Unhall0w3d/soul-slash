# Skill Proposal Format

A Soul/ skill proposal is a review packet for a future skill.

It is not implementation.

It is not approved architecture.

It is not a merge request.

It is a candidate package for human review, and possibly later Codex implementation.

## Default location

Generated skill proposals should land under:

```text
Soul/proposals/skills/<timestamp>-<slug>/
```

This directory is ignored by default.

## Recommended files

```text
metadata.json
proposal.md
provider_response.md
review_checklist.md
sources.md
```

## metadata.json

Recommended fields:

```json
{
  "artifact_type": "skill_proposal",
  "purpose": "skill_brief_draft",
  "provider": "mistral",
  "model": "mistral-small-latest",
  "data_class": "repo_design_summary",
  "secrets_included": false,
  "private_repo_content_included": false,
  "user_memory_included": false,
  "output_mode": "review_artifact_only",
  "direct_repo_mutation": false,
  "human_review_required": true
}
```

## proposal.md

Recommended sections:

```text
Title
Purpose
User-facing behavior
Inputs
Outputs
Required config
Lifecycle states
Safety boundaries
Memory usage
Logs/artifacts
Failure behavior
Acceptance criteria
Deterministic tests
Local LLM behavioral evals
Reflection candidates
Human review checklist
```

## review_checklist.md

Recommended checklist:

```text
- [ ] Scope is bounded.
- [ ] No persistent/background behavior unless explicitly approved.
- [ ] No direct cloud mutation of repo files.
- [ ] No secrets transmitted.
- [ ] Memory usage is shared and justified.
- [ ] Failure states are predictable.
- [ ] Terminal states are defined.
- [ ] Tests are identified.
- [ ] Human approval is required before implementation.
```

## sources.md

Use this when the proposal depends on source material.

If no source material was supplied, write:

```text
No source bundle supplied. This proposal is unguided draft analysis, not sourced research.
```

Yes, we are making the model admit when it is just making educated fog. Progress.
