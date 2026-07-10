# Phase 55 Execution Adapter Registry

Phase 55 adds a dedicated execution adapter registry.

## Added / changed

```text
lib/soul_core/execution_adapter_registry.rb
lib/soul_core/execution_adapter_registry_assessor.rb
lib/soul_core/read_only_skill_execution_gate.rb
lib/soul_core/read_only_skill_execution_gate_assessor.rb
lib/soul_core/app.rb
docs/EXECUTION_ADAPTER_REGISTRY.md
scripts/verify-execution-adapter-registry-phase55.rb
```

## Result

Soul can expose adapter metadata and route execution decisions through a cleaner registry.
