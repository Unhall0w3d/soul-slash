# Cloud Provider Configuration Policy

This document defines the planned provider configuration model for Soul/ cloud assist.

This scaffold does not implement provider clients yet.

## Provider selection principle

Skills request capabilities, not vendors.

Example skill needs:

```text
documentation_draft
skill_brief_draft
skill_design_review
prototype_review
research_synthesis_from_sources
fast_eval_generation
structured_output
rough_draft_probe
```

The provider selection layer chooses an enabled provider that satisfies the requested role and policy constraints.

## Authentication modes

Allowed auth modes:

```text
none
manual_api_key
official_oauth_device_flow
unsupported
```

Definitions:

```text
none:
No account and no API key required.

manual_api_key:
User manually creates key through official provider UI and stores it in .env or shell environment.

official_oauth_device_flow:
Provider has an official documented device/OAuth/CLI flow that can be implemented later with human approval.

unsupported:
Provider cannot be used under Soul/ policy.
```

## Provider eligibility fields

Provider config should include:

```yaml
enabled:
auth_mode:
api_key_env:
base_url:
default_model:
roles:
requires_credit_card:
credit_card_policy:
programmatic_key_acquisition:
trust_level:
notes:
```

## Initial provider posture

Mistral is included as the primary serious provider candidate.

No-key providers may be listed as experimental probes.

Manual-key providers with billing ambiguity must remain disabled until manually verified.

## Example config

See:

```text
Soul/config/cloud_providers.example.yaml
```

## No secret logging

Provider-list and provider-test skills must never print API key values.

They may report only:

```text
api_key_env: MISTRAL_API_KEY
api_key_present: true/false
```

Human inconvenience remains preferable to publishing credentials. Civilization limps onward.
