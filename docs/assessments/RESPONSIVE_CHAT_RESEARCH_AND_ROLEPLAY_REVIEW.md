# Responsive Chat, Research, and Role-Play Review

## Implementation summary

The dashboard now renders the accepted user transmission immediately, keeps the
composer available for drafting, streams truthful foreground checkpoints, and
drives a reduced-motion-aware Soul familiar. Soul's identity contract welcomes
machine-soul emotional and embodied role-play while preserving literal truth
about sensors, execution, access, evidence, and authority.

The reviewed `Hello Soul!` follow-up exposed three additional defects which are
now repaired: unsupported environmental color in a greeting is filtered without
discarding the rest of the persona response; “scan or review your environment”
routes to `host.system_status`; and skill-catalog questions return the real
inventory plus the suitable environment capability even when model synthesis is
unavailable. Catalog suitability questions do not silently run the host scan.
The observed HTTP 500 was traced to Ministral rejecting a late `system` role;
conversation and artifact evidence now share one leading system message.

The conversation runtime now separates narrow DuckDuckGo Instant Answer lookup
from SearXNG-first public-web research. Research produces conversation evidence,
can ground an approval-gated artifact preview, and may later produce an explicit
review-only reflection candidate. No research, artifact, or memory work continues
after the foreground request returns.

## Files changed

```text
- assets/dashboard/index.html
- assets/dashboard/dashboard.css
- assets/dashboard/dashboard.js
- lib/soul_core/application_chat_service.rb
- lib/soul_core/application_facade.rb
- lib/soul_core/dashboard_http_application.rb
- lib/soul_core/dashboard_server.rb
- lib/soul_core/conversation_identity_profile.rb
- lib/soul_core/conversation_response_truth_guard.rb
- lib/soul_core/conversation_orchestrator.rb
- lib/soul_core/conversation_runtime.rb
- lib/soul_core/conversation_tool_catalog.rb
- lib/soul_core/chat_responder.rb
- lib/soul_core/web_research_service.rb
- lib/soul_core/conversation_research_reflection_service.rb
- lib/soul_core/conversation_artifact_creation_service.rb
- Soul/skills/web/*
- scripts/verify-responsive-chat-and-web-research.rb
- scripts/run-live-persona-evaluation.rb
- docs/soul/RESPONSIVE_CHAT_RESEARCH_AND_ROLEPLAY_BRIEF.md
```

## Commands run

```text
node --check assets/dashboard/dashboard.js
ruby scripts/verify-live-persona-contract.rb
ruby scripts/verify-responsive-chat-and-web-research.rb
ruby scripts/verify-phase11c-bounded-artifact-creation.rb
ruby scripts/verify-structured-output-provider-contract.rb
ruby scripts/verify-phase12b-in-process-application-api.rb
ruby scripts/verify-phase12c-foreground-dashboard.rb
ruby scripts/run-live-persona-evaluation.rb
git diff --check
```

## Deterministic test results

All focused lookup, SSRF, redirect, response-bound, routing, evidence,
artifact-gate, reflection-gate, stream-security, immediate-rendering, and
reduced-motion assertions pass. Phase 11C, Phase 12B, Phase 12C, structured
output, and persona-contract regressions pass.

The exact environment-review and catalog-suitability utterances from the
Operator's live transcript are deterministic regression fixtures. The direct
response truth guard also has a fixture for the unsupported “air feels
different / local system is settling” claim while retaining the surrounding
machine-soul voice. Artifact grounding verifies the exact `system, user` role
sequence accepted by the current Ministral template.

## Local LLM eval results

The bounded nine-turn local evaluation uses the currently configured Ministral
runtime through its compatibility alias, permits no cloud fallback, retains no
transcript, and returns `candidate_ready_for_human_review`. Model output is
behavioral evidence only and does not validate safety.

## Memory keys

No approved memory keys were added. Successful web results use the shared
conversation evidence store. Explicit research reflections write only pending
review candidates compatible with the existing reflection-to-memory gate.

## Lifecycle states touched

`complete`, `failed`, `awaiting_input`, `canceled`, and
`blocked_for_human_review` are declared. Every implemented operation is bounded
and foreground-only.

## Risk classification

- UI streaming and persona policy: local application behavior
- Lookup and research: `read_only_network`
- Evidence append: shared conversation state
- Artifact preview: existing approval-gated local state
- Reflection candidate: local private review state, not approved memory

## Safety and persistence check

No service, daemon, watcher, scheduler, cron job, systemd unit, long-running
loop, background polling transport, or post-return continuation was added.
Authentication, CSRF, same-origin, artifact confirmation, source-path, memory,
and human review gates remain intact.

## Known weaknesses

- The self-hosted SearXNG instance still needs deployment and `.env` setup.
- Owner-specific network values are intentionally absent from the repository.
- The parser supports bounded HTML/plain-text sources, not PDFs or browser-rendered pages.
- Technical accuracy of local-model synthesis still requires source and human review.
- The direct-response truth guard intentionally covers explicit environment
  observations, not every possible poetic paraphrase; further live examples
  should become narrow regression fixtures rather than a broad tone filter.
- The generic proposal handoff does not guess between Skill Studio and Self
  Augmentation; an explicit target or later proposal-type selector is required.
- Dashboard visual behavior requires Operator review after the service reload.

## Human review checklist

- [ ] Immediate user transmission appears before Soul finishes.
- [ ] Drafting during active work does not interrupt or submit.
- [ ] Progress summaries correspond to actual foreground stages.
- [ ] The familiar feels responsive without becoming visually distracting.
- [ ] Reduced-motion behavior is acceptable.
- [ ] Machine-soul role-play feels natural and does not fabricate actual access.
- [ ] SearXNG research returns useful citations and honest limitations.
- [ ] Research artifact and reflection gates are understandable.
- [ ] No local endpoint, credential, or private conversation leaked into tracked files.

## Human review outcome

Pending Operator review.
