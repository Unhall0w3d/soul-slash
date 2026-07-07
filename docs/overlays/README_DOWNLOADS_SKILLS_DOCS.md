# Soul/ Downloads Skills Documentation Overlay

This overlay fills the missing public docs for the Downloads cleanup/restore skills.

You were right: `docs/skills/` had cloud/weather docs, but not the cleanup Downloads workflow. Naturally, the oldest working skill was the one quietly missing from the index. Documentation, the eternal tax on progress.

## Adds

```text
docs/skills/DOWNLOADS_CLEANUP.md
docs/SKILLS.md
README_DOWNLOADS_SKILLS_DOCS.md
docs/overlays/README_DOWNLOADS_SKILLS_DOCS.md
```

## What it documents

```text
downloads.inspect
downloads.cleanup_plan
downloads.move_to_trash
downloads.restore_last_cleanup
```

It captures:

```text
natural cleanup flow
candidate IDs
confirmation behavior
Trash-only policy
restore-last-cleanup workflow
protected-name behavior
terminal states
reflection guidance
```

## Apply

```bash
unzip ~/Downloads/soul_downloads_skills_docs_overlay.zip
```

## Review

```bash
cat docs/skills/DOWNLOADS_CLEANUP.md
cat docs/SKILLS.md
git diff -- docs/skills/DOWNLOADS_CLEANUP.md docs/SKILLS.md
```

## Commit

```bash
git status --short
git add docs/skills/DOWNLOADS_CLEANUP.md docs/SKILLS.md README_DOWNLOADS_SKILLS_DOCS.md docs/overlays/README_DOWNLOADS_SKILLS_DOCS.md
git commit -m "Document Downloads cleanup skills"
git push origin main
```

## Final docs cleanup note

The later final documentation cleanup overlay should move root overlay readmes like this one into:

```text
docs/overlays/archive/
```

and keep root README focused on project overview/setup while `docs/SKILLS.md` owns the skill index.
