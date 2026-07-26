# Knowledge Vault

Knowledge Vault is an optional external directory of ordinary Markdown files
shared between Soul and the Operator's preferred editor. Obsidian is a suitable
human surface, but it is not a runtime dependency.

The vault is deliberately supplementary:

- Soul's append-only reviewed memory ledger remains canonical memory.
- Studio projects remain canonical in their private project archives.
- Artifacts, approvals, activities, and conversation history retain their
  existing stores.
- Vault notes are human-readable working knowledge, not automatic authority.

## Configure a vault

Choose a location outside the public Soul repository. An absolute path or a
path beginning with `~/` is accepted:

```dotenv
SOUL_KNOWLEDGE_VAULT_PATH=~/Knowledge/soul-vault
```

Keep this setting in the ignored `.env`. Public installations choose their own
path.

Inspect the configuration and preview the starter structure:

```bash
make knowledge-vault-status
make knowledge-vault-init-preview
```

The preview returns an exact digest. Review it, then initialize:

```bash
make knowledge-vault-init \
  EXPECTED_DIGEST=<digest-from-preview> \
  CONFIRM=INITIALIZE_KNOWLEDGE_VAULT
```

Initialization creates:

```text
Index.md
README.md
Projects/
Research/
Decisions/
Creative Works/
Environment/
Memory Candidates/
Reviews/
Generated/
Templates/
```

Conflicting files are never overwritten.

## Use Obsidian

Install Obsidian only if you want its editing and navigation experience. In
Obsidian, choose **Open folder as vault** and select the configured directory.

Soul does not read Obsidian's cache, workspace state, plugins, or hidden
configuration. It reads bounded regular Markdown files directly, so the vault
remains usable in any editor.

YAML properties and ordinary Markdown links are recommended:

```markdown
---
title: Gemma Core Decision
type: decision
status: accepted
tags:
  - soul
  - models
related:
  - "[[Projects/Soul]]"
---

# Gemma Core Decision
```

Obsidian-specific block references may be useful to a human, but ordinary
Markdown links are more portable.

## Search

Search is a foreground operation with no resident index:

```bash
make knowledge-vault-search KNOWLEDGE_QUERY="Gemma Core"
```

Soul also recognizes the deliberately narrow chat forms:

```text
knowledge vault status
search knowledge vault for Gemma Core
```

Nearby conversation does not trigger a vault search. This keeps “I am editing
the knowledge vault” conversational instead of interpreting it as a skill
request.

One invocation scans at most 500 regular Markdown files, reads at most 256 KiB
per file, and returns at most 20 ranked excerpts. Hidden directories,
`.obsidian`, `.git`, non-Markdown files, and symlinks are excluded. Returned
content remains untrusted context.

## Decide what belongs in the vault

Knowledge Reflection applies a deterministic destination matrix before any
note preview:

| Candidate kind | Destination |
|---|---|
| Reviewed project, decision, research, workflow, lesson, or environment knowledge | Knowledge Vault |
| Operator preference or personal episodic context | Shared-memory candidate flow |
| Music or visual candidate-specific evidence | Canonical Studio archive |
| Transient status, raw conversation, candidate evidence, or an unverified claim | Current conversation/evidence surface only |
| Credential classification or detected secret material | Never store |

This policy does not run automatically after conversations. A human may supply
one structured candidate directly, or explicitly ask Soul to draft one from
the active conversation. Model classification is advisory; deterministic
validation and human approval remain authoritative.

## Reflect on the active conversation

Use one narrow request when a transmission contains a reviewed decision,
verified lesson, reusable workflow, durable project fact, or stable environment
fact:

```text
Reflect on this conversation for reusable knowledge.
```

Soul reads at most 100 bounded messages and sends them only to the configured
local conversation model. It drafts at most one candidate. Deterministic A1
policy then:

1. rejects likely secrets;
2. redirects preferences, Studio evidence, transient state, and raw
   conversation to their canonical surfaces without creating a vault
   candidate;
3. searches the vault for duplicates;
4. renders the complete proposed Markdown and digest when the candidate is
   vault-eligible.

