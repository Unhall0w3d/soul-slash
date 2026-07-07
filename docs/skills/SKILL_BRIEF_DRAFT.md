# skill.brief.draft

`skill.brief.draft` uses a configured cloud LLM provider to draft a review-only Soul/ skill proposal.

It writes proposal packets under:

```text
Soul/proposals/skills/
```

Generated proposal folders are ignored by default. Promote only reviewed material manually.

## Provider role

```text
skill_brief_draft
```

Mistral is the first supported provider.

## Direct usage

Dry-run without network:

```bash
ruby Soul/skills/skill/brief/draft.rb --dry-run --idea "Create a bounded note cleanup skill"
```

Mistral-backed draft:

```bash
ruby Soul/skills/skill/brief/draft.rb \
  --config Soul/config/cloud_providers.yaml \
  --provider mistral \
  --idea "Create a bounded note cleanup skill"
```

## Requirements for Mistral-backed draft

```text
MISTRAL_API_KEY is present in .env or shell environment
Soul/config/cloud_providers.yaml exists
cloud_llm.enabled: true
providers.mistral.enabled: true
providers.mistral.roles includes skill_brief_draft
cloud.providers.test passes
```

## What is sent

The provider prompt includes:

```text
the user-provided skill idea
selected Soul/ design docs under docs/soul/
```

It does not send:

```text
API keys
.env
user memory
private repo contents
task logs
local cloud provider config
```

## Output packet

Example:

```text
Soul/proposals/skills/20260707T190000Z-note-cleanup/
  metadata.json
  proposal.md
  provider_response.md
  prompt.md
  review_checklist.md
  sources.md
```

## Safety boundaries

This skill does not implement code.

It does not mutate repo source files.

It does not approve memory or rules.

It does not create background services.

It produces a proposal packet for human review.

## Verification

```bash
ruby scripts/verify-skill-brief-draft.rb
```

The verifier uses dry-run mode so it does not call Mistral.
