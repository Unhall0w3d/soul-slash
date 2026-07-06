# Soul/ Reflection overlay

This overlay adds deterministic reflection candidate staging.

It does not automatically promote memory, rules, or skills.

## Commands

```bash
cd ~/Projects/soul
unzip ~/Downloads/soul_reflection_overlay.zip

ruby bin/soul reflect last
ruby bin/soul reflections
```

You can also reflect a specific task log:

```bash
ruby bin/soul reflect Soul/logs/tasks/<task-log-file>.json
```

Reflection output is written to:

```text
Soul/reflection/pending/
```

Each reflection creates:
- a JSON candidate
- a Markdown review file

This is the first "learning loop" piece:
task -> evidence -> reflection candidate -> human review later
