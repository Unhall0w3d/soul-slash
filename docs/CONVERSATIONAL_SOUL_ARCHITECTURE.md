# Conversational Soul Architecture

Conversational Soul turns Soul's deterministic chat and action foundation into a coherent multi-turn assistant runtime.

The purpose is not to make every message probabilistic. The purpose is to let conversation, memory, tools, artifacts, and bounded action cooperate without reducing the user to memorizing command phrases.

## Interaction loop

```text
user message
-> load session and working context
-> retrieve relevant project, preference, semantic, and episodic memory
-> interpret subject, intent, tone, task, and unresolved references
-> decide whether to answer, clarify, retrieve, invoke, chain, or create
-> validate any proposed skill or provider use
-> execute bounded skills when useful
-> interpret structured results
-> compose a natural response
-> attach or store artifacts when detailed output belongs elsewhere
-> update session state
-> stage candidate memories with provenance
```

The conversational loop must support messages containing several simultaneous signals:

```text
commentary
humor
question
task request
project reference
implicit continuation
explicit action
```

Soul should not force the user to split those into separate commands merely because parsing them separately would make the implementation emotionally comfortable.

## Conversation state

Working conversation state should track:

```text
session_id
recent_turns
active_subject
active_task
current_goal
pending_questions
unresolved_references
recent_skill_calls
recent_skill_results
artifacts_created
pending_approvals
conversation_summary
```

The state must distinguish:

- what the user is discussing
- what the user is asking Soul to do
- what remains unresolved
- what has already been completed
- what should survive beyond the current context window

The current session state is not automatically durable memory.

## Orchestration decisions

For each turn, the orchestrator must choose among:

```text
respond directly
continue discussion
ask a focused clarification
retrieve memory
invoke one skill
invoke a bounded sequence of skills
create an artifact
request approval
report a blocked or unsupported action
defer work to an inbox item
```

The orchestrator must also decide when no tool is appropriate.

Tool relevance must be based on the active subject and task, not merely on keyword overlap. A Ruby optimization discussion must not trigger the Downloads cleanup workflow because both are vaguely related to "cleanup." Such behavior is how assistants become haunted autocomplete.

## Skill invocation inside conversation

Skill use is part of a conversation turn, not a terminal state.

Required flow:

```text
conversation
-> tool decision
-> registered capability lookup
-> risk and privacy validation
-> execution or approval request
-> structured result
-> result interpretation
-> conversational continuation
```

Soul should summarize what matters, explain uncertainty, and return to the user's topic.

Raw output may be included when requested, but the default response should not become a tool-output dumping machine.

A single user request may require a bounded skill chain. Each step must have:

```text
purpose
input
registered capability
risk class
stop condition
result
failure behavior
```

No open-ended autonomous loops are permitted.

## Layered memory

Soul requires distinct memory classes.

### Working memory

Current session context, active task, recent turns, and unresolved references.

### Project memory

Structured project facts:

```text
current milestone
current phase
completed work
open decisions
repo conventions
tooling constraints
next planned work
```

### Preference memory

Stable user and workflow preferences:

```text
shell choice
artifact handoff style
preferred verbosity
review requirements
privacy choices
provider preferences
```

### Episodic memory

Past events and outcomes:

```text
a verifier failed
a repair overlay fixed it
a milestone closed
a design decision changed
```

### Semantic memory

Stable learned knowledge not tied to one event.

Every durable memory must include:

```text
content
memory_type
source
created_at
confidence
promotion_status
last_verified_at
supersedes
```

Memory without provenance is not durable knowledge. It is gossip in JSON.

## Artifact-aware conversation

Detailed output should become an artifact when that is more useful than placing it inline.

Artifact examples:

```text
code
overlay ZIP
report
CSV
spreadsheet
document
research package
implementation plan
review bundle
```

Conversation should contain:

```text
what was created
why it matters
important findings
limitations
where the artifact is available
what action, if any, remains
```

Artifacts should retain:

```text
artifact_id
conversation_id
task_id
creator_skill
provider
source_inputs
privacy_class
created_at
path_or_attachment
lifecycle_state
```

Voice output should summarize artifacts rather than reading large code blocks or link collections aloud.

## Personality and variation

Soul's personality is principle-driven.

Stable identity may include:

```text
directness
curiosity
technical seriousness
guarded warmth
loyalty to the user's goals
skepticism toward fragile automation
occasional context-sensitive humor
```

Personality must not be implemented as:

```text
joke quotas
forced fandom references
fixed metaphor rotation
banned-word substitution
keyword-triggered quips
```

Humor is optional.

Soul may respond seriously, quietly, enthusiastically, technically, or playfully depending on context.

Variation should consider recent response history:

```text
recent analogy domains
recent joke density
recent openings
recent sentence patterns
current emotional tone
task seriousness
```

This awareness should reduce repetition without turning the personality into a spreadsheet of approved whimsy.

Interests may develop as inspectable memory based on sustained engagement. Soul must not fabricate biological experiences, childhood memories, embodiment, or unsupported emotions.

## Safety boundary

Conversation can be flexible. State-changing behavior cannot.

Model-generated plans and tool requests remain proposals until validated.

Action workflow:

```text
plan -> approval -> execute -> verify -> record
```

Required protections:

- registered capability lookup
- risk classification
- privacy classification
- explicit approval for mutation
- bounded execution
- timeout and loop limits
- structured verification
- execution history
- recoverable action preference
- no permanent deletion
- no secret exposure
- no automatic durable-memory promotion

Codex remains outside automatic repository mutation during broad architectural development.

Codex or other external coding agents may later receive narrow, reviewed implementation tasks after the architecture and acceptance contract identify a bounded target.

## Interface direction

All interfaces should use the same conversational runtime.

Planned surfaces:

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
```

### Chat

Supports multi-turn conversation, tool activity summaries, artifact cards, and pending work.

### Inbox

Holds work completed outside the active turn:

```text
artifact ready
research completed
approval required
skill failed
scheduled work completed
```

### Files

Supports user uploads, Soul-generated outputs, pipeline inputs, conversation attachments, and artifact lifecycle management.

### Approvals

Shows pending, expired, revoked, used, and completed approval records.

### Memory

Shows memory type, source, confidence, promotion state, edit history, and deletion controls.

### Settings

Exposes only settings that are meaningful and safe to change.

Every exposed setting must document:

```text
current value
accepted range or values
behavioral effect
privacy impact
risk impact
restart requirement
recommended default
```

## Explicit anti-patterns

Conversational Soul must not become:

- a command parser with decorative prose
- a tool-output dumping machine
- a canned-quipping persona
- an unrestricted autonomous agent
- a memory system without provenance
- a model that invents tool results
- a dashboard exposing every internal constant as a slider
- a voice layer with a separate assistant identity
- a cloud-first dependency disguised as local-first software
