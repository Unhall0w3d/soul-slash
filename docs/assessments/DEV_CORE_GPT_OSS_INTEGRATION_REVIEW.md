# Dev Core GPT-OSS Integration Review

## Status

Candidate-complete for deterministic and human review. The Operator adopted the
brief, installed the exact inactive user unit, and reviewed live Soul-Lite → Dev
→ Soul-Lite behavior. GPT-OSS remained resident for two selected Dev requests;
one later scoped Soul Dev Worker request borrowed the runtime and returned to
Soul-Lite without disturbing Qwen.

## What was implemented

- Five operator-facing Cores with stable internal IDs: Soul, Soul-Lite,
  Creative, Free, and Dev.
- A digest-pinned, loopback-only, inactive and unenabled Ollama/Vulkan Dev
  runtime deployment for `gpt-oss:20b`.
- Selected-Dev residency and bounded scoped borrowing from Soul or Soul-Lite,
  including explicit restoration receipts and Creative/Free blockers.
- A Free Core Dashboard lock that leaves Core selection available while other
  authenticated controls are inert.
- Local-first skill brief draft/review commands with Mistral retained only as
  an explicit `--provider mistral` fallback.
- One exact post-Gate-1 Skill Studio action that asks GPT-OSS for a
  proposal-local read-only Ruby candidate, statically rejects dangerous
  primitives, runs syntax and declared behavior checks in bubblewrap, and
  stops at human Beta review.
- Networkless, read-only bubblewrap isolation retained when the Operator later
  runs a GPT-OSS-generated Beta.

Self Assessment and Self Augmentation may consume the general local Dev client
only in a later dedicated review-only action. Their existing deterministic
collection and human gates were intentionally not replaced or broadened in
this slice.

## Files changed

See the pull-request diff. Primary additions are:

- `lib/soul_core/dev_model_runtime_coordinator.rb`
- `lib/soul_core/dev_core_task_orchestrator.rb`
- `lib/soul_core/local_development_model_client.rb`
- `scripts/soul-model-runtime-dev`
- `docs/soul/DEV_CORE_GPT_OSS_INTEGRATION_BRIEF.md`
- `docs/guides/CORES.md`

Core orchestration, Skill Studio, application-contract, Dashboard, Makefile,
current-state, and operator-guide files are updated around those additions.

## Commands run

```text
ruby -c <changed Ruby files>
node --check assets/dashboard/dashboard.js
ruby scripts/verify-ollama-model-runtime-deployment.rb
ruby scripts/verify-core-orchestration.rb
ruby scripts/verify-dev-core-runtime.rb
ruby scripts/verify-dev-core-skill-build.rb
ruby scripts/verify-phase12d-skill-studio.rb
ruby scripts/verify-conversational-creative-workflow.rb
ruby scripts/verify-visual-studio-a1.rb
ruby scripts/verify-perception-a3.rb
```

## Deterministic test results

The focused runtime, Core, Skill Studio, conversational creative, Visual Studio,
perception, project-timeline, runtime-privacy, and aggregate model-runtime
control checks pass. Repository curation is expected to pass after the exact
candidate files are intentionally staged.

## Local LLM eval results

No live local-model eval was run in this pass. The previously reviewed model
artifact and exact digest are reused. Live residency, scoped restoration, and
one real Beta draft remain human acceptance items.

## Known weaknesses

- Dashboard and Noctalia visual behavior for the Core choices remains subject
  to ordinary ongoing usability refinement.
- The inactive Dev unit is installed only through the separately reviewed
  owner action; repository mutation alone still cannot install it.
- Self Assessment and Self Augmentation have documented review-only Dev roles,
  but no new model-backed button was added; their deterministic evidence and
  established human gates remain unchanged.
- Generated skills are deliberately limited to self-contained read-only Ruby;
  broader risk classes require a separate approved brief and sandbox design.
- There is no automatic model repair retry after a generated test failure.

## Memory keys added or used

None. Dev jobs do not read or write shared memory or the Knowledge Vault.

## Task lifecycle states touched

`complete`, `failed`, `awaiting_input`, `canceled`, and
`blocked_for_human_review`. Dashboard-owned work has a bounded terminal job
record and does not survive process exit as silent work.

## Risk classification

Runtime mutation plus candidate-code generation. Runtime activation remains
exactly gated. Generated code is proposal-local, read-only, statically filtered,
and networklessly tested; all successful output remains candidate material.

## Human review checklist

- [ ] Visually review the five Core choices and Free Core lock.
- [x] Install and inspect the inactive Dev unit using the Makefile preview.
- [ ] Confirm Soul Core → scoped Dev → Soul Core restores Gemma.
- [x] Confirm Soul-Lite scoped Dev work leaves Qwen running and unloads GPT-OSS.
- [x] Confirm selected Dev Core keeps GPT-OSS resident across two requests.
- [ ] Build one approved proposal and inspect the generated Beta and `REVIEW.md`.
- [ ] Run one deliberately invalid candidate and confirm useful terminal failure.
- [ ] Confirm Mistral is used only after explicit fallback selection.
- [ ] Confirm neither human gate nor production promotion was weakened.
