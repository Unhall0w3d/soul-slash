# Fundamental Files Inspect A1 Review

Date: 2026-08-02

Branch: `codex/fundamental-files-inspect-a1`

Status: human-approved; merge authorized

## Implementation

- one deterministic `FileInspectionService` owns configured-root parsing,
  ancestry validation, path normalization, bounded list/stat/read behavior,
  safe file open, secret screening, lifecycle, and non-mutation metadata;
- the application contract exposes `files.roots`, `files.list`, `files.stat`,
  and `files.read`;
- exact Chat patterns route through `FileInspectionChatControls`, which is also
  the shared deterministic response path used by Voice Presence;
- the modern `inspect-files` package documents trigger and authority behavior;
- registry, invocation, operator capability, setup, Skills, and tracker records
  describe the same boundary.

## Files changed

```text
.env.example
Makefile
Soul/skills/files/inspect-files/
Soul/skills/registry.yaml
config/invocation_catalog.yaml
config/operator_capability_catalog.yaml
config/project_tracker_seed.json
docs/SKILLS.md
docs/assessments/FUNDAMENTAL_FILES_INSPECT_A1_REVIEW.md
docs/guides/INVOCATION_GUIDE.md
docs/skills/FILES_INSPECT.md
docs/soul/CURRENT_STATE.md
docs/soul/FUNDAMENTAL_FILES_INSPECT_A1_BRIEF.md
lib/soul_core/application_contract.rb
lib/soul_core/application_facade.rb
lib/soul_core/chat_responder.rb
lib/soul_core/conversation_orchestrator.rb
lib/soul_core/file_inspection_chat_controls.rb
lib/soul_core/file_inspection_service.rb
scripts/verify-fundamental-files-inspect-a1.rb
```

## Deterministic validation

```text
ruby scripts/verify-fundamental-files-inspect-a1.rb
17 checks passed

python "${CODEX_HOME:-$HOME/.codex}/skills/.system/skill-creator/scripts/quick_validate.py" Soul/skills/files/inspect-files
Skill is valid

make verify-invocation-catalog
15 checks passed

make verify-operator-capability-catalog
9 checks passed

make verify-skill-studio-conversation
10 checks passed

make verify-local-search
A1 and A2 passed

make verify-project-timeline
10 checks passed

ruby scripts/verify-phase12b-in-process-application-api.rb
candidate-ready; shared Chat and prior application regressions passed

make test-soul
passed

git diff --check
passed
```

The focused verifier covers configured-root privacy, bounded list, exact stat,
text read and digest, unknown roots, absolute paths, traversal, hidden and
secret-bearing names, symlinks, binary content, oversize content, credential
content, non-mutation, exact Chat routing, ordinary-conversation restraint,
shared Chat response, and application-envelope behavior.

## Local LLM eval

Not used. This candidate is a deterministic authority and filesystem boundary;
model output is not suitable validation for it.

## Known weaknesses

- semicolons cannot appear in configured paths;
- uncommon text formats require explicit allowlist review;
- conservative credential screening may reject a file that contains token-like
  examples; and
- natural spoken variants outside the exact request grammar await convenient
  live use, but Voice Presence uses the same tested Chat handler.

## Human review

Confirm root configuration, path and secret failure behavior, ordinary-chat
restraint, useful rendering, and the absence of mutation or persistence before
accepting the candidate.

## Human review outcome

- Outcome: approved
- Reviewer: human owner
- Date: 2026-08-02
- Decision: accept the bounded `files.inspect` vertical slice as presented.
- Required changes: none
- Scope note: the remaining Fundamental Skill Cohort A1 skills retain their own
  implementation and human-review gates.
