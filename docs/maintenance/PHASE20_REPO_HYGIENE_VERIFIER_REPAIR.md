
# Repo Hygiene Phase 20 Verifier Repair

This repair updates the phase 20 verifier.

## Why

The initial verifier was too strict in two places:

```text
.env.example
docs/overlays/README_*REPAIR*.md
```

`.env.example` is intentionally tracked.

Some existing `docs/overlays/README_*REPAIR*.md` files may already be tracked. Phase 20 should warn about them and leave the decision to the curation phase instead of failing hygiene verification.

## Behavior after repair

The verifier now:

```text
allows tracked .env.example
warns on tracked overlay README phase/repair notes
still fails tracked runtime JSON
still fails tracked generated proposal artifacts
still fails tracked root phase README files
still fails tracked patch/repair scripts
```

## Scope

This repair changes only:

```text
scripts/verify-repo-hygiene-phase20.rb
docs/maintenance/PHASE20_REPO_HYGIENE_VERIFIER_REPAIR.md
```
