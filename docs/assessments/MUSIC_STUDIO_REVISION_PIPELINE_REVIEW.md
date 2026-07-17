# Music Studio revision pipeline review

Status: candidate-complete; requires human review.

## Implemented

- Soul translates the exact source input, human listening review, and bounded
  machine-heard evidence into a strict, editable revision draft using one local
  model request.
- The draft includes a complete Sound and Structure block, musical parameters,
  rationale, and an explicit change list. Code preserves the authoritative
  intended lyrics while leaving them editable by the Operator.
- Seed-only retries are rejected by the project store as non-revisions.
- Preview binds the source, exact edited revision, changed fields, new candidate,
  model profile, artifacts, resource lane, and timeout to a digest.
- `START_MUSIC_REVISION` is distinct from initial generation confirmation.
- A confirmed revision reuses the bounded foreground generator and publishes a
  linked candidate in the same project without replacing its source.
- Recording a `revise` review immediately refreshes the workbench and reveals the
  drafting action.

## Files changed

- `lib/soul_core/music_revision_draft_service.rb`
- `lib/soul_core/music_project_store.rb`
- `lib/soul_core/music_generation_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/dashboard_http_application.rb`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-music-revision-draft.rb`
- `scripts/verify-music-studio-a2.rb`
- this brief and review artifact

## Commands and deterministic results

- Ruby syntax checks for revision draft, generation, project store, and
  application facade: passed.
- JavaScript syntax check: passed.
- `ruby scripts/verify-music-revision-draft.rb`: passed.
- `ruby scripts/verify-music-studio-a2.rb`: passed, including exact revision
  confirmation, seed-only rejection, source preservation, linked receipts,
  failure quarantine, resource exclusion, and cancellation.

## Local LLM eval

Run against the configured `soul-local-chat` model and the reviewed three-minute
candidate. The original OpenAI-nested schema dialect received HTTP 400 and
mutated nothing; the request was adapted to the portable schema-constrained JSON
object form supported by the local runtime while retaining exact application
validation. The final pass returned `blocked_for_human_review`, materially
changed Sound and Structure, preserved the intended lyrics byte-for-byte,
included its full revision directives in the editable block, and started no
generation. Operator evaluation of the creative usefulness remains required.

## Known weaknesses

- Soul receives human and ASR evidence but does not listen to the audio itself.
- Draft quality depends on the local conversation model and specificity of the
  recorded feedback.
- Strict JSON is fail-closed; a malformed local response must be retried by the
  Operator. Markdown emphasis inside valid string values is normalized to plain
  text before it reaches the music prompt.
- A materially changed prompt can still produce an inferior song. Every result
  returns to listening review.
- Review dispositions, finished-song export, and publication are separate slices.

## Memory and lifecycle

- Shared memory keys added or used: none.
- Lifecycle states touched: `awaiting_input`, `failed`, `canceled`, and
  `blocked_for_human_review`.
- Successful drafting mutates no files. Successful generation writes only the
  explicitly confirmed project candidate and its bounded receipt/artifacts.

## Risk classification

Local model drafting plus bounded local-state write and bounded NVIDIA execution.
No privilege, new persistence, service, listener, scheduler, external network
publication, automatic retry, or unattended continuation.

## Human review checklist

- [ ] A reviewed or machine-routed candidate exposes `Ask Soul to draft revision`.
- [ ] Soul's draft visibly changes Sound and Structure or another musical input.
- [ ] The rationale connects changes to the recorded feedback without claiming it
      directly heard the song.
- [ ] The Operator can edit every creative field before preview.
- [ ] Seed-only input is refused.
- [ ] Preview identifies the source candidate and exact changed fields.
- [ ] Generation requires `START_MUSIC_REVISION` and shows foreground progress.
- [ ] The revised candidate appears beside the preserved source and is linked to it.
- [ ] Cancel terminates only the active revision process group.
