
# Codex Handoff Contract

The Codex handoff contract defines the minimum structure required before Soul asks Codex or another external coding model to produce implementation work.

This contract is advisory and local. It does not invoke Codex. It does not send repo context anywhere. It does not write implementation output.

## Commands

```bash
ruby bin/soul assess codex-handoff
ruby bin/soul assess codex-handoff --json
ruby bin/soul assess codex-handoff --task model_suitability_registry
ruby bin/soul assess codex-handoff --task model_suitability_registry --write --json
```

Aliases:

```bash
ruby bin/soul assess handoff-contract
ruby bin/soul assess codex-contract
```

## Required fields

```text
task
repo_context
allowed_files
forbidden_files
acceptance_criteria
verifier_expectations
security_boundaries
output_format
rollback_notes
```

## Codex model recommendation

```text
gpt-5.5 medium
```

## Boundaries

Codex may produce:

```text
patch suggestions
bounded implementation drafts
verifier suggestions
documentation drafts
risk notes
rollback notes
```

Codex must not:

```text
read or persist secrets
enable providers
modify runtime configuration
register skills
promote alpha artifacts
delete files outside explicit paths
install dependencies without approval
change files outside the allowed file list
```

## Write mode

`--write` writes a contract JSON under:

```text
Soul/codex/handoffs/
```

This is generated handoff material and should remain local by default unless deliberately reviewed and committed.

## Future phase

Phase 28 should add a Codex dry-run review loop that ingests a proposed Codex response as an artifact and assesses it against this contract.
