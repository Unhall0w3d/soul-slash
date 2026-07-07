# Soul/ skill.brief.draft Mistral Overlay

This overlay adds the first real cloud-assisted drafting skill:

```text
skill.brief.draft
```

This is where Mistral starts doing useful work instead of replying with a ceremonial test string like a very expensive doorbell.

## Adds

```text
lib/soul_core/cloud_llm_client.rb
Soul/skills/skill/brief/draft.rb
scripts/verify-skill-brief-draft.rb
docs/skills/SKILL_BRIEF_DRAFT.md
README_SKILL_BRIEF_DRAFT_MISTRAL.md
docs/overlays/README_SKILL_BRIEF_DRAFT_MISTRAL.md
```

## What it does

```text
takes a rough skill idea
uses provider role skill_brief_draft
calls Mistral if configured
writes a review-only proposal packet under Soul/proposals/skills/
returns JSON evidence
writes a task log
```

## What it does not do

```text
implement the skill
mutate repo code
approve memory/rules
send secrets
send .env
send user memory
send task logs
send private repo content
create background services
```

## Apply

```bash
unzip ~/Downloads/soul_skill_brief_draft_mistral_overlay.zip
chmod +x Soul/skills/skill/brief/draft.rb scripts/verify-skill-brief-draft.rb
```

## Verify dry-run

```bash
ruby scripts/verify-skill-brief-draft.rb
```

Expected:

```text
Verification complete.
```

This creates a local ignored proposal fixture under:

```text
Soul/proposals/skills/
```

That is expected.

## Run with Mistral

Only after Mistral smoke test passes:

```bash
ruby Soul/skills/skill/brief/draft.rb \
  --config Soul/config/cloud_providers.yaml \
  --provider mistral \
  --idea "Create a bounded notes cleanup skill"
```

Expected:

```text
status: ok
outcome: complete
proposal_path: Soul/proposals/skills/<timestamp>-...
```

Review:

```bash
ls Soul/proposals/skills/
cat Soul/proposals/skills/<folder>/proposal.md
cat Soul/proposals/skills/<folder>/metadata.json
```

## Cleanup runtime artifacts before commit

Generated proposal folders and task logs are ignored/local. Do not commit them.

```bash
rm -rf Soul/proposals/skills/*/
rm -f Soul/logs/tasks/*-skill.brief.draft.json
```

Keep:

```text
Soul/proposals/skills/.keep
```

## Commit

```bash
git status --short
git add lib/soul_core/cloud_llm_client.rb \
  Soul/skills/skill/brief/draft.rb \
  scripts/verify-skill-brief-draft.rb \
  docs/skills/SKILL_BRIEF_DRAFT.md \
  README_SKILL_BRIEF_DRAFT_MISTRAL.md \
  docs/overlays/README_SKILL_BRIEF_DRAFT_MISTRAL.md

git commit -m "Add Mistral skill brief draft skill"
git push origin main
```

## Later

A future overlay should wire this into the normal `bin/soul` skill registry flow after direct testing is stable.
