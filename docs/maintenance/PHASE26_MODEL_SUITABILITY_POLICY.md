
# Phase 26 Model Suitability Policy

Phase 26 tightens the policy around model suitability and prepares Soul for a safe Codex handoff contract.

## Purpose

Phase 25 added advisory model suitability rankings.

Phase 26 defines:

```text
what must remain local-only
what requires explicit approval
what low-risk public work can use approved cloud models
what Codex is allowed to do
what Codex must never do
what a future handoff package must contain
```

## New command

```bash
ruby bin/soul assess model-policy
ruby bin/soul assess model-policy --json
ruby bin/soul assess model-policy --task coding
ruby bin/soul assess suitability-policy --task speech-to-text --json
```

## Scope

Phase 26 is advisory only.

It does not:

```text
enable providers
route tasks
read secrets
download models
install packages
modify runtime configuration
invoke Codex
send context to cloud providers
```

## Recommendation

Proceed to Phase 27: Codex Handoff Contract.

Do not let Codex modify production paths until the handoff contract exists and has deterministic verification.
