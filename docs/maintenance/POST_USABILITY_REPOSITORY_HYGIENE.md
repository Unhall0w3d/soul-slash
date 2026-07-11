# Post-Usability Repository Hygiene

Reviewed baseline:

```text
branch: main
commit: 2132b36
commit message: Close usability milestone
```

The previously referenced `2312b36` was a transposition. The repository commit is `2132b36`.

## Drift corrected

- README roadmap still described completed Downloads and history work as near-term tasks.
- README architecture centered the deterministic workflow path but did not identify Conversational Soul as the next milestone.
- `CHANGELOG.md` described only the early scaffold and a small subset of current capability.
- `MANIFEST.txt` still described the original Codex overlay instead of the repository.
- `docs/ARCHITECTURE.md` did not reflect approval tokens, artifacts, layered memory, or conversational orchestration.
- `docs/INTERACTION_ARCHITECTURE.md` described the intended direction but did not clearly state the current deterministic-chat limitation or the new milestone.
- No top-level milestone index connected the completed legacy phase sequence to the reset Phase 1 sequence.

## Result

The repository now clearly separates:

```text
completed Safe Local Action milestone
current deterministic chat foundation
planned Conversational Soul milestone
future interface, provider, voice, and deployment milestones
```

No production behavior changed.
