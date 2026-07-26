# Creative Archive Chat Awareness A1 Review

## Candidate outcome

Chat can resolve exact local Music Studio and Visual Studio projects, ground a
response in their briefs and bounded lineage, and inspect an explicitly
requested existing visual candidate without a download/re-upload round trip.

## Files changed

- `lib/soul_core/conversation_creative_archive_service.rb`
- `lib/soul_core/conversation_tool_catalog.rb`
- `lib/soul_core/conversation_evidence_contract.rb`
- `lib/soul_core/conversation_runtime.rb`
- `scripts/verify-creative-archive-awareness-a1.rb`
- current-state, roadmap, README, workflow guide, and this brief/review pair

## Deterministic results

- exact Visual Studio title resolution: PASS
- brief-only lookup avoids pixel inference: PASS
- existing still inspection without upload: PASS
- exact brief and Operator question reach vision: PASS
- evidence remains non-authorizing: PASS
- exact Music Studio title resolution: PASS
- bounded project catalog: PASS
- natural brief and candidate-comparison routing: PASS
- ordinary conversation avoids invocation: PASS
- archive service exposes no creative mutation calls: PASS
- Picture Understanding A1 regression: PASS
- conversational creative workflow regression: PASS
- weather-routing regression: PASS

The historical Phase 4 aggregate's functional checks pass. Its aggregate exit
remains nonzero because this active worktree intentionally contains untracked
review candidates, which the old repository-curation gate treats as unfinished.

## Live local-model result

On Daily Core, Soul resolved **The Rooms Remember Me — Habitat**, extracted a
temporary three-frame contact sheet from its kept motion candidate, and compared
the visible evidence with the exact stored brief. It identified matching
environment, atmosphere, architectural dominance, creature design, and palette;
it also identified absent violet contour fissures and insufficient concealment.
The derived contact sheet was removed after inference.

The same comparison was then submitted through the authenticated Dashboard chat
surface. Soul disclosed that it inspected three chronological sampled motion
frames, named the matching brief details, reported the two absent details above,
and found no visible contradiction. It did not request another upload, mutate
the Visual Studio project, or cross an approval gate.

## Commands

- `ruby scripts/verify-creative-archive-awareness-a1.rb` - PASS
- `ruby scripts/verify-perception-a1.rb` - PASS
- `ruby scripts/verify-conversational-creative-workflow.rb` - PASS
- `ruby scripts/verify-conversation-weather-routing.rb` - PASS
- Ruby syntax checks - PASS
- `git diff --check` - PASS

## Known weaknesses

- Title resolution intentionally requires the full exact stored title or ID.
- Pixel inspection selects the newest existing candidate; explicit candidate-ID
  selection is not yet exposed conversationally.
- Motion understanding samples three frames and does not analyze audio or every
  video frame.
- Music briefs are readable, but existing audio is not yet listened to or
  transcribed through this archive path.
- A prior arbitrary ephemeral upload cannot be reconstructed after its pixels
  have been discarded.

## Memory, lifecycle, and risk

- Shared memory keys: none.
- Soul Vault writes: none.
- Lifecycle: `complete`, `awaiting_input`, `failed`.
- Risk: local-private read-only project and candidate inspection.
- Mutation: none.
- Human review remains required before merge or promotion.

## Human checklist

- [ ] Ask Soul to list visual projects.
- [ ] Refer to an exact Visual Studio brief by title.
- [x] Ask Soul to compare that project's existing candidate with its brief.
- [x] Confirm the response names the selected still or sampled motion evidence.
- [ ] Confirm a conversational mention of project work does not invoke lookup.
- [ ] Confirm generation, revision, deletion, and binding gates are unchanged.
