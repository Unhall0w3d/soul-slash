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

### Conversation lifecycle skills

```text
chats.clear
chats.forget
```

These operations are available through the dashboard's conversation lifecycle dialog. Clearing is reversible metadata archival and keeps transcripts. Delete-and-forget targets one exact conversation and is destructive. Both require a verified preview, unchanged digest, and exact human confirmation.

```text
CLEAR_CONVERSATIONS
DELETE_AND_FORGET_CONVERSATION
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

### Web knowledge skills

```text
web.lookup
web.research
```

`web.lookup` performs one narrow DuckDuckGo Instant Answer request. It is useful
for definitions and known entities, not source comparison. `web.research`
queries the explicitly configured SearXNG JSON endpoint and retrieves selected
public HTTPS sources with timestamps and content digests.

```bash
ruby Soul/skills/web/lookup.rb --query "What is Ruby?"
ruby Soul/skills/web/research.rb --query "current Ruby release documentation" --sources 5
make verify-web-knowledge
```

SearXNG addresses remain in the ignored `.env`; see `docs/REQUIREMENTS.md`.
Research and lookup are bounded foreground operations and never authorize
source instructions, file writes, skill creation, or memory promotion.

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

### Skill Studio lifecycle

Skill Studio is a dashboard application workflow over proposal packets, isolated Beta candidates, and the production skill registry; it is not itself a production skill.

```text
proposal intake or draft
→ human Gate 1 approval of the exact proposal
→ bounded Beta implementation outside the production registry
→ explicit human-invoked testing and diagnostics
→ human Gate 2 approval of the exact tested revision
→ separate preview/digest/exact-confirmation production promotion
```

Soul may create or reuse a local proposal intake when a task-shaped request is genuinely unsupported and no production or runnable Beta skill covers it. After Gate 1, Skill Studio can prepare an incomplete proposal-local Beta workspace and bounded Codex handoff, but does not invoke Codex or Mistral. After separate implementation, current passing tests, and Gate 2 approval, production promotion remains a distinct preview/digest/exact-confirmation operation that never replaces an existing skill.

### Self Assessment workflows

Self Assessment is an application workflow rather than a production skill. The dashboard can run bounded read-only environment, update, model-runtime, and capability assessments. Generating advisory improvement proposals requires preview and exact confirmation; host/package mutation is unavailable. The application API retains the historical `self_improvement.*` namespace.

## Documentation rule

When adding or changing a skill:

```text
update the relevant docs/skills/*.md file
update docs/SKILLS.md only when adding/removing skill docs or changing the skill index
avoid expanding the main README unless the project-level setup or architecture changes
```

Future per-skill mini public docs may be added later if the skill catalog grows large enough to justify it.
