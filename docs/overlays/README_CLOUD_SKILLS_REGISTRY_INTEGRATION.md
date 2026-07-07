# Soul/ Cloud Skills Registry Integration Overlay

This overlay registers the cloud provider and skill-brief tools with the normal Soul skill runner.

## Adds

```text
scripts/patch-cloud-skills-registry.rb
scripts/verify-cloud-skills-bin-soul.rb
docs/skills/CLOUD_SKILLS_BIN_SOUL.md
README_CLOUD_SKILLS_REGISTRY_INTEGRATION.md
docs/overlays/README_CLOUD_SKILLS_REGISTRY_INTEGRATION.md
```

## Patches

```text
Soul/skills/registry.yaml
```

Registers:

```text
cloud.providers.list
cloud.providers.test
skill.brief.draft
skill.brief.review
```

## Apply

```bash
unzip ~/Downloads/soul_cloud_skills_registry_integration_overlay.zip
chmod +x scripts/patch-cloud-skills-registry.rb scripts/verify-cloud-skills-bin-soul.rb
ruby scripts/patch-cloud-skills-registry.rb
```

## Verify

```bash
ruby scripts/verify-cloud-skills-bin-soul.rb
```

Expected:

```text
Verification complete.
```

The verifier uses:

```text
cloud.providers.example.yaml
dry-run modes
temporary ignored proposal folders
```

It should not make a Mistral network call.

## Manual commands

List providers:

```bash
ruby bin/soul skill cloud.providers.list -- --config Soul/config/cloud_providers.yaml
```

Test Mistral:

```bash
ruby bin/soul skill cloud.providers.test -- \
  --provider mistral \
  --config Soul/config/cloud_providers.yaml
```

Draft proposal:

```bash
ruby bin/soul skill skill.brief.draft -- \
  --config Soul/config/cloud_providers.yaml \
  --provider mistral \
  --idea "Create a bounded notes cleanup skill"
```

Review proposal:

```bash
ruby bin/soul skill skill.brief.review -- \
  --config Soul/config/cloud_providers.yaml \
  --provider mistral \
  --proposal Soul/proposals/skills/<proposal-folder>
```

## Cleanup runtime artifacts before commit

```bash
rm -rf Soul/proposals/skills/*/
rm -f Soul/logs/tasks/*-cloud.providers.test.json
rm -f Soul/logs/tasks/*-skill.brief.draft.json
rm -f Soul/logs/tasks/*-skill.brief.review.json
```

Keep:

```text
Soul/proposals/skills/.keep
```

## Cleanup patch scaffolding before commit

Remove the one-time patch script and root overlay README:

```bash
rm scripts/patch-cloud-skills-registry.rb
rm README_CLOUD_SKILLS_REGISTRY_INTEGRATION.md
rm docs/overlays/README_CLOUD_SKILLS_REGISTRY_INTEGRATION.md
```

Keep the verifier and docs:

```text
scripts/verify-cloud-skills-bin-soul.rb
docs/skills/CLOUD_SKILLS_BIN_SOUL.md
```

## Commit

```bash
git status --short
git add Soul/skills/registry.yaml \
  scripts/verify-cloud-skills-bin-soul.rb \
  docs/skills/CLOUD_SKILLS_BIN_SOUL.md

git commit -m "Register cloud skill tooling"
git push origin main
```
