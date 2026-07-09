
# Workflow Documentation

This directory contains engineering documentation for Soul workflow architecture.

Workflow docs should describe implemented and committed workflow behavior, handler contracts, routing policy, validation rules, or session behavior.

## Appropriate content

```text
workflow registry behavior
handler contract rules
runtime contract validation
workflow session behavior
promotion/review gate behavior when implemented
```

## Inappropriate content

```text
temporary overlay application notes
generated runtime workflow session JSON
local-only troubleshooting logs
one-time repair instructions
```

## Verifiers

Workflow-related `scripts/verify-*.rb` files are durable regression checks when they validate committed behavior. Keep them unless a newer verifier replaces them.
