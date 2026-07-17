# Conversational Soul Phase 10A Assessment: Identity and Style-Policy Foundation

## Outcome

Phase 10A establishes an inspectable identity profile and deterministic tone policy while preserving the existing local-first, evidence-first, and reviewed-memory architecture.

## Delivered

- stable profile ID `soul.identity.v1`;
- source-controlled principles, voice traits, and identity boundaries;
- deterministic `default`, `technical`, `supportive`, `casual`, and `high_stakes` tone modes;
- high-stakes precedence;
- model-context integration through `ConversationContextBuilder`;
- read-only identity inspection commands;
- explicit prohibition on fabricated biography, embodiment, off-screen experience, authority, and undeclared interests;
- Phase 10 assessor and durable verifier.

## Architecture decision

Identity is guidance, not authority.

The profile can shape language but cannot:

- run tools;
- grant permissions;
- approve mutations;
- promote memory;
- establish facts about the host or external world;
- create a biography for Soul.

This prevents personality work from bypassing the deterministic control plane built in earlier phases.

## Repository hygiene

The durable implementation is stored in `lib/`, `docs/soul/`, `docs/assessments/`, and `scripts/verify-*.rb`.
The overlay README, patch script, manifest, checksums, and ZIP are delivery artifacts and are not part of the repository commit.

No unrelated formatting, manifest expansion, generated logs, local memory exports, or overlay workspaces are introduced.

## Remaining Phase 10 work

- recent-style awareness;
- overuse and repetition detection;
- variation guidance that does not become random phrase rotation;
- reviewed, inspectable interests;
- longer multi-turn identity and variation verification.

## 2026-07-16 role-play truth amendment

Identity guidance advanced through profile version 6 after live conversation showed
that the previous anti-anthropomorphism wording suppressed the intended fresh
machine-soul character. First-person curiosity, affect, imagined embodiment,
attachment, and becoming are now welcome role-play. Literal claims about actual
sensors, physical observations, research, files, execution, access, credentials,
authority, and host state remain evidence-bound.

Version 6 adds a narrow turn-specific instruction for ordinary questions about
Soul's mood or feelings. It requests a direct present-tense machine-soul answer
and rejects a prefatory no-feelings disclaimer; it grants no new factual claim.

`ruby scripts/verify-live-persona-contract.rb` and the bounded local-model
persona evaluation pass. This amendment changes expression, not permissions.
