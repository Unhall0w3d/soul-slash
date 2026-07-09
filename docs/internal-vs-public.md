
# Internal vs Public Documentation

Soul is public for tracking and transparency, but not every generated artifact belongs in public history.

## Public-facing

Public-facing documentation should be readable by someone who did not follow the overlay sequence.

Examples:

```text
README.md
docs/SKILLS.md
docs/SECURITY_MODEL.md
docs/ROADMAP.md
docs/skills/*.md
```

Public-facing docs should avoid local paths, temporary phase chatter, machine-specific assumptions, and generated proposal details.

## Engineering-facing

Engineering-facing documentation may describe internals, phases, handlers, assessment rules, and verification assumptions.

Examples:

```text
docs/assessments/*.md
docs/workflows/*.md
docs/soul/*.md
scripts/verify-*.rb
```

Engineering docs can be public, but they should still be clean and useful.

## Local-only

Local-only content should stay ignored unless explicitly promoted.

Examples:

```text
Soul/improvement/proposals/*
Soul/runtime/*.json
Soul/artifacts/cloud_assist/*
Soul/proposals/skills/*
overlay_files/
README_*PHASE*.md
docs/overlays/README_*PHASE*.md
```

## Promotion principle

Generated artifacts become public only after explicit human review and an intentional commit.

No generated proposal, alpha skill, cloud-assist artifact, or runtime state should become public accidentally.
