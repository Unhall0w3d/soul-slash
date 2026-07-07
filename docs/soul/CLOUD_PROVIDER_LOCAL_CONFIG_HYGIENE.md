# Local Cloud Provider Config Hygiene

Soul/ keeps two provider config files conceptually separate:

```text
Soul/config/cloud_providers.example.yaml
Soul/config/cloud_providers.yaml
```

## Tracked

```text
Soul/config/cloud_providers.example.yaml
```

The example config is safe to commit because it should contain:

```text
provider names
expected env var names
default roles
policy notes
disabled defaults
```

It must not contain API keys.

## Ignored

```text
Soul/config/cloud_providers.yaml
```

The real local config should stay untracked because it may contain:

```text
local provider enablement
workspace/provider choices
machine-specific testing posture
operator preferences
```

It should still not contain API keys, because API keys belong in `.env` or the shell environment, but it remains local configuration.

## Secret storage

API keys must not be placed in YAML.

Use:

```text
.env
```

or exported shell environment variables.

The provider config may reference only the variable name:

```yaml
api_key_env: MISTRAL_API_KEY
```

## Verification

```bash
git check-ignore -v Soul/config/cloud_providers.yaml
git ls-files Soul/config/cloud_providers.yaml
git ls-files .env
```

Expected:

```text
Soul/config/cloud_providers.yaml is ignored
Soul/config/cloud_providers.yaml is not tracked
.env is not tracked
```
