
# Phase 24 Verifier Repair

This repair updates the phase 24 feature direction verifier.

## Issue

The phase 24 verifier called the phase 23 curation summary verifier.

During phase 24 application, the phase 24 verifier itself is still untracked:

```text
scripts/verify-feature-direction-phase24.rb
```

The phase 23 verifier correctly reports untracked `verify-*` files as curation candidates, so the phase 24 verifier failed before the user could stage and commit the new verifier.

This was a sequencing issue, not a feature direction failure.

## Fix

The phase 24 verifier now checks repo curation directly and allows only the current phase verifier as a temporary untracked candidate.

It still fails on:

```text
tracked overlay notes
unexpected untracked review candidates
generated/local leftovers
feature direction command failures
missing docs
missing source files
```

## Scope

This repair changes only:

```text
scripts/verify-feature-direction-phase24.rb
docs/maintenance/PHASE24_FEATURE_DIRECTION_VERIFIER_REPAIR.md
```
