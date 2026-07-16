# Conversational Soul Phase 13 Closeout Review

## Candidate status

```text
candidate_complete
blocked_for_human_review
```

Implementation and automated evidence are complete. The milestone remains blocked from final completion until the owner reviews and approves this packet.

## Implementation summary

- Phase 13A adds a ten-scenario integrated assessor over the shared application, conversation, evidence, artifact, memory, style, and skill lifecycle boundaries.
- Phase 13A drives twenty user exchanges and twenty assistant responses through one isolated persistent chat.
- Phase 13B adds a bounded local-only twenty-turn behavioral evaluator that retains hashes and observations rather than transcript content.
- Phase 13B verifies the three dashboard tabs, authentication, Review Center, initial/manual status behavior, and absence of polling primitives.
- Phase 13C aligns the public project state and adds one aggregate Phase 1–13 regression command.
- `bin/soul` now returns its application's bounded exit status to the shell, allowing failed assessments to produce a nonzero process result.
- Closeout repaired the orchestration contract's missing `capability_catalog` and `capability_info` kinds and updated two legacy source-verifier expectations to the already-delivered evidence-router and completed-memory architecture.

## Files changed

Phase 13 changes include the three briefs, Phase 13A integrated assessor and CLI registration, Phase 13A/B/C verifiers, the Phase 13B local evaluator, three review artifacts, updates to `README.md`, `CHANGELOG.md`, `docs/CURRENT_STATE.md`, `docs/MILESTONES.md`, `docs/ROADMAP.md`, `docs/CONVERSATIONAL_SOUL_ROADMAP.md`, and `docs/CONVERSATIONAL_SOUL_ACCEPTANCE.md`, plus narrow compatibility repairs in the orchestration contract and legacy Phase 6/9 verifiers.

## Commands run

```text
ruby bin/soul assess conversational-soul-acceptance --json
ruby scripts/verify-phase13a-integrated-acceptance.rb
ruby scripts/run-phase13b-local-model-acceptance.rb
ruby scripts/verify-phase13b-local-model-dashboard-acceptance.rb
ruby scripts/verify-phase13c-conversational-soul-closeout.rb
ruby bin/soul assess repository-curation --json
ruby -c <changed Ruby files>
node --check assets/dashboard/dashboard.js
git diff --check
git diff --cached --check
```

## Deterministic test results

Phase 13A passes all ten integrated acceptance scenarios. Its focused verifier passes application API, orchestrator, and Phase 12D.5 regressions. Phase 13B deterministic dashboard and evaluator-boundary checks pass. Phase 13C runs 33 milestone verifiers spanning Conversational Soul Phases 1–13, authentication, protected deployment, conversation clearing/forgetting, Skill Studio, Self Improvement, Review Center, and repository curation.

## Local LLM eval results

Provider: configured local OpenAI-compatible runtime

Model: `soul-qwen3-8b-q4`

Data class: synthetic public evaluation prompts

Cloud fallback: no

Transcript retained: no

The first artificially constrained run completed 20/20 turns but blocked because a 256-token cap produced safe empty-response fallbacks and one prompt named an executable inspection route. After restoring Soul's normal 1,024-token output cap and correcting the probe language, the candidate run completed 20/20 turns through the model path, passed 6/6 continuity probes, produced 20 unique response hashes, and retained no transcript. Total time was 265.5 seconds, with approximately 4.7–21.3 seconds per turn.

Local LLM evidence validates conversational behavior only. It does not authorize safety, mutation, merge, release, or milestone completion.

## Memory keys

Reads: temporary synthetic project memory only in Phase 13A.

Writes/updates: one temporary candidate and approved project-memory record.

Forget behavior: the complete temporary root is removed when the foreground assessor returns.

Live memory: no live user memory is read, written, promoted, or forgotten.

## Lifecycle states touched

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

## Risk classification

- Phase 13A: Class 1 repository assessment plus Class 2 disposable isolated fixture writes.
- Phase 13B: Class 1 local-only behavioral evaluation using synthetic prompts.
- Phase 13C: Class 1 documentation and verification changes.
- Final milestone approval, merge, release, and tagging remain human-authority decisions.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Skill-private memory store added: no
Cloud fallback added: no
Transcript committed: no
Release or tag created: no
```

The previously approved local dashboard services are regression-tested but not changed by Phase 13.

## Known weaknesses

- Sustained local-model latency is significant on the current runtime: the successful twenty-turn run took approximately 4.4 minutes.
- Behavioral heuristics cannot replace the owner's judgment of usefulness, aesthetics, or conversational feel.
- Production skill promotion remains intentionally limited to one self-contained Ruby entrypoint.
- Proxmox, backup/recovery, Internet exposure, multi-user access, voice, and richer document/provider capabilities remain later milestones.
- The repository remains experimental and has no selected open-source license.

## Human review checklist

- [ ] Phase 13A's ten scenarios fairly represent the acceptance contract.
- [ ] The twenty-turn local-model result is conversationally acceptable.
- [ ] Sustained latency is acceptable for this milestone or explicitly deferred.
- [ ] Dashboard Chat, Skill Studio, Self Improvement, and Review Center remain visually acceptable.
- [ ] Authentication and seven-day persistence remain acceptable.
- [ ] Both Skill Studio human gates and exact promotion confirmation remain intact.
- [ ] No private transcript, credential, endpoint, or memory entered the repository.
- [ ] Documentation honestly identifies deferred work and known weaknesses.
- [ ] Conversational Soul is approved as complete at the Phase 13 stopping point.
- [ ] A release tag is either separately approved or explicitly deferred.

## Human review outcome

```text
Outcome: pending
Reviewer: owner
Date:
Decision summary:
Required changes:
```
