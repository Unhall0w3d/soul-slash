# Workflow Handler Contract Enforcement Phase 9

Phase 8 documented the handler contract.

Phase 9 adds reusable validation.

Checks include:

- handler existence
- required run method
- optional intent ownership
- optional response ownership
- contract metadata visibility

Verification:

```bash
ruby scripts/verify-workflow-contract-enforcement-phase9.rb
```

Future phases can wire this validator into application startup and CI.
