# Soul/ Reflection Review overlay

This overlay adds the human review gate for reflection candidates.

Existing flow:

```text
ruby bin/soul reflect last
```

New flow:

```text
ruby bin/soul reflection show latest
ruby bin/soul reflection approve latest
ruby bin/soul reflection reject latest --reason "not useful"
```

Approving a candidate:
- moves the `.json` and `.md` candidate from `Soul/reflection/pending/` to `Soul/reflection/approved/`
- appends candidate lessons to `Soul/memory/approved_lessons.md`
- appends candidate rules to `Soul/memory/approved_rules.md`

Rejecting a candidate:
- moves the pair to `Soul/reflection/rejected/`
- records a rejection reason in the JSON
- does not apply lessons or rules

This is the first explicit memory/rule promotion gate.
Nothing is promoted automatically.
