# CLI Help Formatting Cleanup

## Purpose

This cleanup fixes the workflow help output so commands are shown as separate usable lines.

It also adds a natural YouTube play workflow example to the help text.

## Commands expected in help output

```bash
ruby bin/soul workflow show latest
ruby bin/soul workflow status latest
ruby bin/soul workflow list
ruby bin/soul workflow list --active
ruby bin/soul workflow clear-complete
ruby bin/soul workflow clear-complete --confirm CLEAR_COMPLETE

ruby bin/soul do "play Folsom Prison Blues on YouTube"
ruby bin/soul respond "yes"
```

## Behavior

This is a formatting-only cleanup.

It should not change workflow behavior, skill behavior, confirmation behavior, or session cleanup behavior.

## Verification

```bash
ruby scripts/verify-cli-help-formatting.rb
```
