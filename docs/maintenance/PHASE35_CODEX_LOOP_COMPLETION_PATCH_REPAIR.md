
# Phase 35 Patch Repair

The original Phase 35 patch script expected the `skill-loop` assessment route to have an exact source layout.

The local `app.rb` did not match that exact multiline anchor, so the patch stopped safely with:

```text
Could not find skill-loop route anchor
```

This repair replaces the patch script with a more tolerant insertion strategy:

```text
add require near skill-loop or Codex fixture requires
insert codex-loop route before capabilities or repo-curation
add help line near skill-loop or codex-dry-run-review
```

It still fails closed if no safe insertion point is found.
