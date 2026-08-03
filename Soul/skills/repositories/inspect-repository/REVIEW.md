# Human review — repository.inspect

Candidate: Fundamental Skill Cohort A1, slice 3

Status: candidate-complete; human review required

## Implemented

- One configuration-owned repository-ID list with portable `project=.` default.
- One foreground inspection returning branch/detached state, HEAD, bounded
  status, ten recent commits, staged diff, and working-tree diff.
- One shared deterministic path across `soul.application.v1`, authenticated
  Chat, and Voice Presence.
- Fixed absolute argv-only Git execution with optional locks and extension
  points disabled, five-second command deadlines, and output ceilings.
- Secret-shaped status and diff paths are excluded. Credential-like or unsafe
  non-UTF-8 diff content is withheld.
- Modern skill metadata, authority reference, registries, invocation guide,
  public documentation, and project-tracker records.

## Files changed

- `lib/soul_core/repository_inspection_service.rb`
- `lib/soul_core/repository_inspection_chat_controls.rb`
- application contract, facade, responder, and orchestrator integration
- `Soul/skills/repositories/inspect-repository/`
- skill, invocation, capability, environment, documentation, and tracker files
- `scripts/verify-fundamental-repository-inspect-a1.rb` and Make target

## Commands and deterministic results

```text
make verify-fundamental-repository-inspect
19 checks passed

quick_validate.py Soul/skills/repositories/inspect-repository
Skill is valid

make verify-invocation-catalog
15 checks passed

make verify-operator-capability-catalog
passed

make verify-fundamental-files-inspect
17 checks passed

make verify-fundamental-network-diagnose
19 checks passed

Chat intent and interaction-boundary verifier
35 checks passed

make test-soul
passed

documentation registry refresh verifier
passed

assistant skill catalog verifier
passed

Phase 12B in-process application API verifier
candidate-ready

Project Timeline A1 verifier
passed

Skill Studio conversation verifier
10 checks passed

live project smoke
complete; Chat complete; mutation none; status unchanged
```

## Local LLM eval

Not used. Exact deterministic routing and command/output behavior are fully
covered without model judgment. No LLM output validates authority or safety.

## Known weaknesses

- Exact Chat grammar is deliberately conservative.
- Large or unusually slow repositories may hit the five-second boundary.
- Untracked file content is never included; only its bounded status path may be
  visible.
- Submodule state, upstream divergence, tags, remotes, and per-file history are
  outside this slice.
- A high-confidence credential pattern withholds the entire affected diff and
  may conservatively hide otherwise harmless example text.
- Returned repository evidence becomes part of the requesting local
  conversation transcript.

## Memory and lifecycle

- Memory keys added or used: none.
- No skill-private memory, cache, index, watcher, service, schedule, retry, or
  background continuation.
- Lifecycle states touched: `complete`, `awaiting_input`, `failed`, and
  `blocked_for_human_review`; application cancellation remains available
  through the shared application contract.
- Mutation: always `none`.

## Risk classification

`read_only`. The repository list is configuration authority. Conversation may
select one ID but cannot add a path or authorize Git or file mutation.

## Human checklist

- [ ] Confirm configured repository IDs are the intended authority boundary.
- [ ] Confirm the fixed Git argv contains no mutating or network operation.
- [ ] Confirm output/time limits and secret withholding are acceptable.
- [ ] Confirm ordinary Git discussion does not invoke inspection.
- [ ] Confirm Chat output labels repository evidence untrusted and
      point-in-time.
- [ ] Confirm no mutation, persistence, memory, retry, or background behavior.
- [ ] Accept, request revision, or reject this candidate independently of tests.
