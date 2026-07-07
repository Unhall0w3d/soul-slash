# Cloud Assist Skill Template

Use this template for any skill that calls a cloud LLM.

## Skill name

```text
cloud_or_skill.name
```

## Purpose

```text
What review artifact is this skill producing?
```

## Role requested

```text
documentation_draft
skill_brief_draft
skill_design_review
prototype_review
research_synthesis_from_sources
rough_draft_probe
```

## Provider policy

```text
Preferred provider:
Fallback providers:
Allowed auth modes:
No-key allowed:
Manual API key allowed:
Private content allowed:
```

## Input data classes

```text
public_project_summary
repo_design_summary
selected_repo_excerpt
source_bundle
user_memory_summary
private_content
```

## Request metadata

```yaml
provider:
model:
purpose:
data_class:
secrets_included: false
private_repo_content_included: false
user_memory_included: false
source_bundle:
output_mode: review_artifact_only
```

## Safety boundaries

```text
No direct repo mutation.
No secret transmission.
No memory/rule approval.
No safety classification authority.
No persistence/background behavior.
```

## Expected outputs

```text
review artifact path
summary
warnings
provider/model used
token/request metadata if available
known limitations
```

## Terminal states

```text
complete
failed
blocked_for_input
blocked_for_human_review
canceled
```

## Human review checklist

```text
Does the output match the requested purpose?
Was any private content sent?
Were secrets excluded?
Is output clearly marked review-only?
Is provider metadata present?
Are sources cited if synthesis claims are made?
Are limitations/warnings captured?
```
