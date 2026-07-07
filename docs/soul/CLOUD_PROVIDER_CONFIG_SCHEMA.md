# Cloud Provider Config Schema

This document describes the provider config loader introduced by this overlay.

## Purpose

The provider config loader validates cloud provider configuration without making network calls.

This is intentionally boring. Boring config validation is how we avoid debugging API clients that were doomed by a typo in YAML, the most humiliating flavor of software failure.

## Files

```text
lib/soul_core/cloud_provider_config.rb
scripts/verify-cloud-provider-config.rb
```

## Config search path

By default, the loader uses:

```text
Soul/config/cloud_providers.yaml
```

If that file does not exist, it falls back to:

```text
Soul/config/cloud_providers.example.yaml
```

This lets the repo ship an example file without requiring users to create a real config immediately.

## Auth modes

Supported auth modes:

```text
none
manual_api_key
official_oauth_device_flow
unsupported
```

## Validation

The loader validates:

```text
cloud_llm root
default policy safety flags
provider enabled flag
auth_mode
api_key_env requirements
roles
credit-card eligibility
programmatic key acquisition posture
```

It must not print secrets.

It reports only whether an environment variable is present:

```text
api_key_env: MISTRAL_API_KEY
api_key_present: true/false
```

## Manual API keys

If a provider uses:

```yaml
auth_mode: manual_api_key
```

then it must specify:

```yaml
api_key_env: SOME_ENV_VAR
```

The loader never reads or prints the key value except to determine whether the variable exists and is non-empty.

## Credit card policy

Providers with:

```yaml
requires_credit_card: true
```

are invalid by default.

Providers with:

```yaml
requires_credit_card: unknown_or_user_verified
```

should remain disabled unless the user explicitly verifies them.

## Usage

Verify the example config:

```bash
ruby scripts/verify-cloud-provider-config.rb
```

Verify a real config:

```bash
ruby scripts/verify-cloud-provider-config.rb Soul/config/cloud_providers.yaml
```

## Next overlay

The next overlay should add:

```text
cloud.providers.list
```

That skill should use this loader to display provider configuration without making outbound network calls.
