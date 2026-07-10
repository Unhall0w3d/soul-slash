
# Runtime Privacy Hygiene

Soul keeps a hard boundary between source-controlled project files and local owner data.

## Private runtime data

The following paths are local runtime data and should not be committed:

```text
Soul/runtime/
Soul/codex/tasks/
Soul/codex/responses/
Soul/codex/reviews/
```

These may contain:

```text
private chats
local transcripts
assistant memory
project-local state
generated Codex task packages
Codex response drafts
local review artifacts
runtime databases
machine-specific metadata
```

## Restorable from Git

These belong in Git when intentionally created and reviewed:

```text
source code
docs
maintenance docs
verifier scripts
skill registry entries
approved skill implementations
reviewed generated documentation snapshots
```

## Not restorable from Git

These are personal/local data and need a separate backup strategy later:

```text
chat history
memory summaries
personal projects
local preferences
provider configuration
secrets
skill invocation logs
runtime databases
local generated task state
```

This is what makes one Soul instance personally useful instead of just a fresh clone.

## Backup posture

A future infrastructure phase should define backups for the non-Git data.

For now:

```text
Git protects project source.
.gitignore protects private runtime data from accidental commit.
A later backup plan protects owner-specific Soul state.
```

## Proxmox / LAN note

When Soul becomes LAN-accessible, runtime data should live on persistent storage with an explicit backup plan.

The Proxmox NUC hosts should remain standalone unless there is a specific reason to cluster them.

## Safety rule

If a file contains personal conversation, local memory, provider state, credentials-adjacent metadata, or generated Codex task material, assume it is private unless explicitly promoted through review.
