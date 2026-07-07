# Cloud Assist Artifacts

Cloud LLM outputs in Soul/ must land as review artifacts.

They must not directly mutate repo code, approved memory, safety rules, or project documentation.

## Artifact roots

Cloud-assist raw outputs:

```text
Soul/artifacts/cloud_assist/
```

Skill proposal packets:

```text
Soul/proposals/skills/
```

Both directories are ignored by default except for `.keep` files.

## Why generated artifacts are ignored

Cloud outputs are candidate material.

They may contain:

```text
draft prose
provider responses
review packets
source summaries
model limitations
experimental structure
```

They should be reviewed before anything is promoted into tracked docs or implementation files.

That is the difference between “assistant” and “unattended prose trebuchet.”

## Metadata

Every cloud artifact should include:

```text
metadata.json
```

Required metadata posture:

```json
{
  "output_mode": "review_artifact_only",
  "direct_repo_mutation": false,
  "human_review_required": true
}
```

Cloud request metadata should include, when available:

```text
provider
model
purpose
data_class
secrets_included
private_repo_content_included
user_memory_included
source_bundle
```

## Generated folder pattern

Example cloud artifact:

```text
Soul/artifacts/cloud_assist/20260707T190000Z-skill-brief-draft/
  metadata.json
  provider_response.md
  prompt.md
```

Example skill proposal:

```text
Soul/proposals/skills/20260707T190000Z-weather-alerts/
  metadata.json
  proposal.md
  provider_response.md
  review_checklist.md
  sources.md
```

## Promotion

To promote a generated artifact:

```text
human reviews it
human edits/sanitizes as needed
human manually copies selected content into tracked docs/code
human commits the intentional change
```

Cloud outputs do not promote themselves.
