# Project Timeline

Project Timeline is Soul's shared implementation ledger. It records what is
active, queued, qualified for later, or deliberately retained in the backlog.
It is not a generated roadmap report and does not infer completion from tests,
commits, conversation, or model output.

## Where state lives

- `config/project_tracker_seed.json` is the public, neutral starter ledger.
- `Soul/private/project_tracker/state.json` is the ignored owner-local working
  state created from that seed on first use.
- Both the Dashboard and Chat operate on that same local state.

This keeps personal project decisions out of the public repository while
providing a useful initial timeline to another person who checks out Soul.

## Dashboard flow

Open **Administration → Project Timeline** in the top navigation.

The four columns are:

- **Now** — active implementation and immediate review.
- **Next** — cleanly queued follow-on work.
- **Later** — qualified expansion that is not current work.
- **Backlog** — retained possibilities without implied priority.

Completed and validated records use a separate internal `archive` horizon and
appear in **Implemented inventory** rather than being presented as backlog.

Use the status filter to narrow the board. **Active roadmap** omits completed
and deferred entries; **Implemented inventory** shows both `validated` and
`done` feature records. Select a card to open its scrollable detail flyout, or
select **New timeline item** to create one. Saving one form is the explicit
authority to write that item. Revision checks block stale browser edits instead
of silently overwriting newer state.

The detail flyout may progressively record:

- what was implemented or is planned;
- models, languages, runtimes, and other technologies;
- Dashboard, Chat, voice, command-line, or service interfaces;
- useful commands and invocation syntax;
- associated documentation and evidence;
- acceptance criteria, provenance, and working notes.

Completed foundation entries are pre-seeded as a compact implementation
inventory. Planned and active entries may carry the same information before
completion where the intended architecture is already known.

Supported states are `planned`, `in_progress`, `blocked`, `needs_review`,
`validated`, `done`, and `deferred`.

## Chat flow

Deterministic Chat controls are intentionally explicit:

```text
show project timeline
show timeline item track_foundation_creative_studios
mark timeline item track_example as needs review
update timeline item track_example notes: Live validation remains pending.
update timeline item track_example technologies: Ruby service and Dashboard JavaScript.
```

Creation uses eight pipe-separated fields:

```text
add timeline item: Title | Area | next | planned | medium | Summary | Acceptance criteria | Source
```

An exact item ID or exact title is preferred. Ambiguous references do not
change state.

Ordinary conversation about plans, TODOs, pending work, or future ideas never
updates the ledger. Soul must use an unmistakable timeline-item command or the
Operator must save the Dashboard editor.

## Lifecycle and limits

Every operation terminates as `complete`, `awaiting_input`, or
`blocked_for_human_review`. The ledger is capped at 300 items and 512 KiB.
There is no watcher, background loop, automatic scanner, inferred status
transition, or delete action in A1.

Run the deterministic verification with:

```bash
make verify-project-timeline
```
