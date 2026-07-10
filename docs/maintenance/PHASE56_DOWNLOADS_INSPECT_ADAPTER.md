# Phase 56 Downloads Inspect Adapter

Phase 56 enables a safe read-only adapter for `downloads.inspect`.

## Added / changed

```text
lib/soul_core/execution_adapter_registry.rb
lib/soul_core/execution_adapter_registry_assessor.rb
lib/soul_core/read_only_skill_execution_gate.rb
lib/soul_core/read_only_skill_execution_gate_assessor.rb
docs/DOWNLOADS_INSPECT_ADAPTER.md
scripts/verify-downloads-inspect-adapter-phase56.rb
```

## Result

Soul can inspect Downloads metadata without leaking filenames or modifying files.
