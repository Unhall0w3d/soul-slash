# Architecture

Soul/ is split into layers.

## Interface layer

Human-facing inputs and outputs:

- CLI
- future web UI
- future voice input
- future TTS output

The interface should be human-accessible and forgiving.

## Orchestration layer

The orchestration layer turns human requests into structured workflow execution.

Current pieces:

- intent routing
- workflow sessions
- selection parsing
- confirmation parsing
- response rendering

The LLM may assist with intent classification, but all results must be validated against known workflows.

## Execution layer

The execution layer contains deterministic skills.

Current skills:

- `system.status`
- `downloads.inspect`
- `downloads.cleanup_plan`
- `downloads.move_to_trash`

Execution skills should produce structured JSON and explicit verification fields.

## Reflection layer

The reflection layer turns task logs into candidate lessons/rules.

Reflection does not automatically promote durable changes.

Current flow:

```text
task log
  -> reflection candidate
  -> human review
  -> approve/reject
  -> approved rules/lessons
```

## Memory layer

Human-readable memory and rule files live under:

```text
Soul/memory/
```

Current approved rule files:

```text
Soul/memory/approved_rules.md
Soul/memory/approved_lessons.md
```
