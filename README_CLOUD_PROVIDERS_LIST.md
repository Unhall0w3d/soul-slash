# Soul/ cloud.providers.list Overlay

This is the third cloud-assist overlay.

It adds the first cloud provider skill:

```text
cloud.providers.list
```

This skill is intentionally network-free.

It does **not**:

```text
test Mistral
ask for API keys
add Mistral setup docs
write .env
make outbound network calls
```

No API-key side quest yet. We remain tragically disciplined.

## Adds

```text
Soul/skills/cloud/providers/list.rb
scripts/verify-cloud-providers-list.rb
docs/skills/CLOUD_PROVIDERS_LIST.md
README_CLOUD_PROVIDERS_LIST.md
docs/overlays/README_CLOUD_PROVIDERS_LIST.md
```

## Apply

```bash
unzip ~/Downloads/soul_cloud_providers_list_skill_overlay.zip
chmod +x Soul/skills/cloud/providers/list.rb scripts/verify-cloud-providers-list.rb
```

## Run

```bash
ruby Soul/skills/cloud/providers/list.rb
```

Expected behavior with only the example config:

```text
status: ok
outcome: complete
network_used: false
secrets_printed: false
providers listed from Soul/config/cloud_providers.example.yaml
```

Mistral should still be disabled and should not ask for an API key.

## Verify

```bash
ruby scripts/verify-cloud-providers-list.rb
```

Expected:

```text
Verification complete.
```

## Optional config test

If you want to test config loading without enabling anything:

```bash
cp Soul/config/cloud_providers.example.yaml Soul/config/cloud_providers.yaml
ruby Soul/skills/cloud/providers/list.rb --config Soul/config/cloud_providers.yaml
```

Do not add real API keys yet. The Mistral setup documentation arrives with the provider smoke-test overlay, where it actually belongs instead of floating around like a credential-shaped liability.

## Registry integration

This overlay does not patch `Soul/skills/registry.yaml`.

For now, run the skill directly:

```bash
ruby Soul/skills/cloud/providers/list.rb
```

After the direct skill is verified, the next overlay can wire it into Soul's normal `ruby bin/soul skill ...` flow once we confirm the current registry shape.

## Commit

```bash
git status --short
git add Soul/skills/cloud/providers/list.rb scripts/verify-cloud-providers-list.rb docs/skills/CLOUD_PROVIDERS_LIST.md README_CLOUD_PROVIDERS_LIST.md docs/overlays/README_CLOUD_PROVIDERS_LIST.md
git commit -m "Add cloud providers list skill"
git push origin main
```
