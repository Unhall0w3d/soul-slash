
# Codex Dry-Run Review

The Codex dry-run review evaluates a proposed Codex output artifact against a handoff contract.

It does not invoke Codex. It does not apply patches. It does not modify production files.

## Commands

```bash
ruby bin/soul assess codex-dry-run-review --contract <contract.json> --response <response.json>
ruby bin/soul assess codex-dry-run-review --contract <contract.json> --response <response.json> --json
```

Aliases:

```bash
ruby bin/soul assess codex-review --contract <contract.json> --response <response.json>
ruby bin/soul assess handoff-review --contract <contract.json> --response <response.json>
```

## Expected response shape

```json
{
  "summary": "What Codex proposes.",
  "files_changed": ["lib/soul_core/example.rb"],
  "commands_to_verify": ["ruby scripts/verify-example.rb"],
  "risks": ["Risk notes."],
  "rollback": "How to revert the proposed changes.",
  "human_review_notes": "What a human should inspect."
}
```

Optional:

```json
{
  "implementation_patch": "Patch text or notes."
}
```

If patch content is present, the review warns that Phase 28 does not apply patches.

## Review checks

```text
contract JSON validity
response JSON validity
required response sections
changed files within allowed file patterns
changed files do not match forbidden file patterns
verifier command guidance exists
rollback notes exist
risk notes exist
```

## Boundaries

The review is advisory only.

It must not:

```text
invoke Codex
apply patches
modify files
read secrets
change runtime configuration
promote alpha artifacts
```

## Future phase

Phase 29 should build alpha implementation task packs that can use the handoff and dry-run review chain.
