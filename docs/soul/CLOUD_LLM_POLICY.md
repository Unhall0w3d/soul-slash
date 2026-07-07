# Cloud LLM Policy

Cloud LLM support in Soul/ is an assist layer for drafting, critique, synthesis, prototype suggestions, and review artifacts.

It is not an authority layer.

## Primary rule

Cloud models draft artifacts.

Codex may mutate the repo under a brief.

Humans approve.

## Allowed cloud LLM uses

Cloud LLMs may:

```text
draft documentation
summarize approved sources
critique skill briefs
generate prototype snippets as artifacts
generate test/eval prompts
produce human review packets
compare provider options
synthesize research from supplied source bundles
```

## Prohibited cloud LLM uses

Cloud LLMs must not:

```text
receive secrets
receive API keys
receive credentials
receive private repo content unless explicitly approved in a skill brief
receive user memory unless explicitly approved in a skill brief
mutate repo files directly
decide safety classification
approve their own work
approve memory/rules
approve persistence
approve merge readiness
run background or persistent processes
```

## Credential acquisition policy

Soul/ prefers no-key providers for low-trust experiments.

For serious cloud-assisted drafting/review, Soul/ may use a manual API-key provider if:

```text
the provider currently documents no-credit-card free API access
the user creates the account/API key manually
the key is stored only in .env or the user's shell environment
Soul/ never prints or logs the key
Soul/ never attempts unofficial account creation or key acquisition
```

Soul/ must not scrape, fake, farm, automate signup pages, or programmatically create provider accounts/API keys.

Programmatic credential acquisition is allowed only through official documented OAuth, device-code, or CLI authentication flows approved in the relevant skill brief.

## Mistral posture

Mistral is the first serious manual-key provider candidate because current official docs state Free mode API access is enabled by default with no credit card required.

Mistral setup instructions are intentionally deferred until the provider test overlay. At that time, Soul/ documentation should include:

```text
account creation steps
API key generation steps
.env setup
provider smoke test
no-secret logging verification
```

Do not add Mistral account/API-key setup instructions in this policy scaffold.

## No-key provider posture

No-key providers may be used for low-trust experiments and rough drafts only until they pass repeated smoke tests and their terms/behavior are better understood.

No-key providers should not receive private repo content or user memory.

## Request metadata banner

Every cloud LLM request must declare metadata:

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

## Artifact-only output

Cloud outputs should be written as review artifacts under a future artifact path such as:

```text
Soul/artifacts/cloud_assist/<timestamp>-<purpose>/
```

Cloud models must not write directly into:

```text
lib/
Soul/skills/
Soul/memory/
AGENTS.md
docs/soul/
```

unless a human explicitly applies their output through a normal repo change.

## Failure behavior

A cloud skill should return:

```text
complete
failed
blocked_for_input
blocked_for_human_review
canceled
```

It should not loop indefinitely or retry forever.
