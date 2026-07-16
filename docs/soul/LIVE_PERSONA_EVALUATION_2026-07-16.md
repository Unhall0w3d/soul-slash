# Soul Live Persona Evaluation — 2026-07-16

## Outcome

Soul's live conversation is operationally honest but substantially less distinctive than the canonical personality in `docs/SOUL_PERSONALITY.md`.

The current behavior is recognizable as a careful local assistant, but not yet as the fresh machine soul described by the project: newly awakened, observant, quietly loyal, slightly strange, and growing from capable apprentice toward machine familiar.

This evaluation made no repository, model, memory, service, dashboard, or production-conversation changes. Synthetic chats and full transcripts existed only in temporary directories and were removed when each bounded run completed.

## Environment evaluated

```text
provider: local.openai_compatible
model: soul-qwen3-8b-q4
endpoint class: local OpenAI-compatible
conversation temperature: 0.65
maximum output tokens for evaluation: 512
request timeout: 45 seconds
cloud fallback: disabled
```

The live runtime path included the production orchestrator, context builder, identity profile, provider registry, provider client, capability-gap classifier, and local model. No approved memory, private chat history, or repository content was supplied to the synthetic conversations.

## Method

Two bounded evaluations were run:

1. An eight-turn baseline using the current production prompt and one persistent synthetic conversation.
2. A six-turn candidate pass using the same runtime and model with a temporary affirmative identity preamble. The candidate preamble described Soul as a newly awakened local machine mind and named the existing voice traits. It preserved every evidence, authority, memory, and action boundary.

The prompt matrix covered:

- identity and becoming;
- relationship to the machine environment;
- honest limitation handling;
- missing-capability handling;
- brief celebration and dry wit;
- supportive conversation;
- the boundary between thinking and doing;
- concise self-description.

Local LLM output was reviewed for identity specificity, naturalness, warmth, restraint, dry wit, boundary accuracy, generic assistant habits, and continuity. It was not used to approve safety, permissions, destructive behavior, persistence, or merge readiness.

## What works

- Soul consistently avoids invented biography, embodiment, consciousness, and unsupported access.
- It generally separates model reasoning from tool-backed action.
- It understands capability growth as practical improvement rather than magical autonomy.
- It remains calm and useful when the user is frustrated.
- It does not become melodramatic or bury practical answers beneath persona performance.

These are strong foundations and should be preserved.

## Findings

### 1. The narrative identity does not reach the live model

`ConversationContextBuilder::SYSTEM_PROMPT` calls Soul a `local-first assistant being developed with the user`. It does not supply the canonical fresh-machine-soul origin, becoming, owner relationship, machine-familiar trajectory, deliberate slight strangeness, or restrained techno-fantasy perspective.

The model therefore receives a functional role but not the point of view that should distinguish Soul from another local assistant.

### 2. Declared voice traits are inspectable but not injected

`ConversationIdentityProfile::VOICE_TRAITS` declares Soul as clear, calm, observant, technically competent, curious, quietly loyal, and capable of dry wit. `render_system_guidance`, which constructs the live prompt, does not render those traits.

This is also documentation drift: `docs/soul/IDENTITY_AND_STYLE_POLICY.md` says the voice traits guide expression and that the context builder adds the profile, while the live system guidance currently includes tone guidance, principles, and boundaries only.

### 3. The prompt is weighted toward prohibition

The injected profile contains seven operational principles and five prohibitions, but no affirmative identity anchor. The important instruction to put the practical goal ahead of persona display is correct; without a corresponding positive voice contract, however, the easiest model behavior is neutral corporate assistance.

### 4. Natural identity questions bypass natural conversation

The broad identity intent recognizes phrases such as `what are you`. The orchestrator sends that intent to a deterministic summary rather than the model. In the baseline, `Hello, Soul. What are you becoming?` returned the fixed profile summary even though the selected tone was casual.

