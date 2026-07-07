# Human Review Gate

Human review is the authority boundary for Soul/.

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
memory/rule promotion
safety classification
persistence/background architecture
private-content sharing
credential setup
```

Soul/ may stage candidates. It may not self-certify them.
