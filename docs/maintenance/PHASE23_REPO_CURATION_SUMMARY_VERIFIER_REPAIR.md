
# Phase 23 Verifier Repair

This repair updates the phase 23 summary verifier.

## Issue

The phase 23 verifier checks `ruby bin/soul assess repo-curation --json`.

During the apply-and-verify step, the phase 23 verifier itself is still untracked:

```text
scripts/verify-repo-curation-summary-phase23.rb
```

That made the repo-curation assessment report one untracked review candidate, causing the phase 23 verifier to fail before the user could stage and commit the verifier.

This is a verifier sequencing issue, not a repository hygiene issue.

## Fix

The phase 23 verifier now allows its own verifier file as the only acceptable temporary untracked review candidate during phase application.

It still fails on:

```text
tracked overlay notes
other untracked review candidates
generated/local leftovers
repo hygiene failure
phase 21 verifier failure
phase 22 verifier failure
missing curation status docs
```

## Scope

This repair changes only:

```text
scripts/verify-repo-curation-summary-phase23.rb
docs/maintenance/PHASE23_REPO_CURATION_SUMMARY_VERIFIER_REPAIR.md
```
