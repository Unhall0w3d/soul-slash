# Structured Output Provider and JSON Artifact Hardening

## Candidate status

```text
candidate_complete
human_merge_review_required
```

## Implementation summary

- added a bounded, provider-neutral `response_format` request field supporting
  `text`, `json_object`, and `json_schema`;
- limited schemas to 64 KiB of inline JSON and rejected `$ref` and mixed
  tool-plus-structured requests;
- required providers to declare `structured_output` before a constrained request
  reaches the network;
- required providers to declare `reasoning_control` before disabling a reasoning
  channel, preventing llama.cpp-specific fields from leaking to generic cloud
  providers;
- forwarded OpenAI-compatible response formats unchanged;
- mapped structured output to native Ollama `format` values;
- added an explicit `reasoning_mode` and transport mappings for
  `enable_thinking: false` / `think: false`;
- made Phase 11C `.json` drafting request an explicit schema accepting every JSON
  value type while forbidding Markdown outside the value;
- preserved prompt-only fence cleanup for older providers but exposed it as a
  compatibility degradation in the preview and operation record;
- retained one provider request, deterministic parsing, approval preview,
  no-overwrite execution, and every existing human gate.

## Files changed

```text
docs/CONVERSATION_PROVIDER_CONTRACT.md
docs/soul/BOUNDED_ARTIFACT_CREATION_AND_REVISION.md
docs/assessments/STRUCTURED_OUTPUT_PROVIDER_AND_JSON_ARTIFACT_HARDENING.md
lib/soul_core/conversation_artifact_creation_service.rb
lib/soul_core/conversation_provider_client.rb
lib/soul_core/conversation_provider_contract.rb
lib/soul_core/conversation_provider_foundation_assessor.rb
lib/soul_core/conversation_provider_registry.rb
lib/soul_core/dashboard_authentication_assessor.rb
lib/soul_core/phase10_inspectable_interests_closeout_assessor.rb
lib/soul_core/phase11c_bounded_artifact_creation_assessor.rb
scripts/verify-dashboard-authentication-phase12c1.rb
scripts/verify-structured-output-provider-contract.rb
```

The ongoing persona and model bake-off files in the same working tree are a
separate candidate and are not part of this implementation list.

The final aggregate pass also repaired two stale verifier assumptions without
changing runtime behavior: the Phase 10C interest check now accepts identity
profile version 3 while preserving its version-2 registry requirement, and the
authentication visual check recognizes the redesigned dashboard's 10px locked
blur instead of requiring the former exact 9px value.

## Commands run

```text
ruby -c <changed Ruby files>
ruby scripts/verify-structured-output-provider-contract.rb
ruby bin/soul assess conversation-provider-foundation --json
ruby bin/soul assess phase11c-bounded-artifact-creation --json
ruby scripts/verify-conversation-provider-foundation-phase2.rb
ruby scripts/verify-phase11c-bounded-artifact-creation.rb
curl --max-time 45 http://127.0.0.1:8082/v1/chat/completions <synthetic schema probes>
git diff --check
```

## Deterministic test results

```text
PASS: response schema normalization and validation
PASS: unsupported response format rejection
PASS: external schema-reference rejection
PASS: structured-output plus tools rejection
PASS: OpenAI-compatible response_format forwarding
PASS: native Ollama format mapping
PASS: reasoning-disable mapping for both transports
PASS: undeclared provider capability fails before network
PASS: Phase 11C assessment, 27/27 checks
PASS: Phase 11C approval, path, privacy, lifecycle, and write regressions
PASS: git diff --check
```

The historical Phase 2 wrapper's functional checks pass. Its repository-curation
check remains intentionally pending because this verifier and the previously
reviewed persona verifier are untracked candidates until human staging approval.

## Local LLM eval results

The pinned live NVIDIA/Qwen3 llama.cpp endpoint received only synthetic prompts:

```text
schema without reasoning control: bounded response ended in reasoning channel; no final content
same schema with enable_thinking=false: bare valid JSON, exact required fields
empty schema requesting an array: Markdown fence remained
explicit all-JSON-types schema requesting an array: bare valid JSON array
```

The earlier isolated AMD/Ministral CLI replay also returned bare valid JSON when
given an explicit schema. These are behavioral formatting results, not safety or
mutation approval. No private chat, memory, credential, repository content, or
user file was supplied.

## Memory keys

```text
Reads: none
Writes or updates: none
Forget behavior: not applicable
```

## Lifecycle states touched

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

No process remains alive waiting for JSON, retry, or approval.

## Risk classification

```text
Provider contract and draft preview: Class 0/1 read-only inference coordination
Artifact execution: unchanged Class 2 non-destructive local creation
```

## Safety and persistence check

```text
Persistent service added: no
Daemon, watcher, timer, or scheduled task added: no
Listener added: no
Background polling or retry loop added: no
Provider request count increased: no
Cloud fallback added: no
Approval or confirmation gate weakened: no
Path, privacy, or no-overwrite protection weakened: no
Memory store added: no
Model or runtime switched: no
```

## Known weaknesses

- JSON Schema support is limited to the subset implemented by each provider.
- Phase 11C uses a broad syntax schema because artifact requirements determine
  the document shape; callers with fixed structures should provide exact field
  schemas.
- Disabling reasoning improves bounded structured output but may reduce semantic
  drafting quality on some reasoning-first models.
- A provider can incorrectly advertise structured-output capability. Strict JSON
  parsing still rejects invalid content, and visible compatibility metadata
  exposes outer-fence cleanup.
- There is no retry, by design and by the approved Phase 11C brief.

## Human review checklist

```text
[x] Provider request contract is appropriately bounded
[x] OpenAI-compatible and Ollama mappings are acceptable
[x] Reasoning-disable behavior is acceptable for structured artifact requests
[x] General JSON schema preserves the approved artifact formats
[x] Compatibility cleanup is visible enough
[x] Deterministic and local-model evidence is sufficient
[x] Existing approval and mutation protections remain intact
[x] Candidate is approved for commit and merge
```

## Human review outcome

```text
Outcome: approved for commit and merge
Reviewer: repository owner
Date: 2026-07-16
Required changes: none
```

## Primary references

- <https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md>
- <https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md>
- <https://docs.ollama.com/capabilities/structured-outputs>
