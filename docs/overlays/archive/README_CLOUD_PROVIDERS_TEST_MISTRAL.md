# Soul/ cloud.providers.test Mistral Overlay

This overlay adds the first bounded provider smoke-test skill:

```text
cloud.providers.test
```

It implements **Mistral** first.

Now, and only now, the overlay includes Mistral setup documentation. A tiny miracle of timing and restraint.

## Adds

```text
Soul/skills/cloud/providers/test.rb
scripts/verify-cloud-providers-test.rb
docs/skills/CLOUD_PROVIDERS_TEST.md
README_CLOUD_PROVIDERS_TEST_MISTRAL.md
docs/overlays/README_CLOUD_PROVIDERS_TEST_MISTRAL.md
```

## What it does

```text
loads cloud provider config
loads .env if available
tests Mistral with a tiny prompt
writes a task log
reports provider/model/status
never prints API key values
```

## What it does not do

```text
create a Mistral account
generate an API key
write .env
send repo content
send user memory
send secrets
modify repo files
approve memory/rules
```

The key must be created manually. Soul/ is not getting into the “automate provider signup” business, because that way lies bans, captchas, and a small courtroom sketch of your repo.

## Apply

```bash
unzip ~/Downloads/soul_cloud_providers_test_mistral_overlay.zip
chmod +x Soul/skills/cloud/providers/test.rb scripts/verify-cloud-providers-test.rb
```

## Verify without a key

This should still verify structural behavior:

```bash
ruby scripts/verify-cloud-providers-test.rb
```

If Mistral is still disabled or no key is present, that is fine at this stage.

## Mistral setup, when ready

See:

```text
docs/skills/CLOUD_PROVIDERS_TEST.md
```

Summary:

```text
1. Create/sign into Mistral account manually.
2. Generate API key manually.
3. Add MISTRAL_API_KEY=... to .env.
4. Copy cloud_providers.example.yaml to cloud_providers.yaml.
5. Set cloud_llm.enabled: true.
6. Set providers.mistral.enabled: true.
7. Run cloud.providers.list.
8. Run cloud.providers.test.
```

## Test command

```bash
ruby Soul/skills/cloud/providers/test.rb --provider mistral --config Soul/config/cloud_providers.yaml
```

Expected success:

```text
status: ok
outcome: complete
exact_match: true
assistant_text: SOUL_PROVIDER_TEST_OK
```

## Registry integration

This overlay does not patch `Soul/skills/registry.yaml`.

Run directly for now:

```bash
ruby Soul/skills/cloud/providers/test.rb --provider mistral
```

After direct testing is stable, a later overlay can wire cloud provider skills into the normal Soul skill flow.

## Commit

```bash
git status --short
git add Soul/skills/cloud/providers/test.rb scripts/verify-cloud-providers-test.rb docs/skills/CLOUD_PROVIDERS_TEST.md README_CLOUD_PROVIDERS_TEST_MISTRAL.md docs/overlays/README_CLOUD_PROVIDERS_TEST_MISTRAL.md
git commit -m "Add Mistral cloud provider smoke test"
git push origin main
```