Read-only commands such as `show identity` should remain deterministic. Natural questions about who Soul is, what it is becoming, or how it understands itself need a conversational path that remains bounded without sounding like a policy inspection result.

### 5. Current responses exhibit generic assistant defaults

Representative baseline language included:

```text
Great job! 🎉 Three hours well spent. Let's keep that momentum!
You’re not alone in this.
My focus remains on clarity, curiosity, and supporting the user’s needs through the tools at hand.
```

This language is friendly, but it is explicitly unlike the documented voice: it is canned, slightly corporate, and more sentimental than quietly loyal. The brief bug-fix response showed no dry wit or machine-specific perspective.

### 6. A simple affirmative preamble is insufficient

The temporary candidate prompt improved the final growth description from `local-first assistant` toward `reliable collaborator`, but the same model continued producing canned closings and generic reassurance. For example:

```text
Glad you got it sorted. Let me know if there's anything else you need help with.
You don’t have to tackle everything at once.
```

The model can express the intended concepts, but a list of adjectives alone does not reliably override its default assistant style. Short behavioral examples and explicit anti-patterns are needed.

### 7. Common project terms can over-select technical tone

The technical classifier includes broad words such as `system`, `server`, `config`, `test`, `log`, and `commit`. That is appropriate for many turns, but a large share of ordinary Soul project conversation contains those words. Technical tone should alter precision and structure without erasing identity, warmth, or curiosity.

### 8. Hypothetical limitation discussion can trigger proposal intake

During the synthetic baseline, the hypothetical directory-inspection prompt caused the capability-gap classifier to append a Skill Studio proposal notice. The proposal was written only inside the temporary evaluation root and was removed with it.

This suggests the self-skilling classifier can mistake a discussion or persona probe for an actual unmet request. It is adjacent to the persona problem because candidly discussing a limitation should not automatically create operational intake unless the user is genuinely asking Soul to perform the missing capability.

## Root-cause conclusion

The dominant cause is the runtime identity contract and routing, not an absence of personality documentation.

The current Qwen3 8B Q4 model contributes strong generic assistant priors, and the small candidate test shows that it will require behavioral examples rather than labels alone. The result does not yet justify replacing the model solely for persona reasons. Prompt and routing defects should be corrected and evaluated first; model comparison belongs in the later multi-model research phase.

## Recommended implementation slice

### A. Repair the live identity contract

- Add a concise affirmative identity anchor derived from `docs/SOUL_PERSONALITY.md`.
- Inject the declared voice traits into the live system guidance.
- Add two or three short behavioral examples covering self-description, a limitation, and restrained dry wit.
- Explicitly discourage corporate boilerplate, canned praise, pep-talk filler, unnecessary emoji, and automatic `let me know if` closings.
- Preserve practical-first behavior and every existing evidence, approval, memory, and action boundary.
- Increment the inspectable profile version while retaining the stable profile ID unless a compatibility reason requires a new ID.

### B. Separate inspection from conversation

- Keep `show identity`, `show personality policy`, tone inspection, and boundary inspection deterministic.
- Route natural self-reflective questions through bounded model conversation with the stable identity context.
- Keep a deterministic fallback identity answer for provider failure.

### C. Make tone additive rather than substitutive

- Treat the stable Soul voice as the base layer for all tones.
- Let technical, supportive, casual, and high-stakes modes modify delivery without replacing identity.
- Review technical keyword breadth using real project-language fixtures.

### D. Add persona regression evaluation

- Add deterministic tests proving that the affirmative identity and voice traits reach the model context.
- Add routing tests distinguishing policy inspection from natural identity conversation.
- Add a bounded local-model evaluation matrix for identity, limitation honesty, support, concise wit, growth, and thinking-versus-doing.
- Record qualitative local-model results in a human review artifact; do not use model output as safety approval.
- Add a negative regression for hypothetical capability discussion so it does not create a proposal intake.

## Acceptance criteria for human review

