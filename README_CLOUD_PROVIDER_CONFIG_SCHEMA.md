# Soul/ Cloud Provider Config Schema Overlay

This is the second cloud-assist overlay.

It adds a provider config loader and verifier.

It does **not**:

```text
make network calls
test Mistral
ask for API keys
add Mistral setup instructions
write .env
```

Provider setup docs still wait until the `cloud.providers.test` overlay, as requested.

## Adds

```text
lib/soul_core/cloud_provider_config.rb
scripts/verify-cloud-provider-config.rb
docs/soul/CLOUD_PROVIDER_CONFIG_SCHEMA.md
README_CLOUD_PROVIDER_CONFIG_SCHEMA.md
docs/overlays/README_CLOUD_PROVIDER_CONFIG_SCHEMA.md
```

## Behavior

The loader reads:

```text
Soul/config/cloud_providers.yaml
```

or falls back to:

```text
Soul/config/cloud_providers.example.yaml
```

It validates:

```text
auth_mode
manual API key env var names
roles
enabled/disabled status
credit-card eligibility
programmatic key acquisition posture
safe default policy flags
```

It never prints secret values. It only reports whether an expected env var is present.

## Apply

```bash
unzip ~/Downloads/soul_cloud_provider_config_schema_overlay.zip
chmod +x scripts/verify-cloud-provider-config.rb
```

## Verify

```bash
ruby scripts/verify-cloud-provider-config.rb
```

Expected:

```text
Cloud provider config verification: ok
```

Since this uses the example config, Mistral should appear as disabled, manual API key, and `api_key_present: false`.

That is correct. We are not setting up Mistral yet. The API-key ritual happens later, with documentation, not by vibes and terminal incense.

## Optional real config later

Eventually, users can create:

```bash
cp Soul/config/cloud_providers.example.yaml Soul/config/cloud_providers.yaml
```

Then enable providers there. Do not do that yet unless testing the loader manually.

## Commit

```bash
git status --short
git add lib/soul_core/cloud_provider_config.rb scripts/verify-cloud-provider-config.rb docs/soul/CLOUD_PROVIDER_CONFIG_SCHEMA.md README_CLOUD_PROVIDER_CONFIG_SCHEMA.md docs/overlays/README_CLOUD_PROVIDER_CONFIG_SCHEMA.md
git commit -m "Add cloud provider config schema"
git push origin main
```
