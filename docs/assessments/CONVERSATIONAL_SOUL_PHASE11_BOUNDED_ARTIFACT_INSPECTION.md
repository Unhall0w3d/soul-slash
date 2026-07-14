# Conversational Soul Phase 11B Bounded Artifact Inspection

## Outcome

Phase 11B adds integrity-checked, read-only inspection of active text artifacts attached to the current conversation. Inspection is bounded, privacy-aware, redacted, explicitly untrusted, and unable to mutate artifact files or registry metadata.

## Candidate status

```text
candidate_complete
```

Candidate-complete means ready for human review, not approved for merge, release, or unattended use.

## Implementation summary

- resolves attached artifacts by explicit ID, title, kind, or a single unambiguous reference;
- opens files with no-follow semantics and hashes the exact bytes used for inspection;
- enforces size, line, excerpt, context, comparison, encoding, binary, path, and format limits;
- redacts assignment, quoted JSON/YAML, bearer, cloud-key, private-key, and token-like secrets;
- blocks non-public artifact content from cloud providers before provider invocation;
- filters incompatible artifact metadata from ordinary provider prompts;
- surfaces ambiguity, inspection failure, and privacy mismatch as explicit terminal lifecycle states;
- supports deterministic inspect, summarize, excerpt, and comparison controls;
- repairs the existing `ConversationRuntime`/`ConversationContextBuilder` `evidence_store:` constructor mismatch required for direct runtime testing.

## Files changed

```text
CHANGELOG.md
docs/ARCHITECTURE.md
docs/CONVERSATIONAL_SOUL_ROADMAP.md
docs/CONVERSATIONAL_SOUL_ACCEPTANCE.md
docs/INTERACTION_ARCHITECTURE.md
docs/MILESTONES.md
docs/assessments/CONVERSATIONAL_SOUL_PHASE11_BOUNDED_ARTIFACT_INSPECTION.md
docs/soul/ARTIFACT_METADATA_AND_ATTACHMENT.md
docs/soul/BOUNDED_ARTIFACT_INSPECTION.md
lib/soul_core/app.rb
lib/soul_core/conversation_artifact_contract.rb
lib/soul_core/conversation_artifact_controls.rb
lib/soul_core/conversation_artifact_inspector.rb
lib/soul_core/conversation_artifact_reference_resolver.rb
lib/soul_core/conversation_context_builder.rb
lib/soul_core/conversation_orchestrator.rb
lib/soul_core/conversation_provider_registry.rb
lib/soul_core/conversation_runtime.rb
lib/soul_core/phase11_bounded_artifact_inspection_assessor.rb
scripts/verify-phase11-bounded-artifact-inspection.rb
```

## Commands run

```text
ruby bin/soul assess phase11-bounded-artifact-inspection --json
ruby scripts/verify-phase11-bounded-artifact-inspection.rb
ruby scripts/verify-phase11-artifact-metadata-attachment.rb
ruby scripts/verify-conversation-provider-foundation-phase2.rb
ruby scripts/verify-multiturn-conversation-runtime-phase3.rb
ruby scripts/verify-conversational-orchestrator-phase4.rb
ruby -c <changed Ruby files>
git diff --check
```

## Deterministic test results

```text
Phase 11B assessment: passed
Phase 11B verifier: passed
Phase 11A regression: passed
Phase 10 closeout regression: passed through Phase 11A verifier
Whitespace checks: passed
```

Coverage includes exact-byte integrity, before-and-after artifact and ledger hashes, assignment and quoted-JSON redaction, provider privacy routing, zero provider calls on privacy block, untrusted-content labeling, binary and UTF-8 rejection, size and format limits, symlink substitution, integrity drift, ambiguity, anti-hijacking, and deterministic controls.

Historical Phase 2, 3, and 4 verifier scripts were also audited. Their behavioral assessors pass, but the scripts exit nonzero because they assert obsolete milestone/changelog snapshots for their former current phase. The Phase 3 and 4 scripts additionally depend on source-string markers and old assessment fields that were replaced by later architecture. These failures predate Phase 11B behavior and are recorded as verifier-maintenance debt rather than treated as passing regressions.

## Local LLM eval results

```text
Provider: local.openai_compatible
Model: soul-qwen3-8b-q4
Endpoint: local llama.cpp OpenAI-compatible endpoint

Explicit attached-report summary: pass
Secret redaction in model context and response: pass
Hostile artifact instruction treated as quoted data: pass
Ordinary report-writing question avoided content inspection: pass
Ambiguous attached-report reference returned awaiting_input: pass
Integrity drift returned failed before provider synthesis: pass
```

The ordinary-language response reached the configured 512-token eval cap and ended with provider finish reason `length`; its routing behavior still passed because no artifact content was inspected or discussed.

Local LLM evaluation is behavioral validation only. It does not approve the privacy matrix, file-read boundary, lifecycle routing, redaction, or mutation protections.

## Memory keys

Reads:

```text
none
```

Writes or updates:

```text
none
```

Phase 11B reuses the shared artifact registry and conversation context. It creates no skill-private memory store.

## Lifecycle states touched

```text
complete
failed
awaiting_input
blocked_for_human_review
```

Inspection is a bounded foreground operation. It never remains running after returning control.

## Risk classification

```text
read_only_sensitive_local_content
```

The feature reads file content but does not mutate files or registry state. Content disclosure is constrained by artifact privacy and provider class before a provider request is constructed.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
launch agent added: no
Windows service added: no
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Skill-private memory store added: no
Artifact file mutation added: no
Artifact registry mutation during inspection: no
```

## Known weaknesses

- Redaction is deterministic defense in depth and cannot recognize arbitrary sensitive prose.
- Reference resolution considers at most one hundred attached records and model context includes at most two artifacts.
- Rich documents, archives, media, executables, and unknown formats remain unsupported.
- Structured summaries are intentionally shallow and do not validate document semantics.
- Privacy reclassification is not part of Phase 11B; an artifact must be re-registered through a reviewed flow.
- The append-only artifact registry still has no compaction strategy.
- Local runtime provider compatibility accepts both the existing `SOUL_MODEL_ALIAS`/`SOUL_OPENAI_BASE_URL` names and the newer conversation-specific names; configuration normalization remains future cleanup work.
- Historical Phase 2 through 4 wrapper verifiers contain stale current-phase and source-text assertions even though their underlying runtime assessors pass.

## Human review checklist

```text
[ ] Matches the approved Phase 11B scope
[ ] No unapproved persistence or background behavior
[ ] Exact-byte and no-follow read boundary is adequate
[ ] Provider privacy matrix is correct
[ ] No provider call occurs on ambiguity, failure, or privacy block
[ ] Redaction coverage and limitations are acceptable
[ ] File and registry mutation tests are meaningful
[ ] Lifecycle states are complete and visible
[ ] Local LLM eval is treated as behavioral evidence only
[ ] Phase 11A and Phase 10 regressions pass
[ ] Known weaknesses are acceptable
[ ] Candidate is approved for merge
```

## Human review outcome

```text
Outcome: pending
Reviewer: human owner
Date:
Decision summary:
Required changes:
```
