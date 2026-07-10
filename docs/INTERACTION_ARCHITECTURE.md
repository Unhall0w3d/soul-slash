
# Soul Interaction Architecture

Soul will build its own required interaction layer instead of depending on a third-party chat frontend.

Existing open-source frontends can inform design and may become optional clients later, but Soul's assistant runtime must remain owned by Soul.

## Principle

Soul is not only a model chat frontend.

Soul is a local-first assistant runtime with:

```text
conversation memory
project memory
skill registry awareness
natural-language intent routing
approval-gated skill execution
Codex/cloud/local model handoff controls
repo-aware development workflows
future voice input/output
```

A third-party UI can display messages. It should not define Soul's brain, skill policy, memory model, or action rules.

## Core pipeline

Every interface should feed the same internal pipeline:

```text
human utterance
→ chat/session context
→ intent router
→ capability and skill lookup
→ plan or clarification
→ safe response, skill execution, or handoff package
→ response rendering
→ memory/session update
```

This applies to terminal chat, single-shot CLI messages, future web UI, future OpenAI-compatible endpoints, and future voice input/output.

Voice should not have a separate brain. It is an input/output surface for the same chat pipeline.

## Interface order

```text
1. CLI chat
2. local persistent chat/session store
3. natural-language intent router
4. assistant-facing skill catalog
5. skill invocation planner
6. local HTTP API
7. optional web UI
8. optional OpenAI-compatible endpoint
9. voice input/output layer
```

## Near-term CLI targets

```bash
soul
soul "check if we have pending skills to build"
soul chat
soul chat "what skills do you have?"
soul chats
soul chat --new
soul chat --resume <chat_id>
soul chat --pin <chat_id>
soul chat --search "skill registry"
```

During early phases, implementation may remain under:

```bash
ruby bin/soul chat
ruby bin/soul chat "message"
```

## Local LLM versus skills

The local LLM should handle language-heavy, low-risk work:

```text
summarization
rewriting
conversation
intent classification
drafting plans
explaining structured results
human-readable response generation
```

Skills should handle deterministic or risky work:

```text
reading local state
writing files
changing system state
calling APIs
testing providers
querying registries
generating handoff packages
reviewing structured JSON
moving files
anything requiring exact auditability
```

Rule:

```text
If being wrong is merely annoying, the LLM can probably help.
If being wrong changes state, hides facts, breaks files, leaks secrets, or misreports system condition, use a skill.
```

## Third-party frontend posture

Third-party frontends may become optional clients. Soul should not require them.

Optional integration points:

```text
OpenAI-compatible /v1/chat/completions endpoint
native Soul HTTP API
read-only skill catalog endpoint
approval-gated skill planning/execution endpoint
```

## Non-goals for the first implementation

```text
web UI
voice
multi-user auth
vector database
always-on daemon
skill auto-execution
Codex auto-application
provider activation
background workers
```

Build the skeleton first. The floating sword can wait outside until it stops whispering.
