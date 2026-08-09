# Music Vocal Feasibility and Failure Diagnostics A1 Brief

## Objective

Give the Operator deterministic, read-only evidence about whether a vocal music brief is likely to favor intelligible lyric delivery and what retained candidate evidence says after generation.

This slice does not promise exact lyric execution. ACE-Step treats the lyric field as a temporal script, but output remains probabilistic.

## Evidence basis

The retained 57-second and 71-second qualification projects use few words, so lyric density is not the primary concern. Their scripts combine very short isolated lines with unanchored performance tags and directions such as distant, broken, chopped, or nearly inaudible vocals. Those choices preserve an uncanny aesthetic while competing directly with intelligibility.

ACE-Step's published guidance recommends concise structural tags, moderate tag combinations, consistency between caption and lyrics, and lyric lines that usually fall near six to ten syllables. The diagnostic must describe departures as risks, not invalid inputs.

Sources:

- <https://github.com/ace-step/ACE-Step-1.5/blob/main/docs/en/Tutorial.md>
- <https://github.com/ace-step/ACE-Step-1.5/blob/main/docs/en/ace_step_musicians_guide.md>

## A1 vertical slice

1. Inspect one existing music project and its retained candidates.
2. Classify structural tags, vocal modifiers, lyric-line syllable estimates, and explicit intelligibility conflicts.
3. Summarize structured listening reviews and machine-heard sequence recall when available.
4. Display the result inside Music Studio before or after generation.
5. Offer deterministic recommendations without changing the project, starting a generation, or drafting a revision.

## Lifecycle

- `complete`: read-only diagnostic produced, including instrumental `not_applicable` results.
- `awaiting_input`: the project identifier is absent or invalid.
- `blocked_for_human_review`: retained project evidence fails integrity validation.

No background process remains after the request.

## Authority and risk boundary

- Risk class: read-only local evidence.
- Human review remains authoritative for musical quality and candidate disposition.
- Warnings are advisory and do not block the exact generation gate.
- The service does not rewrite captions or lyrics.
- The service does not infer failure from prose review notes; formal counts use structured review fields and retained analysis.
- No new memory store, service, timer, model call, or network request is introduced.

## Acceptance criteria

- Instrumental projects return `not_applicable` without false warnings.
- Standard anchored tags are distinguished from unanchored performance-only tags.
- Explicit masking language is surfaced with exact evidence terms.
- Candidate summaries distinguish reviewed, unreviewed, failed, partial, and analyzed attempts.
- Repeated structured lyric failures are visible without counting an unreviewed attempt as failed.
- Music Studio renders the evidence and recommendations for a selected project.
- Deterministic tests cover clear, risky, instrumental, and repeated-failure cases.
