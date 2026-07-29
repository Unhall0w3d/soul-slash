# Project Timeline A1 Human Review

```text
status: deterministic candidate complete; live Operator visual review pending
date: 2026-07-25
risk: Class 2 - explicit owner-local project state write
human_merge_approval: required
```

## What was implemented

- A top-level **Project Timeline** Dashboard page with Now, Next, Later, and
  Backlog horizons.
- A separate completed-feature inventory surface; completed and validated
  records use `archive` classification and are never presented as Backlog.
- Status filtering and summary counts for active, review, blocked, and
  validated/done work.
- One scrollable feature-record flyout with status, priority, implementation
  summary, technologies/models, interfaces, commands, references, acceptance
  criteria, notes, source, and optimistic revision checks.
- A curated tracked seed with 25 current project entries, including six compact
  completed/validated foundation records.
- Ignored owner-local working state shared by Dashboard and Chat.
- Deterministic Chat controls for listing, creating, changing status, and
  changing notes or implementation-detail fields, plus full inspection of one
  exact feature record.
- Skill-catalog entries and an Operator guide.

## Files changed

- `config/project_tracker_seed.json`
- `lib/soul_core/project_tracker_service.rb`
- `lib/soul_core/project_tracker_chat_controls.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/chat_responder.rb`
- `lib/soul_core/conversation_orchestrator.rb`
- `lib/soul_core/assistant_skill_catalog.rb`
- `Soul/skills/registry.yaml`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.css`
- `assets/dashboard/dashboard.js`
- `scripts/verify-project-timeline-a1.rb`
- `Makefile`
- `README.md`
- `docs/guides/PROJECT_TIMELINE.md`
- `docs/ASSISTANT_SKILL_CATALOG.md`
- `docs/CURRENT_STATE.md`
- `docs/ROADMAP.md`
- `docs/soul/PROJECT_TIMELINE_A1_BRIEF.md`

## Commands and deterministic results

- Ruby syntax checks for the service, controls, responder, orchestrator, and
  facade — PASS.
- `node --check assets/dashboard/dashboard.js` — PASS.
- JSON parse of `config/project_tracker_seed.json` — PASS.
- `ruby scripts/verify-project-timeline-a1.rb` — PASS (9 checks).
- `ruby scripts/verify-dashboard-self-improvement-navigation.rb` — PASS after
  extending its primary-navigation expectations for Project Timeline.
- `git diff --check` for the bounded implementation files — PASS.
- Live local Dashboard reload — PASS: 25 seeded items, six implemented
  inventory records, four populated roadmap horizons, dedicated
  implemented-inventory filter with the roadmap hidden, populated scrollable
  feature flyout, editor open/close, URL fragment persistence, and zero browser
  console errors.

Two broad legacy suites reached their existing repository-curation assertion
and reported the wider untracked candidate set from the current development
session. Their functional catalog/orchestrator assertions passed before that
curation-only failure; this is not a Project Timeline runtime failure.

## Local LLM eval

Not used. Timeline recognition and mutation are deterministic. Model output is
not execution authority and cannot silently change project state.

## Known weaknesses

- Initial seed entries are a reviewed snapshot, not a repository-derived live
  inventory.
- A1 does not delete items, attach dependencies, or render dates/Gantt views.
- Only explicit structured Chat creation is supported; natural conversation is
  deliberately not interpreted as an edit.
- Live visual and interaction review remains pending.

## Dashboard write-path repair · 2026-07-29

Normal-use review exposed that the Dashboard supplied the bounded timeline
`item` as an object and `expected_revision` as an integer, while the shared
application contract's generic type branch incorrectly required both values to
be strings. The service and UI were correct, but the request was rejected
before reaching the service.

The contract now recognizes the allowlisted `item` object and requires a
positive integer revision. The focused verifier exercises an actual update
through `ApplicationFacade`, matching the Dashboard request shape, so service-
only and snapshot-only tests cannot mask this path again.

## Memory and lifecycle

- Shared memory keys added: none.
- Public seed: `config/project_tracker_seed.json`.
- Owner-local state: `Soul/private/project_tracker/state.json`.
- Lifecycle states touched: `complete`, `awaiting_input`,
  `blocked_for_human_review`, `failed`.
- Item cap: 300. State cap: 512 KiB.
- No watcher, poller, scanner, daemon, network operation, or background
  continuation was added.

## Human review checklist

- [ ] Project Timeline remains readable at desktop and mobile widths.
- [ ] Seeded items reasonably represent current, next, later, and backlog work.
- [ ] Create and edit forms preserve the intended values after refresh.
- [ ] Status filtering and counts agree with visible state.
- [ ] Implemented inventory exposes useful architecture, model/language,
  interface, command, and reference details without overwhelming the board.
- [ ] A stale browser edit is blocked after another edit wins.
- [ ] `show project timeline` lists the same owner-local state.
- [ ] Explicit Chat status and notes edits update the Dashboard after refresh.
- [ ] Ordinary planning conversation does not mutate the ledger.
- [ ] No private tracker state appears in Git status.
