# Alpha Skill Generator Phase 15

Phase 15 adds proposal-local alpha skill artifact generation.

Command:

```bash
ruby bin/soul improve alpha --proposal Soul/improvement/proposals/<proposal-folder>
ruby bin/soul improve alpha --proposal Soul/improvement/proposals/<proposal-folder> --json
```

## Input

The proposal folder must contain:

```text
metadata.json
proposal.md
```

## Output

Alpha artifacts are written under the selected proposal folder:

```text
alpha/
├── README.md
├── skill.rb
├── verify-alpha.rb
├── test_cases.json
├── promotion_checklist.md
└── alpha_manifest.json
```

## Boundaries

Alpha generation is proposal-local.

Soul must not:

```text
register the alpha skill
copy files into production skill paths
modify workflow registries
install packages
download models
promote the skill automatically
```

Every alpha artifact requires human review before promotion.

## Purpose

This phase starts the bridge from advisory proposal to reviewable implementation artifact, while keeping production Soul untouched.
