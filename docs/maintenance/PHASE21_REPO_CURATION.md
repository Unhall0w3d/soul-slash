
# Phase 21 Repo Curation

Phase 21 adds read-only repo curation assessment.

## Purpose

Phase 20 established repository hygiene policy. Phase 21 helps inspect existing tracked and untracked leftovers so they can be curated deliberately.

The command is read-only:

```bash
ruby bin/soul assess repo-curation
ruby bin/soul assess repo-curation --json
```

## What it reports

```text
tracked overlay notes
untracked docs/verifier candidates
untracked generated/local leftovers
recommendations
proposed actions
```

## What it does not do

```text
delete files
stage files
commit files
remove tracked files
rewrite documentation
modify gitignore
```

## Curation rules

Use small explicit commits.

Do not use:

```bash
git add .
```

Classify files into:

```text
commit as durable source/doc/verifier
rewrite into stable documentation
remove from tracking
delete local generated debris
leave untracked temporarily
```

## Known curation candidates

Existing tracked overlay repair notes may be worth removing from normal tracked history or rewriting into stable docs.

Existing untracked phase 9/10 docs/verifiers should be reviewed separately. They may be valuable, but they should not be swept into a hygiene commit accidentally.