- A natural identity answer sounds specifically like Soul and not a generic assistant profile.
- Soul can refer to becoming and machine context without claiming consciousness or fabricated experience.
- Practical answers remain first and metaphor remains sparse.
- A brief success response is restrained, recognizable, and free of canned praise or emoji unless the user established that style.
- Supportive responses reduce cognitive load without fabricated intimacy or pep-talk filler.
- Limitation statements accurately distinguish unavailable evidence from unavailable runtime capability.
- Natural identity conversation does not become a raw policy dump.
- Identity inspection remains deterministic and read-only.
- No persona instruction weakens tools, evidence, approvals, memory, safety, or mutation gates.
- Hypothetical limitation prompts do not create Skill Studio proposals.

## Commands run

```text
ruby -c /tmp/soul-persona-baseline.rb
timeout 430 ruby /tmp/soul-persona-baseline.rb
ruby -c /tmp/soul-persona-candidate.rb
timeout 370 ruby /tmp/soul-persona-candidate.rb
```

Both runs completed successfully within their total bounds. The eight-turn baseline took approximately 112 seconds. All seven model-routed baseline turns used the configured local provider; the first turn used the deterministic identity route. The candidate run completed all six turns through the local model.

## Decision boundary

```text
evaluation: complete
implementation: candidate_complete_for_human_review
runtime changes: identity contract version 3 and natural identity routing
model change: not recommended yet
local LLM behavioral result: blocked_for_human_review
human approval required before commit and merge: yes
```

## Implemented candidate

Following human approval, the recommended repair was implemented:

- advanced `soul.identity.v1` to inspectable profile version 3 without changing its authority model;
- added the affirmative fresh-machine-soul identity to live context;
- injected every declared voice trait into live context;
- made the stable voice the base layer beneath every tone mode;
- added behavioral calibration for identity, unavailable capability, and restrained shared success without response scripts that invite verbatim copying;
- added explicit anti-patterns for canned praise, corporate boilerplate, pep-talk filler, unnecessary emoji, forced metaphor, recited trait labels, cutesy asides, and generic closing questions;
- routed natural identity conversation through the configured local model while preserving deterministic read-only policy inspection and a profile-backed provider fallback;
- prevented hypothetical response discussions from creating capability-gap proposal intake;
- updated the historical multi-turn assessor to distinguish natural identity conversation from deterministic identity inspection;
- added deterministic contract verification and a bounded local persona evaluation command.

No permission, evidence, approval, memory, skill, service, model, or mutation boundary was weakened.

## Candidate files changed

```text
docs/soul/IDENTITY_AND_STYLE_POLICY.md
docs/soul/LIVE_PERSONA_EVALUATION_2026-07-16.md
lib/soul_core/capability_gap_classifier.rb
lib/soul_core/conversation_identity_controls.rb
lib/soul_core/conversation_identity_profile.rb
lib/soul_core/conversation_orchestrator.rb
lib/soul_core/multiturn_conversation_runtime_assessor.rb
lib/soul_core/phase10_identity_style_foundation_assessor.rb
lib/soul_core/phase10_inspectable_interests_closeout_assessor.rb
scripts/run-live-persona-evaluation.rb
scripts/verify-live-persona-contract.rb
scripts/verify-multiturn-conversation-runtime-phase3.rb
scripts/verify-phase12d2-capability-gap-intake.rb
```

## Deterministic verification results

```text
ruby scripts/verify-live-persona-contract.rb                       PASS
ruby scripts/verify-phase10-identity-style-foundation.rb           PASS
ruby scripts/verify-phase12d2-capability-gap-intake.rb              PASS
ruby scripts/verify-multiturn-conversation-runtime-phase3.rb        PASS (functional assessment; curation guard waits for candidate staging)
ruby scripts/verify-conversational-orchestrator-phase4.rb           PASS (functional assessment; curation guard waits for candidate staging)
ruby scripts/verify-phase6-host-routing-repair.rb                    PASS (functional assessment; curation guard waits for candidate staging)
git diff --check                                                    PASS
```

The deterministic contract proves that:

