# Skill Studio

Skill Studio is Soul's controlled path for turning a missing capability into a reviewable production skill. It is for bounded actions with explicit inputs, outputs, limits, failures, and human authority—not for changing Soul's shared architecture.

Open it from **Self Improvement → Skill Studio**.

## The three inventories

- **Proposals** describe a capability, its scope, risks, tests, and review requirements. A proposal is not code and cannot run.
- **Beta Skills** are isolated candidate implementations. They are not registered for ordinary use and run only when the Operator explicitly invokes them.
- **Production Skills** are registered capabilities available to Soul's normal planner and execution boundary.

## Intended flow

```text
need or capability gap
→ proposal
→ Gate 1: approve exact scope
→ isolated Beta workspace
→ implementation and deterministic tests
→ bounded Beta trials and diagnostics
→ Gate 2: approve exact tested revision
→ separate production promotion
→ proposal closeout
```

### 1. Create or receive a proposal

A proposal may begin as a human-authored brief or as a conservative capability-gap signal from Chat. Soul should propose a skill only when the request is genuinely unsupported—not merely because clarification, research, or an existing skill is needed.

Select the proposal and review:

- the problem and intended capability;
- exact boundaries and risk class;
- cloud provenance, if drafting assistance was used;
- required tests and human review checklist;
- the proposed canonical skill ID.

### 2. Gate 1: approve the scope

**Approve for Beta implementation** records approval of one exact proposal revision. It does not generate code, invoke Codex, change the production registry, or run a skill.

After Gate 1, **Prepare isolated Beta implementation** creates an intentionally incomplete proposal-local workspace and a bounded implementation handoff. The human or an explicitly invoked development tool performs the implementation separately.

### 3. Review and try the Beta

A Beta remains separate from production. Inspect its description, risk classification, current-revision test evidence, known weaknesses, and required promotion tests.

**Try this Beta** performs one previewed, foreground run with bounded arguments and writes diagnostic evidence. Beta failures should terminate visibly; they must not become silent background work.

Changing candidate files changes the revision. Tests and approvals for an older digest do not carry forward automatically.

### 4. Gate 2: approve the tested revision

**Approve for later promotion** checks Gate 1, implementation completeness, current test evidence, and revision integrity. It records approval of the exact tested Beta; it still does not mutate production.

### 5. Promote and close

Production promotion is a separate preview and confirmation. It copies the reviewed entrypoint, records hashes and rollback evidence, and adds one new registry entry atomically. It refuses to replace an existing production skill.

Once the linked skill is registered, proposal closeout may permanently remove the completed proposal and superseded Beta copy while preserving the production skill and shared diagnostics.

## Choosing Skill Studio or Self Augmentation

Use Skill Studio when the new behavior can be expressed as one bounded capability. Use [Self Augmentation](SELF_AUGMENTATION.md) when shared orchestration, contracts, memory architecture, provider infrastructure, or another core subsystem must change.

## Authority boundary

Model output, passing tests, and successful Beta trials are evidence—not authorization. Proposal approval, Beta approval, production promotion, and closeout are distinct human decisions.

## Related engineering references

- [`docs/SKILLS.md`](../SKILLS.md)
- [`docs/soul/HUMAN_REVIEW_GATE.md`](../soul/HUMAN_REVIEW_GATE.md)
- [`docs/soul/PHASE12D5_GATED_BETA_BUILD_AND_PRODUCTION_PROMOTION_BRIEF.md`](../soul/PHASE12D5_GATED_BETA_BUILD_AND_PRODUCTION_PROMOTION_BRIEF.md)
