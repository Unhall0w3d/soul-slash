
# Model Suitability Policy

This document defines how Soul should decide whether local or cloud model/provider classes are appropriate for a task.

The policy is advisory. It does not enable providers, route tasks, read secrets, download models, or change runtime configuration.

## Commands

```bash
ruby bin/soul assess model-policy
ruby bin/soul assess model-policy --json
ruby bin/soul assess model-policy --task coding
ruby bin/soul assess suitability-policy --task speech-to-text --json
```

## Policy tiers

### local_only

Must remain local.

Examples:

```text
secrets
credentials
private keys
local private files
raw audio
screenshots containing private content
unredacted customer data
personal health, financial, or legal records
```

### approval_required

Cloud may be used only after explicit approval for a specific task and bounded context.

Examples:

```text
repo context
bounded coding tasks
approved screenshots
approved research synthesis
long-context reasoning over non-secret material
```

### public_or_low_risk

Cloud may be suitable when content is public, non-sensitive, and benefits from stronger external reasoning.

Examples:

```text
public documentation
public research sources
non-sensitive README drafting
public API documentation synthesis
```

### local_preferred

Local should be tried first, but approved cloud assistance may be used when quality or context demands it.

Examples:

```text
summarization
routing
routine documentation
non-sensitive long-context notes
```

## Codex boundary

Recommended Codex model:

```text
gpt-5.5 medium
```

Allowed uses:

```text
bounded implementation drafts
single-task patch proposals
verifier design
documentation review
acceptance-test suggestions
risk review against explicit boundaries
```

Forbidden uses:

```text
open-ended repo cleanup
unbounded implementation
secret handling
provider activation
automatic promotion
runtime configuration changes
dependency installation without approval
file deletion without explicit paths
```

## Required Codex handoff fields

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

## Approval rules

- Cloud use requires explicit approval when repo context, screenshots, audio, private files, or long-context project material are involved.
- Local-only tasks must not be routed to cloud providers.
- Approval applies to a specific task and context, not to broad future use.
- Secrets, credentials, private keys, and raw audio are local-only by default.
- Codex handoffs must include allowed files, forbidden files, acceptance criteria, verifier expectations, and rollback notes.
- Model suitability scores are advisory and must not automatically route tasks.

## Next phase

Phase 27 should add the Codex handoff contract.
