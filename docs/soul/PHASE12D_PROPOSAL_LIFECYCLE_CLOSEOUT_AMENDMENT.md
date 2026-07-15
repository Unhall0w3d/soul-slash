# Approved Amendment: Proposal Stage, Skill Link, and Production Closeout

```text
brief_status: approved by human owner instruction
implementation_authorized: yes
permanent_proposal_deletion_authorized: production-linked proposals only
beta_or_unlinked_proposal_deletion_authorized: no
human_visual_review_required: yes
```

The owner requested that Skill Studio show the current stage of each proposal, link the proposal to its resulting skill, and allow the proposal to be closed and deleted only after the linked skill is production rather than Beta.

## Deterministic lifecycle

Every canonical proposal exposes exactly one stage:

```text
awaiting_proposal_review
approved_for_beta_build
beta_build
beta_testing
ready_for_promotion_review
approved_for_promotion
production
```

Stage derives only from the existing exact-revision proposal gate, canonical Beta manifest and test evidence, exact-revision Beta gate, and production skill registry. Browser input and model output cannot set it.

## Skill linkage

The canonical Beta manifest's `skill_id` links its proposal to the Beta candidate. The same exact ID links to production only when it is present in `Soul/skills/registry.yaml` with a non-empty production path. Skill Studio shows the linked ID and whether it is unbuilt, Beta, approved for promotion, or production.

No fuzzy title matching, model inference, or user-supplied path is allowed.

## Closeout gate

Closeout permanently removes the canonical proposal directory, including its now-superseded Beta candidate copy and proposal-local gate state. It must not remove or modify:

- the registered production skill or registry entry;
- shared Beta diagnostic logs;
- chats, memories, artifacts, approvals, or application activity;
- unrelated proposals or legacy Alpha/Beta records.

Closeout is available only when deterministic stage is `production`. It requires:

1. a preview of the exact proposal, Beta, gate, linkage, and production-registry revision;
2. the unchanged closeout digest;
3. literal confirmation `CLOSE_PRODUCTION_PROPOSAL`;
4. revalidation that the exact linked skill remains registered in production.

Changed evidence, missing production linkage, Beta-only state, invalid identity, wrong confirmation, or an unsafe path fails closed without deletion.

## Execution boundary

- The close operation is a bounded foreground filesystem mutation.
- It may delete only one validated direct child of `Soul/proposals/skills` per invocation.
- It returns `complete`, `failed`, `awaiting_input`, `canceled`, or `blocked_for_human_review` and leaves no process running.
- It adds no watcher, polling loop, service, scheduled task, autonomous cleanup, or bulk-delete path.
- The already completed operator-requested removal of three old non-Beta proposals is runtime maintenance and is not generalized by this amendment.

## Verification

- All seven stages are deterministically covered.
- A Beta-only proposal cannot preview or execute closeout.
- A production-linked proposal can preview but cannot close with the wrong phrase or stale digest.
- Confirmed unchanged production closeout removes only the proposal directory.
- The production skill, registry, and shared diagnostic log remain.
- Application operations are explicitly allowlisted and typed.
- Skill Studio shows stage, linked skill, production linkage, preview, exact confirmation, and close result.
- Existing Skill Studio, dashboard, authentication, Review Center, privacy, and deployment regressions remain green.

## Human review gate

The owner reviews stage wording, skill linkage, production-only close affordance, deletion disclosure, and the post-close empty/selection behavior before merge.
