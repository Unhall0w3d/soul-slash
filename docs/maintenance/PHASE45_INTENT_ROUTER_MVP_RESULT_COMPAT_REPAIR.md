
# Phase 45 Result Compatibility Repair

The first Phase 45 repair fixed the missing `IntentRouter::Result` constant, but the running application also had code that initialized that result with legacy-style keywords:

```text
ok
intent
parameters
source
```

The struct-based result rejected those keys, which caused:

```text
ArgumentError: unknown keywords: ok, intent, parameters, source
```

## Repair

This repair replaces the struct with a small compatibility class that accepts both:

```text
Phase 45 router fields:
id, label, confidence, skill_id, risk, confirmation_required, reason, next_step

Legacy/router-adjacent fields:
ok, intent, parameters, source
```

## Scope

No routing behavior changes.

No skill execution is added.

This only makes the result object tolerant of both calling paths.
