# Phase 57 Downloads Cleanup Preview

Phase 57 enables a non-mutating cleanup preview adapter for `downloads.cleanup_plan`.

## Added / changed

```text
lib/soul_core/execution_adapter_registry.rb
lib/soul_core/execution_adapter_registry_assessor.rb
lib/soul_core/read_only_skill_execution_gate.rb
lib/soul_core/read_only_skill_execution_gate_assessor.rb
lib/soul_core/chat_responder.rb
docs/DOWNLOADS_CLEANUP_PREVIEW.md
scripts/verify-downloads-cleanup-preview-phase57.rb
```

## Result

Soul can preview Downloads cleanup candidates without exposing filenames or modifying files.
