
# Phase 43 Patch Repair

The original Phase 43 patch script could not find a safe `run_assess` insertion point in the local `app.rb`.

The failure occurred before writing changes to `app.rb`, so the repo was not partially patched.

## Repair

This repair makes the patch script more tolerant:

```text
find require anchors from several recent phases
insert assess route after the run_assess case statement when possible
insert improve route after the run_improve case statement when possible
fall back to known command anchors when needed
warn rather than block if help text shape differs
```

## Scope

The repair only replaces the Phase 43 patch script and adds this maintenance note.

It does not change the skill catalog implementation itself.
