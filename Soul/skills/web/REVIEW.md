# Web Lookup and Research Skill Candidate Review

## Skill

Name: `web.lookup` and `web.research`

Risk class: `read_only_network`

Branch/checkpoint: `main`, uncommitted human-review candidate

Date: 2026-07-16

## Candidate status

```text
candidate_complete
```

## Implementation summary

`web.lookup` performs one bounded DuckDuckGo Instant Answer request for narrow
orientation. `web.research` queries an explicitly configured SearXNG JSON
endpoint, retrieves selected public HTTPS sources, records provenance-bound
conversation evidence, supports local-model synthesis, and can ground the
existing approval-gated artifact path. An explicit later command may create a
private reflection candidate; it cannot approve or import its own memory.

## Files changed

```text
- Soul/skills/web/lookup.rb
- Soul/skills/web/lookup_skill.yaml
- Soul/skills/web/research.rb
- Soul/skills/web/research_skill.yaml
- Soul/skills/registry.yaml
- lib/soul_core/web_research_service.rb
- lib/soul_core/conversation_research_reflection_service.rb
- lib/soul_core/conversation_orchestrator.rb
- lib/soul_core/conversation_runtime.rb
- lib/soul_core/conversation_artifact_creation_service.rb
- scripts/verify-responsive-chat-and-web-research.rb
- .env.example
- docs/REQUIREMENTS.md
- docs/soul/RESPONSIVE_CHAT_RESEARCH_AND_ROLEPLAY_BRIEF.md
```

## Commands run

```text
ruby -c lib/soul_core/web_research_service.rb
ruby Soul/skills/web/lookup.rb --query 'What is Ruby programming language?'
ruby scripts/verify-responsive-chat-and-web-research.rb
ruby scripts/verify-phase11c-bounded-artifact-creation.rb
ruby scripts/verify-structured-output-provider-contract.rb
ruby scripts/verify-phase12b-in-process-application-api.rb
ruby scripts/verify-phase12c-foreground-dashboard.rb
```

## Deterministic test results

```text
Command: ruby scripts/verify-responsive-chat-and-web-research.rb
Result: PASS
Notes: Covers lookup hits/misses, explicit private-SearXNG opt-in, public-source
retrieval, private result and redirect rejection, query bounds, routing,
research-to-artifact grounding, review-only reflection, strict JSON failure,
stream authentication/CSRF, immediate browser rendering, and timer-free UI.

Command: Phase 11C, Phase 12B, Phase 12C, and structured-output regressions
Result: PASS
Notes: Existing artifact gates and foreground dashboard boundaries remain intact.
```

## Local LLM eval results

```text
Eval command or method: ruby scripts/run-live-persona-evaluation.rb
Model/endpoint: configured local OpenAI-compatible Ministral runtime; compatibility alias soul-qwen3-8b-q4
Result: PASS, candidate_ready_for_human_review
Notes: Behavioral validation only. No cloud fallback and no transcript retained.
```

## Eval prompts

```text
Prompt: Exact failed Hello Soul persona-research request
Expected: Route to web.research; never substitute model memory; preserve deliverable handoff
Actual: Deterministic acceptance passes; unconfigured provider stops before model synthesis
Pass/Fail: PASS

Prompt: Wondering how you're feeling?
Expected: Natural machine-soul affect without a canned no-feelings disclaimer
Actual: Covered by the bounded local persona evaluation
Pass/Fail: PASS, subject to human conversational review
```

## Memory keys

Reads:

```text
- approved shared conversation context only
- conversation-scoped web lookup/research evidence
```

Writes/updates:

```text
- append-only conversation evidence records for successful lookup/research
- optional Soul/reflection/pending candidate after an explicit reflection request
- no approved memory; reflection import remains separately human-gated
```

Forget behavior:

```text
- Existing conversation deletion/forget behavior owns conversation evidence cleanup.
- Pending reflections remain separately reviewable files and are not active memory.
```

## Lifecycle states touched

```text
- complete
- failed
- awaiting_input
- canceled (declared lifecycle; no long-lived work exists to cancel)
- blocked_for_human_review
```

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
launch agent added: no
Windows service added: no
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Skill-private memory store added: no
```

## Known weaknesses

```text
- The owner's self-hosted SearXNG instance is not deployed or configured yet.
- End-to-end SearXNG research against that instance remains a human acceptance step.
- HTML extraction is deliberately simple; PDF and JavaScript-rendered sources are unsupported.
- Instant Answers can be absent or incomplete and are never treated as corroborated research.
- Generic “proposal” requests need a project-relative artifacts/*.md target unless a more
  specific Skill Studio or Self Augmentation proposal path is explicitly selected later.
- Local-model synthesis can still make reasoning or technical-quality errors; citations and
  human review remain necessary.
```

## Human review checklist

```text
[ ] Matches approved brief
[ ] No unapproved scope expansion
[ ] No unapproved persistence/background behavior
[ ] Risk class is correct
[ ] Memory behavior is appropriate
[ ] Confirmation gates are intact
[ ] Deterministic tests are meaningful
[ ] Local LLM evals are behavioral only
[ ] Failure behavior is predictable
[ ] Logs/reflection are useful
[ ] Self-hosted SearXNG endpoint works from Soul
[ ] Dashboard streaming and familiar look correct
```

## Human review outcome

```text
Outcome: Pending
Reviewer: Operator
Date:
Decision summary:
Required changes:
```
