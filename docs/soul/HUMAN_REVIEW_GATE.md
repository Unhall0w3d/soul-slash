# Human Review Gate

Human review is the authority boundary for consequential or protected Soul/
changes. Ordinary memory lifecycle work may proceed under the separately
approved, audited, reversible memory policy.

Candidate-complete work is not approved work.

## Review checklist

Before accepting any cloud-assisted or Codex-assisted skill, confirm:

```text
skill matches the approved brief
no persistent/background behavior was added
no safety gates were weakened
memory keys are appropriate and shared
deterministic tests pass
local LLM evals were run where applicable
cloud LLM output was used only as draft/review artifact
no secrets were exposed
no private repo data was sent without approval
failure behavior is predictable
logs/review packet are adequate
```

## Codex review packet

Codex candidate work should include:

```text
implementation summary
files changed
tests run
deterministic test results
local LLM eval prompts/results
failures encountered
known weaknesses
memory keys added/used
lifecycle states touched
risk classification
human review checklist
```

## Cloud review packet

Cloud-assisted artifacts should include:

```text
provider
model
purpose
data class
secrets included
private repo content included
source bundle used
artifact path
warnings
limitations
```

## Approval boundaries

Only the human may approve:

```text
merge readiness
protected memory, authority, safety, identity, or retention-policy changes
safety classification
persistence/background architecture
private-content sharing
credential setup
```

Ordinary memory promotion, demotion, consolidation, supersession, and logical
tombstoning do not require per-record approval when the reviewed deterministic
policy authorizes them and the audit/rollback contract is satisfied. Model
agreement alone does not confer that authority.

Soul/ may stage other candidates. It may not self-certify merge, release,
protected-memory, or persistence decisions.