The response includes an exact command only for an eligible vault note:

```text
WRITE_KNOWLEDGE_VAULT_NOTE <candidate_id> <preview_digest>
```

Sending that exact line in the same conversation authorizes only the displayed
candidate and digest. The service recomputes the A1 scope before writing and
blocks another conversation, a changed digest, a changed vault target, or a
completed candidate. Casual conversation never triggers reflection or storage.

Start from the public example:

```bash
cp config/knowledge_reflection.example.json /tmp/soul-knowledge-candidate.json
```

Edit the copy, then preview:

```bash
make knowledge-vault-reflection-preview \
  KNOWLEDGE_REFLECTION_INPUT=/tmp/soul-knowledge-candidate.json
```

The input records:

```json
{
  "title": "Core Runtime Decision",
  "body": "The reviewed decision and its reusable explanation.",
  "knowledge_kind": "decision",
  "evidence_status": "repository_documentation",
  "source_reference": "repo:docs/CURRENT_STATE.md",
  "target_relative_path": null,
  "tags": ["models", "runtime"]
}
```

For a new note, omit or set `target_relative_path` to `null`; Soul derives a
portable path below the matching durable area. For an update, name one existing
regular Markdown file. The preview shows the complete replacement Markdown,
prior and new hashes, write mode, and up to five possible duplicates.

After reviewing the exact content and destination:

```bash
make knowledge-vault-reflection-execute \
  KNOWLEDGE_REFLECTION_INPUT=/tmp/soul-knowledge-candidate.json \
  EXPECTED_DIGEST=<digest-from-preview> \
  CONFIRM=WRITE_KNOWLEDGE_VAULT_NOTE
```

Execution recomputes classification, duplicates, source state, and rendered
content. A changed input, changed target, changed duplicate scope, or wrong
phrase blocks the write. The capability does not commit or push Git.

## Project approved memory

Soul may create a human-readable projection of active approved memory:

```bash
make knowledge-vault-memory-export-preview

make knowledge-vault-memory-export \
  EXPECTED_DIGEST=<digest-from-preview> \
  CONFIRM=EXPORT_APPROVED_MEMORY_TO_VAULT
```

The output is `Generated/Approved Memory.md`. It is marked as generated and may
be refreshed only through another exact preview. Editing that projection does
not change canonical memory.

## Import one note as a memory candidate

An explicitly selected concise note can enter the existing memory review flow:

```bash
make knowledge-vault-memory-import-preview \
  KNOWLEDGE_NOTE="Decisions/Gemma Core.md" \
  KNOWLEDGE_LAYER=project

make knowledge-vault-memory-import \
  KNOWLEDGE_NOTE="Decisions/Gemma Core.md" \
  KNOWLEDGE_LAYER=project \
  EXPECTED_DIGEST=<digest-from-preview> \
  CONFIRM=IMPORT_VAULT_NOTE_AS_MEMORY_CANDIDATE
```

Accepted layers are `project`, `preference`, `episodic`, and `semantic`. The
note body is capped at 4,000 characters. Import creates a candidate with file
path and SHA-256 provenance. It never approves the candidate; use the existing
reviewed memory controls separately.

## Private Git repository

The vault may be its own private Git repository. This provides history,
recovery, and optional synchronization, but a private remote is access
controlled rather than end-to-end encrypted.

Do not commit:

- credentials or API keys;
- raw authentication state;
- secrets from `.env`;
- private keys;
- unrestricted raw conversation exports;
- information that should never leave the machine.

The starter `.gitignore` excludes volatile Obsidian workspace state while
allowing intentional themes or settings to be versioned later.

Soul does not automatically run Git operations. Commits, pushes, pulls, and
conflict resolution remain explicit human actions.

## Runtime boundaries

Knowledge Vault adds no:

- watcher;
- service or daemon;
- scheduled synchronization;
- network listener;
- automatic Git mutation;
- automatic durable-memory extraction or promotion;
- cloud transmission.

Every operation terminates in `complete`, `failed`, `awaiting_input`, or
`blocked_for_human_review`.
