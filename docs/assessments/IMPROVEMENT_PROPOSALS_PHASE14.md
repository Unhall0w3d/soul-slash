# Improvement Proposals Phase 14

Phase 14 generates advisory improvement proposals from the capability matrix.

Commands:

```bash
ruby bin/soul improve proposals
ruby bin/soul improve proposals --json
ruby bin/soul improve proposals --write
ruby bin/soul improve proposals --write --json
```

## Behavior

Without `--write`, Soul only prints proposed improvements.

With `--write`, Soul writes proposal folders under:

```text
Soul/improvement/proposals
```

Each proposal folder contains:

```text
proposal.md
metadata.json
source_capability_matrix.json
```

## Boundaries

This phase is advisory only.

Soul must not:

```text
modify production skills
register new skills
register new workflows
install packages
download models
start services
implement proposals automatically
```

Every generated proposal requires human approval before implementation.

## Initial proposal types

```text
alpha_skill_generation
model_suitability_routing
vision_screen_understanding
speech_to_text
```

## Related repair

This phase also repairs capability matrix source discovery so unavailable registry listing methods do not produce source errors.
