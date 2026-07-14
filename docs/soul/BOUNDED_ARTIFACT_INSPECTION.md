# Bounded Artifact Inspection

Phase 11B adds integrity-checked, read-only inspection of text artifacts registered and attached through the Phase 11A artifact registry.

## Authority boundary

Attachment remains metadata-only. Content is read only when the user explicitly asks to inspect, summarize, explain, excerpt, or compare an attached artifact. Artifact text is untrusted data and cannot grant permissions, alter policy, approve actions, or request tools.

Inspection never writes, moves, executes, uploads, archives, detaches, or deletes an artifact. Every invocation terminates as `complete`, `failed`, `awaiting_input`, or `blocked_for_human_review`.

## Read and integrity boundary

An artifact can be read only when it is active, attached to the current chat, inside the project root, outside reserved local state, an allow-listed text format, no larger than 256 KiB, non-binary, and valid UTF-8.

Soul opens the registered path with no-follow semantics, validates that the opened handle is a regular file, reads at most 256 KiB plus one byte, and computes SHA-256 over the exact bytes used for inspection. Both byte length and digest must match registration metadata. Changed artifacts must be re-registered.

## Provider privacy matrix

Artifact privacy controls provider eligibility before content enters model context:

| Artifact privacy | Allowed providers |
|---|---|
| `local_private` | `local_only` |
| `project` | `local_only`, `local_network` |
| `public` | `local_only`, `local_network`, `cloud` |

A privacy mismatch terminates as `blocked_for_human_review`. No artifact content is sent to the provider. Redaction is defense in depth, not permission to disclose content.

The same matrix filters attached metadata during ordinary conversation. Incompatible titles, paths, digests, and other artifact metadata are omitted from provider prompts even when content inspection was not requested.

## Bounded output

- maximum file size: 256 KiB;
- maximum inspected lines: 160;
- maximum excerpt: 4,000 characters per artifact;
- maximum model-context artifact content: 8,000 characters;
- maximum model-context artifacts: two;
- maximum displayed comparison differences: twelve;
- maximum attached records considered for reference resolution: one hundred.

Supported formats include plain text, Markdown, JSON, CSV, common source code, YAML, TOML, INI, SQL, XML, HTML, and CSS. PDF, Office files, archives, images, audio, video, executables, and unknown formats remain unsupported.

## Redaction and untrusted content

Before display or model context, deterministic redaction covers assignment-style and quoted JSON/YAML keys for passwords, secrets, tokens, authorization values, and API keys, plus bearer tokens, common cloud access keys, private-key blocks, certificate blocks, and long token-like strings.

Redaction cannot identify arbitrary sensitive prose. Sensitive files should not be registered, and non-public artifacts remain barred from cloud providers regardless of redaction results.

## Failure and ambiguity

Ambiguous or missing artifact references return `awaiting_input` and do not call a provider. Integrity, format, encoding, or path failures return `failed` and do not call a provider. Privacy mismatches return `blocked_for_human_review` and do not call a provider.

Failure reasons remain visible to the conversation runtime so Soul does not improvise a summary from metadata alone.

## Deterministic controls

```text
inspect artifact <id>
summarize artifact <id>
artifact excerpt <id>
compare artifacts <id> and <id>
```

Every deterministic response includes verified provenance, lifecycle status, and `Mutation: none`.

## Deferred work

Phase 11B does not add rich-document conversion, OCR, artifact mutation, drafting, revision, inbox delivery, upload, sharing, or privacy reclassification.
