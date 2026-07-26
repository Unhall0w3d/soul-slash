# Project Timeline A1 Brief

## Human direction

Add a Dashboard page that presents Soul's project timeline and implementation
state across features, TODOs, pending tests, and deferred work. Seed it with the
current project state. Both the Operator and Soul must be able to inspect and
edit the same tracker through explicit GUI or Chat actions.

## Candidate scope

- One tracked public seed and one ignored owner-local JSON state file.
- Four roadmap horizons: `now`, `next`, `later`, and `backlog`, plus an
  `archive` classification used only by implemented inventory records.
- Seven states: `planned`, `in_progress`, `blocked`, `needs_review`,
  `validated`, `done`, and `deferred`.
- Explicit create and update operations with optimistic revision checking.
- Archive by setting `deferred` or `done`; no destructive deletion in A1.
- Dashboard timeline board, filters, summary counts, and edit form.
- Progressive feature records for implementation detail, technologies/models,
  interfaces, commands, references, acceptance, provenance, and notes.
- A compact implemented-feature inventory alongside active and pending work.
- Deterministic Chat controls for list, exact create, status change, and notes
  change.
- No file watcher, repository scanner, polling loop, inferred completion, or
  silent model-authored status change.

## Lifecycle and authority

Every request terminates as `complete`, `awaiting_input`, `failed`, or
`blocked_for_human_review`. Tracker state is planning evidence, not approval,
merge authority, execution authority, or proof that implementation passed.
