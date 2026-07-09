
# Overlay Documentation

This directory is for curated overlay documentation only.

Most overlay README files are temporary application notes and should not be committed. The repository ignores common generated overlay note patterns:

```text
docs/overlays/README_*PHASE*.md
docs/overlays/README_*REPAIR*.md
```

## Commit only when curated

Commit overlay documentation only when it explains durable project process or architecture.

Appropriate examples:

```text
overlay system policy
overlay archive index
design rationale that still matters
```

Inappropriate examples:

```text
one-time apply commands
temporary repair instructions
generated phase README files
local cleanup notes
```

## Archive policy

If an overlay note is worth preserving, rewrite it into a stable document first. Do not blindly commit generated overlay instructions.
