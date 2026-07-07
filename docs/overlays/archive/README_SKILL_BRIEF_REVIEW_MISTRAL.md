# Soul/ skill.brief.review Mistral Overlay

This overlay adds the second real cloud-assisted proposal skill:

```text
skill.brief.review
```

It reviews a generated skill proposal against Soul/ design rules and writes a review-only artifact under the proposal folder.

## Adds

```text
Soul/skills/skill/brief/review.rb
scripts/verify-skill-brief-review.rb
docs/skills/SKILL_BRIEF_REVIEW.md
README_SKILL_BRIEF_REVIEW_MISTRAL.md
docs/overlays/README_SKILL_BRIEF_REVIEW_MISTRAL.md
```

## What it does

```text
takes a proposal folder or proposal.md path
reads proposal.md and supporting proposal files
reads selected docs/soul design docs
calls Mistral if configured
writes a review packet under proposal/reviews/
returns JSON evidence
writes a task log
```

## What it does not do

```text
approve the proposal
implement the skill
mutate repo code
approve memory/rules
send secrets
send .env
send user memory
send task logs
send local cloud provider config
create background services
```

## Apply

```bash
unzip ~/Downloads/soul_skill_brief_review_mistral_overlay.zip
chmod +x Soul/skills/skill/brief/review.rb scripts/verify-skill-brief-review.rb
```

## Verify dry-run

```bash
ruby scripts/verify-skill-brief-review.rb
```

Expected:

```text
Verification complete.
```

## Run with Mistral

Given an existing proposal folder:

```bash
ruby Soul/skills/skill/brief/review.rb \
  --config Soul/config/cloud_providers.yaml \
  --provider mistral \
  --proposal Soul/proposals/skills/<proposal-folder>
```

Expected:

```text
status: ok
outcome: complete
review_path: Soul/proposals/skills/<proposal-folder>/reviews/<timestamp>-skill-brief-review
```

Review:

```bash
cat Soul/proposals/skills/<proposal-folder>/reviews/<review-folder>/review.md
cat Soul/proposals/skills/<proposal-folder>/reviews/<review-folder>/metadata.json
```

## Cleanup runtime artifacts before commit

Generated proposal/review folders and task logs are ignored/local. Do not commit them.

```bash
rm -rf Soul/proposals/skills/*/
rm -f Soul/logs/tasks/*-skill.brief.review.json
```

Keep:

```text
Soul/proposals/skills/.keep
```

## Commit

```bash
git status --short
git add Soul/skills/skill/brief/review.rb \
  scripts/verify-skill-brief-review.rb \
  docs/skills/SKILL_BRIEF_REVIEW.md \
  README_SKILL_BRIEF_REVIEW_MISTRAL.md \
  docs/overlays/README_SKILL_BRIEF_REVIEW_MISTRAL.md

git commit -m "Add Mistral skill brief review skill"
git push origin main
```

## Later

A future overlay should wire this into the normal `bin/soul` skill registry flow after direct testing is stable.
