# skill.brief.review

`skill.brief.review` uses a configured cloud LLM provider to review an existing Soul/ skill proposal.

It writes review packets under:

```text
Soul/proposals/skills/<proposal-folder>/reviews/
```

Generated proposal/review folders are ignored by default. Promote only reviewed material manually.

## Provider role

```text
skill_design_review
```

Mistral is the first supported provider.

## Direct usage

Dry-run without network:

```bash
ruby Soul/skills/skill/brief/review.rb \
  --dry-run \
  --proposal Soul/proposals/skills/<proposal-folder>
```

Mistral-backed review:

```bash
ruby Soul/skills/skill/brief/review.rb \
  --config Soul/config/cloud_providers.yaml \
  --provider mistral \
  --proposal Soul/proposals/skills/<proposal-folder>
```

You can also pass a direct proposal file path:

```bash
ruby Soul/skills/skill/brief/review.rb \
  --config Soul/config/cloud_providers.yaml \
  --provider mistral \
  --proposal Soul/proposals/skills/<proposal-folder>/proposal.md
```

## Requirements for Mistral-backed review

```text
MISTRAL_API_KEY is present in .env or shell environment
Soul/config/cloud_providers.yaml exists
cloud_llm.enabled: true
providers.mistral.enabled: true
providers.mistral.roles includes skill_design_review
cloud.providers.test passes
```

## What is sent

The provider prompt includes:

```text
proposal.md
metadata.json, if present
review_checklist.md, if present
sources.md, if present
selected Soul/ design docs under docs/soul/
```

It does not send:

```text
API keys
.env
user memory
task logs
local cloud provider config
unrelated private repo contents
```

## Output packet

Example:

```text
Soul/proposals/skills/20260707T190000Z-note-cleanup/
  proposal.md
  metadata.json
  reviews/
    20260707T191000Z-skill-brief-review/
      metadata.json
      review.md
      provider_response.md
      prompt.md
      sources.md
```

## Expected recommendation labels

The review should use exactly one:

```text
ready_for_human_review
needs_revision
blocked_for_human_review
```

It must not use:

```text
approved
merged
accepted
safe
```

The cloud model gets to critique, not wear a tiny judge robe.

## Review focus

The review should check:

```text
scope creep
persistent/background behavior
direct repo mutation risk
secret/private data handling
memory usage
lifecycle states
failure behavior
deterministic tests
local LLM evals
reflection candidates
human review gate
```

## Verification

```bash
ruby scripts/verify-skill-brief-review.rb
```

The verifier uses dry-run mode so it does not call Mistral.
