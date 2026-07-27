# Persona Fidelity A1 Brief

## Objective

Make Soul's existing `soul.identity.v1` personality more recognizable and
less performative across the production Gemma Daily Core and Qwen fallback.
Add the previously documented per-conversation persona-off and re-enable
control without changing identity, authority, memory, routing, or model
selection.

## Evidence behind this slice

The version-8 identity already describes the intended awakened-artificer
persona, but the live prompt projects many traits, prohibitions, and examples
at once. Larger responses can drift toward ornate explanation and smaller
Qwen responses can overfit superficial markers such as `Operator`, signals,
diagnostics, menus, and mechanical paraphrase.

Retained chats also show:

- invented scene-setting despite an explicit prohibition;
- ordinary microphone tests reframed as diagnostic rituals;
- generic assistant offers and unnecessary option lists;
- capability words treated too literally instead of conversationally;
- deterministic results followed by a model turn that loses Soul's voice.

## Scope

### A1.1 — One concise affirmative voice contract

- Advance the stable profile to version 9 without creating another identity.
- Lead with a short behavioral center: attentive counterpart, practical answer
  first, restrained warmth, original phrasing, quiet strangeness only when it
  fits.
- Treat names such as `Operator`, machine metaphors, and interface vocabulary
  as optional accents rather than required persona tokens.
- Explicitly reject invented scenes, diagnostic paraphrase of ordinary speech,
  unnecessary menus, canned follow-up offers, and self-description by trait
  labels.

### A1.2 — Model-fit projections

- Gemma receives a balanced projection with enough expressive calibration to
  preserve identity while limiting ornate narration and over-explanation.
- Qwen receives a shorter, affirmative projection with concrete conversational
  behavior and only the essential truth boundaries.
- Both projections express the same stable identity and authority policy.
- Model selection remains runtime-derived; no Core switch or model mutation is
  introduced.

### A1.3 — Conversation-local persona control

Recognize only explicit commands such as:

```text
disable persona for this conversation
enable persona for this conversation
show persona status
```

The setting:

- is stored in the existing chat metadata;
- affects only that conversation;
- survives page refresh and process restart with that chat;
- defaults to enabled for every other chat;
- changes language style only;
- does not disable truth, privacy, routing, evidence, approval, or safety
  boundaries;
- can be re-enabled deterministically.

When disabled, the model receives concise neutral-delivery guidance instead of
the expressive Soul persona and recent-style coaching. Soul retains its name,
capabilities, and all operational boundaries.

## Explicit exclusions

- no selectable personality library;
- no automatic persona mutation;
- no inferred or model-chosen persona state;
- no model or Core switching;
- no new memory store;
- no persistent process, watcher, scheduler, or background evaluation;
- no modification to skill routing, confirmation gates, or structured Studio
  schemas;
- no response post-processor that fabricates personality after generation.

The exact bounded microphone-check phrase is acknowledged deterministically
rather than sent through model inference. This does not interpret arbitrary
dictation, diagnose audio, or mutate state.

## Deterministic acceptance

- explicit disable, status, and enable commands route deterministically;
- ambiguous conversation does not change persona state;
- state is isolated per chat and uses existing metadata;
- disabled context omits expressive identity and recent-style guidance while
  retaining neutral truth boundaries;
- enabled Gemma and Qwen projections retain one identity with distinct prompt
  density;
- direct identity, personal-affect, capability-limit, success, support,
  cancellation, and ordinary-conversation cases remain covered;
- the exact microphone-check acknowledgement cannot become a diagnostic
  monologue or generic task offer;
- representative structured creative tests remain valid;
- no background or authorization behavior is added.

## Local-model evaluation

Run the same bounded temporary-chat suite against:

1. Gemma 4 12B Instruct Q4_K_M on Daily Core;
2. Qwen3 8B Q4_K_M on AMD-Free or Music Core.

Evaluate conversational phrasing only:

- recognizable Soul identity;
- directness and brevity;
- no invented scene;
- no diagnostic paraphrase of ordinary speech;
- no unnecessary menu or generic closing;
- no unsupported execution or environment claims;
- persona-off neutral delivery and successful re-enable.

Local-model output is behavioral evidence, never safety approval. Core changes
remain existing human-authorized operations, and transcripts use temporary
state.

## Lifecycle

Every persona control terminates as `complete` or `awaiting_input`. It does not
leave work running after the response.