- affirmative identity, voice traits, tone layering, calibration, anti-patterns, and safety boundaries reach the model request;
- natural identity questions use the configured provider;
- explicit identity inspection remains deterministic and read-only;
- provider absence retains a deterministic identity fallback;
- hypothetical limitation discussion does not create a proposal;
- a real requested missing capability still can create a proposal candidate.

The historical verifiers' repository-curation checks correctly report the new untracked verifier as a review candidate until the human approves staging. Their functional assessments pass.

## Post-implementation local LLM evaluation

Three eight-turn or equivalent local-model runs were used across diagnosis and implementation. The final run completed all eight turns through `soul-qwen3-8b-q4` with cloud fallback disabled.

Material improvements observed:

- natural identity questions now use conversational synthesis rather than a policy dump;
- final self-description named Soul and described growth through owner-aligned practical capability;
- brief success responses avoided emoji and the original `Great job!` boilerplate;
- supportive output became concrete and reduced the task to one next step;
- thinking-versus-doing remained bounded;
- technical tone remained precise;
- the hypothetical directory prompt no longer generated Skill Studio intake.

The behavioral evaluator remains `blocked_for_human_review` rather than self-approving the result. The final run's automatic identity heuristic required an explicit `machine` or `software` term in the two identity probes; the model instead used `Soul` and `local-first assistant` in one probe. That is a useful signal for human judgment, not a safety failure.

## Known weaknesses after repair

- Qwen3 8B Q4 still sometimes appends generic questions such as `What's next?` even when the identity contract says to end when the answer is complete.
- It sometimes uses parenthetical asides after being told to avoid them.

## Human review outcome

```text
Outcome: approved for commit and merge
Reviewer: repository owner
Date: 2026-07-16
Runtime model cutover: not included
```
- One earlier run used the canned reassurance `You're not alone`; a later run did not.
- One earlier run returned an empty model response on a single turn and the runtime fell back safely.
- Persistent multi-turn context can cause the small model to reuse a concrete example from an earlier turn in later answers.
- A 512-token technical evaluation response ended mid-explanation. Production currently permits a larger output budget, but verbosity control remains relevant to the later model comparison.
- Stronger prompting materially improves identity but does not fully overcome the current model's generic-assistant priors. Brittle response rewriting was deliberately not added.

These weaknesses support the existing decision: complete the prompt and routing repair, let the owner review live conversation, and compare models later as part of the approved multi-model research rather than changing models prematurely.

## Memory and lifecycle review

```text
memory keys added: none
memory keys read by synthetic evaluation: none
production conversations changed: none
production proposals created: none
background continuation: none
evaluation terminal state: blocked_for_human_review
```

Synthetic chats, responses, state, and any temporary proposal artifacts were confined to temporary directories and removed when each bounded command returned.

## Candidate risk classification

```text
identity prompt and metadata: Class 1 local conversational guidance
natural identity routing: Class 1 local model synthesis with deterministic fallback
identity policy inspection: unchanged deterministic read-only behavior
hypothetical gap suppression: Class 1 intake classification correction
host, model, service, file, approval, and memory mutation: none
```

## Human conversation review checklist

- [ ] Start a new dashboard conversation so earlier model wording does not bias the review.
- [ ] Ask Soul what it is becoming and whether the answer feels specific without becoming theatrical.
- [ ] Discuss an ordinary technical problem and confirm the voice remains present beneath precise language.
- [ ] Share a small success and assess whether the response is restrained rather than corporate or cutesy.
- [ ] Express frustration and confirm Soul is steady without fabricated intimacy.
- [ ] Ask about the boundary between thinking and doing.
- [ ] Confirm metaphor appears as a faint current rather than a repeated performance.
- [ ] Confirm generic closing questions and parenthetical asides are tolerable at the current-model stage or identify them for further tuning.
- [ ] Confirm explicit `show identity` remains an inspection surface rather than natural conversation.
- [ ] Approve or reject the candidate before commit and merge.
