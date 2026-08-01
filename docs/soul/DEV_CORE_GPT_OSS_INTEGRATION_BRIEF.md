# Dev Core GPT-OSS Integration Brief

## Brief status

```text
approved_by_human_owner: 2026-07-31
implementation_authorized: yes
local_model_runtime_installation_authorized: yes
bounded_dashboard_job_authorized: yes
automatic_production_promotion: no
human_visual_review_required: yes
human_merge_review_required: yes
```

## Purpose

Promote the reviewed `gpt-oss:20b` Ollama/Vulkan candidate into a local-first
development lane for Soul. Dev Core must support bounded delegated drafting,
proposal review, proposal-local Beta implementation, deterministic machine
testing, and appropriate read-only synthesis for Self Assessment and Self
Augmentation without weakening either human gate.

Mistral remains configured as an explicit fallback. It is not the preferred
provider when the reviewed local Dev runtime is available.

## Core taxonomy

Stable internal IDs remain compatible while user-facing names change:

| Internal ID | User-facing name | Runtime intent |
| --- | --- | --- |
| `daily` | Soul Core | Gemma chat on AMD; NVIDIA available on demand |
| `amd-free` | Soul-Lite Core | Qwen chat on NVIDIA; AMD released |
| `music` | Creative Core | Qwen chat on NVIDIA; AMD reserved for creative work |
| `free` | Free Core | No chat or development model loaded |
| `dev` | Dev Core | Qwen chat on NVIDIA; GPT-OSS resident on AMD |

Free Core locks the authenticated dashboard behind a Core-selection surface.
Only authentication, Core status, and Core selection remain interactive. This
is a visible no-LLM state, not a failure or an implicit fallback.

## Runtime topology

- Keep the existing Gemma and Qwen chat services and model aliases intact.
- Add one reviewed, loopback-only, unenabled `soul-model-dev.service` on a
  distinct port.
- Use the existing local Ollama model store and exact `gpt-oss:20b` digest.
- Allow only one Dev request at a time and one AMD generation-class lease.
- Keep GPT-OSS resident while Dev Core is selected.
- For a scoped Dashboard invocation outside Dev Core, acquire one temporary
  lease, restore the captured Core intent, and unload the Dev runtime at the
  terminal state.
- Never preempt an active music, visual, chat, or Dev lease.

## Dynamic transition matrix

### Selected Dev Core

Soul switches chat to Qwen when necessary, starts and verifies the local Dev
runtime, selects Dev Core, and keeps GPT-OSS resident across bounded requests.
Leaving Dev Core stops the Dev runtime only after its work count reaches zero.

### Borrowed from Soul Core

Soul verifies idle Gemma, switches chat to Qwen, starts GPT-OSS, performs one
bounded Dev transaction, stops GPT-OSS, and restores Gemma plus the prior Soul
Core intent. Restoration failure is a visible terminal failure with a receipt.

### Borrowed from Soul-Lite Core

Soul leaves Qwen in place, starts GPT-OSS, performs one bounded transaction,
stops GPT-OSS, and returns to Soul-Lite Core.

### Creative Core

Soul does not preempt creative work. A scoped Dev request returns
`awaiting_input` until the Operator leaves Creative Core and no AMD generation
lease remains. An explicit transition to Dev Core is separately previewed.

### Free Core

Free Core exposes no Skill Studio or conversational invocation surface. The
Operator must explicitly select another Core before work can begin.

## Skill Studio lifecycle

```text
Gemma or Qwen capability-gap intake / proposal draft
-> Human Gate 1 approves the exact proposal revision
-> Operator selects Dev Core or authorizes one scoped Dev lease
-> GPT-OSS drafts one proposal-local Beta package
-> deterministic schema, syntax, containment, and sandbox tests
-> machine result becomes an isolated Beta candidate
-> human trials and reviews the exact Beta
-> Human Gate 2 approves the exact tested digest
-> separate exact production promotion
```

GPT-OSS output is candidate material, never authority. The implementation
worker may write only inside the exact proposal-local `beta/` workspace. It
must not edit the production registry, tracked repository files outside that
workspace, Git state, services, credentials, shared memory, or the Knowledge
Vault.

Generated Ruby executes only in the existing bounded networkless sandbox. A
failed generated test may produce review evidence; automatic repair retries
are excluded from this slice. No passing result authorizes Beta execution or
production promotion.

## Provider selection

The role order is:

1. reviewed local GPT-OSS Dev runtime;
2. explicit configured Mistral fallback;
3. fail visibly with `awaiting_input` or `blocked_for_human_review`.

Fallback is never silent. Receipts record provider, model, local/cloud
classification, starting Core, restoration result, duration, and artifact
digests without storing secrets.

## Self Assessment and Self Augmentation

GPT-OSS may:

- summarize already-collected, bounded Self Assessment evidence;
- identify evidence-linked observations and explicit unknowns in the dedicated
  Self Assessment A1 action;
- critique a Self Augmentation proposal or experiment dossier;
- draft a bounded implementation handoff after the existing human gate.

GPT-OSS may not classify its own safety, approve host mutation, create an
augmentation worktree without Gate A1, integrate an experiment, commit, push,
merge, install packages, or mutate the host.

The accepted Self Assessment A1 action is narrower than this general model
capability: it does not draft recommendations or plans. It emits only a summary,
evidence-cited observations, unknowns, and non-authorizing navigation hints.

## Knowledge Vault

The Vault remains supplementary. Dev jobs do not automatically ingest or
write it. The Operator may explicitly select bounded Vault search results as
untrusted references in a later extension. Canonical proposal, Beta, test,
assessment, and augmentation state remains in its existing stores.

## Dashboard job behavior

One existing-dashboard-owned bounded development job may continue while the
Operator navigates to another Dashboard tab. It has a fixed maximum duration,
persisted progress receipt, cancellation boundary, and terminal state. It does
not add another listener, daemon, scheduler, watcher, or resident polling loop.
If the Dashboard process exits, recovery marks the job failed; it does not
silently resume.

## Terminal states

Every Dev operation ends as one of:

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

## Required deterministic verification

- Core labels and stable IDs project correctly.
- Free Core unloads all chat/Dev models and locks non-Core Dashboard controls.
- Free Core can always select a recoverable configured Core.
- Dev activation blocks active work, starts Qwen chat plus GPT-OSS, and records
  exact runtime identity.
- Leaving Dev Core blocks while a Dev lease is active and otherwise unloads
  GPT-OSS cleanly.
- Borrowed Soul Core work restores Gemma even after model or test failure.
- Borrowed Soul-Lite work never restarts Gemma.
- Creative Core never suffers automatic Dev preemption.
- Local-first provider selection preserves explicit Mistral fallback.
- Beta generation cannot escape its proposal-local directory.
- Generated code receives syntax and networkless bounded test validation.
- Machine success remains blocked for human Beta review.
- Gate 2 and production promotion regressions remain unchanged.
- No Vault read or write occurs without an explicit future input contract.

## Human review checklist

- [ ] Core names, Free Core lock, and Dev Core status are visually reviewed.
- [ ] Soul Core to Dev Core and back restores Gemma correctly.
- [ ] Soul-Lite Core scoped Dev work does not thrash the chat runtime.
- [ ] GPT-OSS remains resident across two selected-Dev requests.
- [ ] One approved proposal produces an isolated tested Beta candidate.
- [ ] A deliberately invalid candidate fails safely with useful evidence.
- [ ] Mistral remains available but is not used when local GPT-OSS is ready.
- [ ] Self Assessment and Self Augmentation assistance remains review-only.
- [ ] No production skill is promoted without both human gates.
