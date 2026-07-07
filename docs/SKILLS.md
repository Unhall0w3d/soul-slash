# Skills

This document is the public skill index for Soul/.

The main README stays focused on project overview and setup. Skill-specific usage belongs here and in `docs/skills/*.md`, because updating the front page every time a skill changes is how documentation turns into a haunted attic.

## Skill groups

### System skills

```text
system.status
```

Usage:

```bash
ruby bin/soul skill system.status
```

### Downloads cleanup skills

```text
downloads.inspect
downloads.cleanup_plan
downloads.move_to_trash
downloads.restore_last_cleanup
```

Docs:

```text
docs/skills/DOWNLOADS_CLEANUP.md
```

Common workflow:

```bash
ruby bin/soul do "cleanup files in my downloads folder older than 30 days"
ruby bin/soul respond "move all"
ruby bin/soul respond "yeah, do it"
```

Restore workflow:

```bash
ruby bin/soul do "restore the last downloads cleanup"
ruby bin/soul respond "restore all"
ruby bin/soul respond "yeah, do it"
```

### Weather skills

```text
weather.report
```

Docs:

```text
docs/skills/WEATHER_REPORT.md
```

Examples:

```bash
ruby bin/soul do "what is the weather like today"
ruby bin/soul do "what is the weather today in London, UK"
```

### Cloud provider skills

```text
cloud.providers.list
cloud.providers.test
```

Docs:

```text
docs/skills/CLOUD_PROVIDERS_LIST.md
docs/skills/CLOUD_PROVIDERS_TEST.md
docs/skills/CLOUD_SKILLS_BIN_SOUL.md
```

Examples:

```bash
ruby bin/soul skill cloud.providers.list -- --config Soul/config/cloud_providers.yaml
```

```bash
ruby bin/soul skill cloud.providers.test -- \
  --provider mistral \
  --config Soul/config/cloud_providers.yaml
```

### Skill proposal drafting/review

```text
skill.brief.draft
skill.brief.review
```

Docs:

```text
docs/skills/SKILL_BRIEF_DRAFT.md
docs/skills/SKILL_BRIEF_REVIEW.md
```

Draft a proposal:

```bash
ruby bin/soul skill skill.brief.draft -- \
  --config Soul/config/cloud_providers.yaml \
  --provider mistral \
  --idea "Create a bounded notes cleanup skill"
```

Review a proposal:

```bash
ruby bin/soul skill skill.brief.review -- \
  --config Soul/config/cloud_providers.yaml \
  --provider mistral \
  --proposal Soul/proposals/skills/<proposal-folder>
```

## Documentation rule

When adding or changing a skill:

```text
update the relevant docs/skills/*.md file
update docs/SKILLS.md only when adding/removing skill docs or changing the skill index
avoid expanding the main README unless the project-level setup or architecture changes
```

Future per-skill mini public docs may be added later if the skill catalog grows large enough to justify it.
