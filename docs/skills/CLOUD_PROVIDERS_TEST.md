# cloud.providers.test

`cloud.providers.test` runs bounded cloud-provider smoke tests.

This overlay implements Mistral smoke testing first.

## Scope

This skill:

```text
uses provider config
loads .env if SoulCore::EnvLoader is available
sends only a tiny smoke-test prompt
writes a task log
reports provider/model/status
never prints API key values
```

This skill does not:

```text
send repo content
send user memory
send secrets
draft artifacts
modify repo files
approve memory/rules
```

## Direct usage

```bash
ruby Soul/skills/cloud/providers/test.rb --provider mistral
```

Optional explicit config:

```bash
ruby Soul/skills/cloud/providers/test.rb --provider mistral --config Soul/config/cloud_providers.yaml
```

Optional model override:

```bash
ruby Soul/skills/cloud/providers/test.rb --provider mistral --model mistral-small-latest
```

## Smoke-test prompt

The prompt is intentionally tiny:

```text
Reply with exactly: SOUL_PROVIDER_TEST_OK
```

The expected response is:

```text
SOUL_PROVIDER_TEST_OK
```

A non-exact answer from a successful HTTP request is reported as a warning, not success. No green lights without gauges. Again. Somehow this still needs to be said.

## Mistral setup

Mistral setup is manual.

Soul/ must not create accounts, scrape keys, automate signup forms, or programmatically acquire API keys through unofficial means.

Current Mistral documentation says Free mode API access is enabled by default with no credit card required, and API keys work in Free mode with usage/rate limits suitable for evaluation and prototyping.

### 1. Create or sign into a Mistral account

Use Mistral's official Studio/API-key documentation.

### 2. Generate an API key

Create an API key in Mistral Studio.

Recommended handling:

```text
set an expiration date if available
copy the key once
store it locally only
rotate it if exposed
```

### 3. Add the key to `.env`

Add:

```env
MISTRAL_API_KEY=your_key_here
```

Do not commit `.env`.

Do not paste the key into chat.

Do not put it in YAML.

Do not put it in shell history if avoidable.

### 4. Enable Mistral in provider config

Create a real config from the example if needed:

```bash
cp Soul/config/cloud_providers.example.yaml Soul/config/cloud_providers.yaml
```

Edit:

```yaml
cloud_llm:
  enabled: true

  providers:
    mistral:
      enabled: true
```

Keep:

```yaml
auth_mode: manual_api_key
api_key_env: MISTRAL_API_KEY
requires_credit_card: false
programmatic_key_acquisition: unsupported
```

### 5. Run provider list

```bash
ruby Soul/skills/cloud/providers/list.rb --config Soul/config/cloud_providers.yaml
```

Expected for Mistral:

```text
enabled: true
api_key_present: true
status: ready_for_manual_key_smoke_test
```

### 6. Run provider test

```bash
ruby Soul/skills/cloud/providers/test.rb --provider mistral --config Soul/config/cloud_providers.yaml
```

Expected:

```text
status: ok
outcome: complete
exact_match: true
assistant_text: SOUL_PROVIDER_TEST_OK
```

## Failure states

```text
blocked_for_input:
Provider disabled or required API key env var missing.

blocked_for_human_review:
Provider is configured but not implemented by this overlay.

failed:
Provider returned an HTTP/API/network error.

warning:
Provider responded, but smoke-test output was not exact.
```

## Logs

Task logs are written to:

```text
Soul/logs/tasks/<timestamp>-cloud.providers.test.json
```

Logs must not include API key values.
