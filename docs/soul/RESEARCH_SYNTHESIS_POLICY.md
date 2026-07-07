# Research Synthesis Policy

Research synthesis must separate source retrieval from synthesis.

## Pipeline

Recommended pipeline:

```text
source collection
→ source filtering
→ citation extraction
→ synthesis
→ review packet
```

## Source bundle rule

`research.synthesize` must synthesize supplied source bundles.

If no source bundle exists, the output must be labeled:

```text
unguided draft analysis
```

It must not be labeled sourced research.

## Cloud model role

A cloud model is a synthesis engine over supplied sources unless the provider has a verified search/grounding feature available under the configured account tier.

Cloud models are not themselves sources.

## Citation requirement

Research output should cite source bundle IDs or extracted source references.

A polished paragraph with no source evidence is not research. It is confident fog wearing a tie.

## Private content

Private repo excerpts, user memory, credentials, and sensitive documents must not be sent to cloud providers unless explicitly approved in the skill brief.

## Initial scope

The first research overlays should collect user-provided source bundles before implementing any retrieval/browsing skill.
