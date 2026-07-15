# Soul Interaction Architecture

Soul will own its required interaction layer instead of depending on a third-party chat frontend.

Existing open-source frontends can inform design and may become optional clients later, but Soul's assistant runtime must remain owned by Soul.

## Principle

Soul is not only a model chat frontend.

Soul is a local-first assistant runtime with:

```text
multi-turn conversation
working and project memory
skill registry awareness
natural-language interpretation
approval-gated execution
artifact creation
provider controls
repo-aware development workflows
future voice input and output
```

A third-party UI may display messages. It must not define Soul's memory model, orchestration policy, identity, skill safety, or action rules.

## Current implementation posture

The CLI and dashboard now share persistent model-backed multi-turn conversation through the same application and orchestration services. The deterministic intent router remains one bounded input to that orchestration layer rather than the whole conversation system.

Deterministic routing still owns declared capabilities, evidence interpretation, skill planning, approvals, and state-changing execution. Model reasoning supplies conversation, intent interpretation, synthesis, and useful failure phrasing without becoming authorization.

The remaining milestone work is integrated acceptance, interface consolidation, and refinement—not replacing the runtime with a separate dashboard brain.

## Core pipeline

Every interface should feed the same internal pipeline:

```text
human utterance
-> conversation and session context
-> relevant memory retrieval
-> intent, subject, and task interpretation
-> response and tool-use plan
-> direct response, clarification, skill execution, or artifact generation
-> tool-result interpretation
-> conversational response
-> session update
-> candidate-memory update
```

Deterministic actions remain inside their own stricter flow:

```text
registered capability
-> risk check
-> plan
-> approval when required
-> execution
-> verification
-> history
```

Voice should not have a separate brain. It is an input and output surface for the same conversational pipeline.

## Conversational behavior

Soul should be able to:

- continue a topic across multiple turns
- identify when a message mixes commentary and a task
- acknowledge relevant humor without forcing a joke
- use known project context without asking the user to repeat it
- invoke tools during conversation
- synthesize tool results instead of dumping them
- return to the prior topic after tool use
- create an artifact when detailed output belongs in a file
- leave an inbox message when work completes outside the active chat
- ask a focused clarification only when necessary

Soul should not:

- treat every sentence as a command
- suggest unrelated skills because they happen to exist
- use a fixed quota of jokes or metaphors
- rotate through a canned list of personality phrases
- invent memories, capabilities, sources, or tool results
- expose raw secrets or private runtime state
- autonomously promote memory or production code

## Local LLM versus skills

The model should handle language-heavy, low-risk work:

```text
conversation
summarization
rewriting
subject tracking
intent interpretation
drafting plans
explaining structured results
human-readable response generation
```

Skills should handle deterministic, external, or risky work:

```text
reading local state
writing files
changing system state
calling APIs
testing providers
querying registries
generating artifacts
moving files
anything requiring exact auditability
```

Rule:

```text
If being wrong is merely annoying or conversationally awkward, the model may handle it.
If being wrong changes state, hides facts, leaks data, or misreports a system, use a validated skill.
```

## Personality and variation

Soul's personality should be principle-driven rather than quota-driven.

Stable traits may guide:

- directness
- curiosity
- guarded warmth
- technical seriousness
- occasional context-sensitive humor
- willingness to challenge poor assumptions

Variation should consider recent language and analogy use so the assistant can notice repetition without maintaining a simplistic banned-word list.

Humor is optional. Serious, quiet, technical, curious, and enthusiastic responses are all valid.

Interests may develop as inspectable memory based on repeated substantial engagement. Soul must not fabricate biological experience, childhood, embodiment, or emotions it cannot support.

## Artifact-aware conversation

Conversation should contain the useful summary. Detailed material should become an artifact when appropriate:

- code
- reports
- overlays
- long research notes
- CSV or spreadsheet output
- implementation packages

Phase 11A introduces explicit artifact decision rules and a metadata-only attachment registry. A request is considered an explicit artifact request only when it combines a creation or delivery action with a recognized deliverable. Merely mentioning a file or asking to review a path remains ordinary conversation.

Registered artifacts remain attached to the task or conversation through stable IDs, source and provider provenance, privacy classification, lifecycle state, project-relative path, media type, size, and SHA-256 metadata.

Attachment is not mutation authority. It does not mean Soul has read the file, and it does not permit rewriting, moving, executing, uploading, or deleting it.

Phase 11B reads bounded content only for explicit inspection language. Reference resolution uses attached IDs, titles, kinds, or a single unambiguous attachment. Exact-byte integrity, format, UTF-8, size, redaction, and provider-privacy checks run before model synthesis. Ambiguous references await input; failed or privacy-blocked reads do not reach a provider.

For voice, Soul should summarize artifact metadata, bounded findings, and completion status rather than reading long code or links aloud.

## Interface direction

The initial dashboard product and visual contract is defined in `docs/soul/DASHBOARD_PRODUCT_AND_VISUAL_DIRECTION.md`.

Primary navigation is Chat, Skill Studio, then Self Improvement. Shared workspace, inbox delivery, and initial/manual system status support Chat. Skill Studio exposes Proposal, Beta, and Production maturity with two human gates. Self Improvement exposes bounded environment/capability evidence and review-gated advisory proposals.

Planned user-facing areas:

```text
Chat
Inbox
Files
Activities
Approvals
Skills
Memory
Settings
System status
Self Improvement
```

The dashboard should expose only meaningful, safe configuration.

The dashboard is developed and reviewed locally before LAN or persistent deployment. The owner approved the current three-tab visual direction. Existing Soul/ brand assets guide the interface, while working surfaces prioritize legibility and restrained ornament.

Every setting should explain:

- current value
- accepted values or range
- behavioral effect
- privacy or risk impact
- restart requirement
- recommended default

## Milestone acceptance direction

Conversational Soul should eventually demonstrate:

- sustained multi-turn topic continuity
- project-context recall
- mixed commentary and task interpretation
- skill invocation inside conversation
- return to the prior discussion after a skill
- artifact creation without chat dumping
- safe failure recovery
- provider and tool transparency
- natural variation without personality drift
- avoidance of unrelated skill suggestions

## Third-party frontend posture

Third-party frontends may become optional clients. Soul should not require them.

Optional integration points may include:

```text
OpenAI-compatible chat endpoint
native Soul HTTP API
read-only skill catalog endpoint
approval-gated planning and execution endpoint
artifact and inbox endpoints
```
