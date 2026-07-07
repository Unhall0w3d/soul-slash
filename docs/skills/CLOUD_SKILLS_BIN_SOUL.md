# Cloud and Skill-Brief Skills via bin/soul

The cloud provider and skill-brief tools can be wired into Soul's normal skill runner.

## Registered skills

```text
cloud.providers.list
cloud.providers.test
skill.brief.draft
skill.brief.review
```

## Usage

List configured providers:

```bash
ruby bin/soul skill cloud.providers.list -- --config Soul/config/cloud_providers.yaml
```

Smoke-test Mistral:

```bash
ruby bin/soul skill cloud.providers.test -- \
  --provider mistral \
  --config Soul/config/cloud_providers.yaml
```

Draft a skill proposal:

```bash
ruby bin/soul skill skill.brief.draft -- \
  --config Soul/config/cloud_providers.yaml \
  --provider mistral \
  --idea "Create a bounded notes cleanup skill"
```

Review a skill proposal:

```bash
ruby bin/soul skill skill.brief.review -- \
  --config Soul/config/cloud_providers.yaml \
  --provider mistral \
  --proposal Soul/proposals/skills/<proposal-folder>
```

## Dry-run checks

Draft dry-run:

```bash
ruby bin/soul skill skill.brief.draft -- \
  --dry-run \
  --idea "Verify skill brief draft"
```

Review dry-run:

```bash
ruby bin/soul skill skill.brief.review -- \
  --dry-run \
  --proposal Soul/proposals/skills/<proposal-folder>
```

## Boundary

These skills remain review-artifact tools.

They do not:

```text
approve memory/rules
implement skills
mutate repo code
send secrets
send .env
send user memory
create persistent services
```

Yes, we made cloud AI easier to call and still did not give it the steering wheel. A concept many products could stand to revisit.
