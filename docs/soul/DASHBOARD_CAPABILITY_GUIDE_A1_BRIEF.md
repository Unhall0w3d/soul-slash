# Dashboard Capability Guide A1 Brief

Status: Operator-authorized implementation slice

## Purpose

Give Soul a grounded answer when the Operator asks what can currently be done
through Chat in a Dashboard surface. The answer must distinguish implemented
conversational mappings, partial mappings, and Dashboard-only review gates
without dumping the entire skill registry or invoking anything.

## Approved scope

- Add one read-only, registry-backed conversational capability guide.
- Route only explicit discoverability questions to it.
- Describe required user inputs, Core implications, and retained authority
  boundaries for Chat, the creative Studios, Project Timeline, Core control,
  Skill Studio, Self Assessment, Self Augmentation, and Review Center.
- Keep ordinary statements about Dashboard development or Studio preferences
  in natural conversation.
- Register the guide as a production read-only capability.

## Boundaries

The guide does not:

- execute a skill, generate media, switch a Core, create a proposal, mutate
  project state, or approve a review gate;
- claim every Dashboard button is conversationally mapped;
- infer authorization from the question or from model output;
- create a daemon, watcher, queue, service, or background process.

Every guide request terminates `complete` with `Mutation: none`, or fails in the
existing foreground Chat request.

## Acceptance

- `What can you do through the dashboard?` returns a bounded overview.
- A named Studio question returns its required inputs and authority boundary.
- Partial and Dashboard-only coverage is visibly distinguished.
- `I'm working on your dashboard capabilities` remains ordinary conversation.
- The existing skill, creative, Core, and Studio gates are unchanged.
