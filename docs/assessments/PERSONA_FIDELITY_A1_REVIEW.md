# Persona Fidelity A1 Review

## Candidate

Name: Persona Fidelity A1

Risk class: Low — conversation presentation and reversible chat metadata

Branch: `agent/persona-fidelity-a1`

Date: 2026-07-27

Status: `validated`

## Implementation summary

Soul's stable `soul.identity.v1` profile advances to version 9. The runtime now
leads with a concise affirmative delivery center and applies a balanced Gemma
projection or smaller Qwen projection of that same identity. Both explicitly
resist invented scene narration, diagnostic paraphrase of ordinary speech,
unnecessary menus, repeated `Operator` address, generic closings, and persona
tokens used as costume.

Three explicit commands disable, inspect, and re-enable persona expression for
only the active conversation. The setting lives in the existing chat metadata,
defaults enabled in other chats, and survives refresh or process restart.
Disabled mode replaces expressive identity and recent-style coaching with
neutral delivery guidance while retaining truth, privacy, evidence, routing,
approval, and memory boundaries.

## Files changed

```text
config/project_tracker_seed.json
docs/CURRENT_STATE.md
docs/SOUL_PERSONALITY.md
docs/assessments/PERSONA_FIDELITY_A1_REVIEW.md
docs/soul/IDENTITY_AND_STYLE_POLICY.md
docs/soul/PERSONA_FIDELITY_A1_BRIEF.md
lib/soul_core/chat_responder.rb
lib/soul_core/chat_store.rb
lib/soul_core/conversation_acknowledgment_controls.rb
lib/soul_core/conversation_context_builder.rb
lib/soul_core/conversation_identity_profile.rb
lib/soul_core/conversation_orchestrator.rb
lib/soul_core/conversation_persona_controls.rb
scripts/run-persona-fidelity-cross-core-eval.rb
scripts/verify-live-persona-contract.rb
scripts/verify-persona-fidelity-a1.rb
scripts/verify-soul-personality-foundation-phase40.rb
```

Owner-local Project Timeline state is updated separately.

## Commands run

```text
ruby scripts/verify-persona-fidelity-a1.rb
ruby scripts/verify-live-persona-contract.rb
ruby scripts/verify-soul-personality-foundation-phase40.rb
ruby scripts/verify-phase10-identity-style-foundation.rb
ruby scripts/verify-responsive-chat-and-web-research.rb
ruby scripts/verify-conversational-creative-workflow.rb
ruby scripts/verify-phase10-inspectable-interests-closeout.rb
ruby scripts/verify-core-orchestration.rb
ruby scripts/verify-project-timeline-a1.rb
ruby scripts/verify-multiturn-conversation-runtime-phase3.rb
ruby scripts/run-persona-fidelity-cross-core-eval.rb amd-free
ruby scripts/run-persona-fidelity-cross-core-eval.rb daily
git diff --check
```

## Deterministic results

The focused A1 verifier passes:

- one stable version-9 identity;
- balanced and compact projections;
- explicit diagnostic/menu restraint;
- non-authorizing persona behavior;
- deterministic explicit controls;
- ambiguous-language non-routing;
- persistence and per-chat isolation;
- neutral context with retained truth boundaries;
- exact microphone-test acknowledgement without model diagnostic drift;
- successful re-enable.

Existing live persona contract, personality foundation, Phase 10 identity,
responsive Chat/research, conversational creative workflow, inspectable
interests, Core orchestration, and Project Timeline regressions pass. The Phase
3 wrapper initially reported the expected repo-curation warning while this
review candidate was untracked; both the Phase 3 and Phase 1 curation wrappers
pass after intentional staging.

## Local LLM evaluation

Matched temporary-state runs completed on:

```text
Daily Core: Gemma 4 12B Instruct Q4_K_M / AMD Vulkan
AMD-Free Core: Qwen3 8B Q4_K_M / NVIDIA CUDA
```

Both final runs used the production 1,024-token output budget:

```text
Daily / Gemma:    41 / 41
AMD-Free / Qwen:  41 / 41
```

Both reported `finish_reason: stop` for every model-generated case. The exact
microphone check used the deterministic acknowledgement path. Persona disable,
neutral response, enable, and restored identity all passed.

The harness does not switch Cores itself, allows no cloud fallback, retains no
transcript, and cannot authorize safety or merge readiness. Core transitions
used the existing preview/digest/confirmation gate, and Daily Core was restored
after evaluation.

## Memory

Reads: ordinary approved conversation memory remains unchanged.

Writes/updates: none.

Forget behavior: none.

Persona mode is reversible operational chat metadata, not durable memory or a
new memory store. Forgetting the conversation removes it with the existing
chat boundary.

## Lifecycle states touched

```text
complete
awaiting_input
```

No persona control leaves work running.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Background polling added: no
Core or model switch added: no
Confirmation gate weakened: no
Skill routing changed: no
Structured Studio schema changed: no
Automatic identity mutation added: no
New memory store added: no
```

## Known weaknesses

- Prompt calibration improves the probability of the intended voice but cannot
  guarantee identical wording from quantized local models.
- The Qwen projection is intentionally smaller and may remain less nuanced
  than Gemma.
- Qwen can still favor a direct follow-up question and may become more
  mechanical or ornate across longer real conversations; the matched suite
  proves bounded representative turns, not indefinite stylistic consistency.
- Gemma still uses restrained metaphor in some supportive or affective turns.
  Operator review should decide whether that amount feels like Soul or remains
  too performative.
- Persona-off is currently an explicit Chat command rather than a visible
  composer toggle.
- Deterministic skill and evidence responses retain their bounded renderers;
  this slice does not post-process them to add personality.
- Operator conversation review was completed and approved on 2026-07-29.

## Human review checklist

```text
[x] Gemma casual response is Soul-specific without scene narration
[x] Qwen casual response avoids diagnostics, menus, and repeated Operator address
[x] Both models handle success, support, identity, and affect naturally
[x] Neither model invents environment, access, execution, or side effects
[x] Persona disable affects only the active conversation
[x] Neutral mode is concise and operationally unchanged
[x] Persona re-enable restores Soul's voice
[x] Structured creative and skill results remain valid
[x] No authority or persistence boundary changed
```

## Human review outcome

```text
Outcome: approved
Reviewer: Operator
Date: 2026-07-29
Decision summary: The previously completed live review is accepted. Persona
  Fidelity A1 meets the representative-conversation, structured-output, and
  conversation-local control expectations.
Required changes: none
```
