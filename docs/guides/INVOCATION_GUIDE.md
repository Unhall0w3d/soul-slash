# Invocation Guide

The Invocation Guide answers a different question from the production skill
list.

- The skill list inventories registered implementation units.
- The Invocation Guide explains what the Operator can ask Soul to do and how
  the complete human-facing workflow behaves.

One invocation may coordinate several skills, a deterministic conversation
handler, a Core transition, and multiple review gates.

## Dashboard use

Open **Invocations** from the Chat context rail. The guide loads only when
opened. Filter it by category or search its human-readable fields.

Selecting an entry shows required and optional information, Core behavior,
approval behavior, the returned result, the authority boundary, and one
example request.

Examples are inert text. Opening, filtering, selecting, or copying one never
runs a skill or authorizes an operation.

## Chat use

Ask:

```text
Show the invocation catalog.
List Creative invocations.
How can I invoke music production?
Show the Skill Studio inventory.
Show approved file roots.
Read file from root project at README.md.
```

These requests resolve deterministically and perform no mutation. Ordinary
discussion of music, weather, files, the screen, or a Core still remains
conversation unless it meets the owning invocation router's explicit request
shape.

## Core and approval behavior

The catalog describes Core requirements but cannot change a Core. A later
request that needs another Core must still present the existing active-work
check and exact transition action.

Catalog examples do not bypass generation previews, digest checks,
destructive-action gates, candidate review, Skill Studio gates, Self
Augmentation review, or external-publication authority.

## Public configuration

The curated definitions live in `config/invocation_catalog.yaml`. Entries
associated with production skills are checked against
`Soul/skills/registry.yaml`; an unknown production skill makes the invocation
visibly unavailable.

The application operation `invocations.list` accepts optional bounded
`category` and `query` filters. It always returns `read_only: true`,
`examples_are_authority: false`, and `mutation: none`.

The `files-inspect` entry is intentionally exact. `.env` configuration defines
approved roots; invocation wording can select a configured root but cannot add
one. See `docs/skills/FILES_INSPECT.md`.
