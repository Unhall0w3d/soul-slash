# Recent Style Awareness

## Purpose

Phase 10B gives Soul bounded awareness of how its recent assistant responses are shaped so it can avoid repetitive delivery without inventing a new personality or rewriting durable identity.

The feature is observational. It analyzes only the recent assistant turns already present in the current chat context.

## Signals

The analyzer can report:

- repeated openings;
- repeated closings;
- repeated short sentences;
- repeated response structures;
- repeated generic limitation disclaimers.

The default window is eight assistant turns. At least three assistant turns are required before variation guidance is eligible.

## Runtime use

`ConversationContextBuilder` asks `ConversationStyleAnalyzer` to inspect recent chat messages. When repetition signals exist, a small set of variation suggestions is appended to the system context.

The runtime also exposes summary metadata:

- window size;
- assistant sample count;
- eligibility;
- signal types;
- guidance count;
- identity-mutation status;
- persistent-style-profile status.

Raw responses are not copied into the metadata or deterministic inspection output.

## Priority boundary

Variation is lower priority than:

1. truth and factual accuracy;
2. safety boundaries;
3. deterministic routing;
4. grounded evidence;
5. approval requirements;
6. the user’s requested output format.

A response should remain repetitive when repetition is needed for precision, legal wording, safety instructions, command accuracy, or a user-requested template.

## Identity and memory boundary

Recent-style analysis:

- does not mutate `soul.identity.v1`;
- does not create memory records;
- does not create a persistent style profile;
- does not infer interests or biography;
- does not rewrite previous messages;
- does not approve any action.

## Inspection controls

The following deterministic commands are read-only:

```text
style help
show recent style
show variation policy
```

`show recent style` reports normalized signal summaries and guidance, not complete response bodies.

## Future work

Reviewed interests and longer multi-turn identity/variation closeout remain later Phase 10 work.
