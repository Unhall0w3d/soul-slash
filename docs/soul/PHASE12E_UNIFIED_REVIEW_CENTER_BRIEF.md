# Approved Brief: Phase 12E Unified Review Center

```text
brief_status: approved by human owner direction to proceed with documented Phase 12E
implementation_authorized: yes
material_visual_review_required: yes
approval_authority_change: no
new_persistent_process: no
new_memory_store: no
```

The owner directed Soul development to proceed after the documented next phase was identified as Phase 12E unified approvals and activity views. This brief defines the smallest complete interface slice. Human visual/product review remains required before merge.

## Purpose

Add one unified supporting surface where the administrator can inspect active approval state and recent bounded execution activity without leaving the dashboard or confusing dashboard authentication with domain authorization.

## Product placement

The primary dashboard hierarchy remains exactly:

```text
Chat
Skill Studio
Self Improvement
```

Phase 12E adds a header-level **Review Center** control. It opens a bounded supporting drawer/dialog over the current primary tab. It is not a fourth assistant brain, primary tab, approval system, or activity store.

The Review Center contains:

- a summary strip for pending approvals, recent activity, blocked outcomes, and failed outcomes;
- an Approvals view using the existing redacted `approvals.pending` projection;
- an Activity view using the existing bounded `activities.recent` projection;
- manual refresh and bounded activity filters;
- a selected-record detail pane containing only the fields already approved for the application facade.

## Data and privacy boundary

The implementation must reuse:

```text
ApprovalTokenStore → ApplicationFacade approvals.pending
ChatExecutionHistory → ApplicationFacade activities.recent
```

Approval records may show:

- stable redacted approval reference;
- skill ID;
- lifecycle status;
- issue and expiry time;
- scope digest and bounded scope-key names;
- an explicit notice that the authorization value is not exposed.

Activity records may show:

- timestamp;
- source and skill ID;
- status, risk, success, and execution state;
- confirmation requirement and exit status;
- bounded blocked-category labels.

The browser must not receive approval token values, full approval scope values, private request messages, export paths, credentials, hidden reasoning, raw exceptions, or unrelated environment information.

## Authority boundary

Inspection is not approval. This first unified slice is inspect-and-navigate only.

It must not:

- approve, revoke, consume, clear, or execute an approval;
- replay or retry an activity;
- clear, prune, or export execution history;
- turn a selected row, generic click, dashboard session, or model response into authorization;
- duplicate Gate 1 or Gate 2 actions already owned by Skill Studio;
- weaken any existing exact-confirmation or preview-digest gate.

The interface should explain where action belongs: Skill Studio for proposal/Beta gates and Chat or the originating bounded workflow for execution-scoped approvals.

## Interaction and lifecycle

- Opening Review Center performs one foreground bounded load of both projections.
- Manual refresh performs one new bounded load.
- Activity filters perform one bounded request for the selected server-side filter.
- No polling, timer, watcher, background loop, or continuation is added.
- Empty, loading, complete, failed, and selected states are visible.
- Closing the surface returns focus to the opener and leaves the current primary tab intact.
- Each request terminates as `complete`, `failed`, `awaiting_input`, `canceled`, or `blocked_for_human_review` through the existing facade contract.

## Visual direction

- Preserve the restrained operational-instrument language already approved.
- Use Ember Gold only for human-attention and approval state.
- Use Spectral Teal for verified/executed state and violet for active focus.
- Do not encode status through color alone.
- Keep the surface usable at desktop, tablet, and narrow phone widths.
- Respect keyboard focus, semantic tabs, dialog behavior, reduced motion, and readable contrast.

## Deterministic acceptance

- `application.bootstrap` reports Review Center availability without adding a fourth product tab.
- Existing application projections remain capped and redacted.
- The document includes the Review Center opener, summary, Approvals/Activity subviews, detail pane, refresh, close, empty, and status regions.
- JavaScript calls only registered application operations and contains no interval, timeout, polling, mutation, approval-execution, history-clear, or history-export behavior.
- Selection and filtering render with text-safe DOM APIs.
- Authentication, Phase 12C, Skill Studio, Self Improvement, protected deployment, and privacy regressions remain green.
- A human review artifact records implementation, tests, weaknesses, lifecycle, memory, risk, and visual checklist.

## Risk classification

```text
Class 1: bounded read-only projection of private local operational metadata
```

## Human review gate

The owner must review:

- whether Review Center belongs in the header as a supporting surface;
- hierarchy and density;
- approval-versus-authentication clarity;
- usefulness of approval and activity details;
- empty/loading/failure presentation;
- desktop and mobile behavior;
- desired later actions, links, filters, or additions.

Passing tests produces a candidate. It does not approve the visual design or merge.
