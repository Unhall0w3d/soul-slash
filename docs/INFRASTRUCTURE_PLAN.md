
# Soul Interaction Infrastructure Plan

Soul should start small and local, then grow into LAN-hosted infrastructure when the assistant runtime is stable.

## Phase 1: local CLI only

Required infrastructure:

```text
Ruby runtime
SQLite database
local filesystem storage
repo-local configuration during development
```

No containers are required for the first chat interface.

Recommended local data path during development:

```text
Soul/runtime/
```

Long-term user data path:

```text
~/.local/share/soul/
```

## Phase 2: local persistent chat store

Use SQLite.

Tables should eventually cover:

```text
chats
messages
projects
pinned_chats
chat_tags
artifacts
skill_invocations
assistant_decisions
summaries
settings
```

Use SQLite FTS5 for chat, message, and project memory search.

Do not introduce PostgreSQL, Redis, or a vector database until there is a concrete need.

## Phase 3: local HTTP API

Once terminal chat is functional, add a local API.

Example routes:

```text
GET  /api/chats
POST /api/chats
GET  /api/chats/:id
GET  /api/chats/:id/messages
POST /api/chats/:id/messages
GET  /api/skills
POST /api/skills/:id/plan
POST /api/skills/:id/run
GET  /api/projects
```

This API should call the same assistant runtime used by the CLI.

## Phase 4: LAN deployment

For LAN access, a single VM on Proxmox is preferred at first.

Suggested initial shape:

```text
VM: soul-lan
services:
  soul-api
  sqlite volume
  reverse proxy
  optional Open WebUI test client
  optional local model service
```

A single VM is easier to manage initially than many containers split across services.

## NUC/Proxmox posture

The available NUC10FNH systems are suitable for:

```text
Soul API hosting
SQLite-backed LAN service
lightweight web UI
Open WebUI/LibreChat/LobeChat experiments
CPU-only local model testing
backups and artifact storage
```

They are not ideal for heavy local inference unless expectations are modest.

## Later infrastructure

Only when needed:

```text
PostgreSQL
Redis or another job queue
Qdrant or pgvector
object/artifact storage
multi-user auth
backup/restore orchestration
remote sync
```

## Deployment principle

Do not build the airport before the wheelbarrow.

The first target is:

```text
usable local terminal chat
persistent session history
skill-aware responses
safe routing
```

Then make it LAN-accessible.
