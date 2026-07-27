# Skill Registry Snapshot

Generated: 2026-07-27T15:54:08-04:00

Source registry:

```text
Soul/skills/registry.yaml
```

This document is a generated documentation snapshot of the active skill registry. It is intended to reduce documentation drift without changing skill behavior.

## Summary

```text
skill_count: 31
registry_path: Soul/skills/registry.yaml
```

## Skills

### `chats.clear`

```text
name: chats.clear
category: uncategorized
status: unknown
```

Preview and archive active conversations by exact title or all conversations so they leave the active list without deleting transcripts.

### `chats.forget`

```text
name: chats.forget
category: uncategorized
status: unknown
```

Permanently delete one exact local conversation and logically forget shared memories derived from it.

### `cloud.providers.list`

```text
name: cloud.providers.list
category: uncategorized
status: unknown
```

List configured cloud LLM providers without making network calls.

### `cloud.providers.test`

```text
name: cloud.providers.test
category: uncategorized
status: unknown
```

Run bounded smoke tests for configured cloud LLM providers.

### `cores.activate`

```text
name: cores.activate
category: runtime_control
status: available
```

Preview and activate one configured Core without rebooting while preserving active-work, lease, digest, and exact click-approval checks.

### `creative.companion_production`

```text
name: creative.companion_production
category: creative_studios
status: available
```

Coordinate supported reviewed music, still, and native-motion work through exact generation, lineage binding, static presentation when needed, full-duration rendering, kept-song export, and local upload-package export; image-guided motion, destructive visual actions, and external publication retain their dedicated boundaries.

### `creative.music_production`

```text
name: creative.music_production
category: creative_studios
status: available
```

Gather a music brief through chat, preserve user-required decisions, generate and review candidates, translate recorded revision feedback, and prepare exact kept-song export or rejected-candidate deletion gates.

### `creative.visual_production`

```text
name: creative.visual_production
category: creative_studios
status: available
```

Gather or draft a visual brief through chat, generate and review a local still, translate a recorded revise review into one guided edit, and continue a kept visual context into exact native text-to-video generation or a review-led native revision.

### `dashboard.capabilities.inspect`

```text
name: dashboard.capabilities.inspect
category: project_coordination
status: available
```

Explain which Dashboard surfaces currently have bounded conversational mappings, their required inputs, Core needs, and retained human gates without invoking them.

### `dashboard.invocations.inspect`

```text
name: dashboard.invocations.inspect
category: project_coordination
status: available
```

Read the curated invocation guide, including required inputs, Core needs, approval behavior, outputs, and retained authority boundaries, without invoking anything.

### `downloads.cleanup_plan`

```text
name: downloads.cleanup_plan
category: uncategorized
status: unknown
```

Read-only human-oriented cleanup plan based on downloads.inspect.

### `downloads.inspect`

```text
name: downloads.inspect
category: uncategorized
status: unknown
```

Read-only Downloads inspection and cleanup-candidate planning.

### `downloads.move_to_trash`

```text
name: downloads.move_to_trash
category: uncategorized
status: unknown
```

Approval-gated move-to-trash execution based on a verified downloads.cleanup_plan.

### `downloads.restore_last_cleanup`

```text
name: downloads.restore_last_cleanup
category: uncategorized
status: unknown
```

Approval-gated restore of the latest successful Downloads cleanup from Trash.

### `knowledge.vault.conversation_reflect`

```text
name: knowledge.vault.conversation_reflect
category: knowledge
status: available
```

Explicitly inspect one bounded local conversation, draft one review-only reusable-knowledge candidate, and offer the existing exact Knowledge Vault write gate only when deterministic policy permits it.

### `knowledge.vault.initialize`

```text
name: knowledge.vault.initialize
category: knowledge
status: available
```

Create the reviewed portable starter structure in one configured external Markdown vault without overwriting conflicting files.

### `knowledge.vault.memory_export`

```text
name: knowledge.vault.memory_export
category: knowledge
status: available
```

Project approved canonical Soul memory into a clearly marked generated Markdown index without changing canonical memory.

### `knowledge.vault.memory_import`

```text
name: knowledge.vault.memory_import
category: knowledge
status: available
```

Import one explicitly selected bounded Markdown note as a candidate in Soul's existing shared memory ledger.

### `knowledge.vault.reflect`

```text
name: knowledge.vault.reflect
category: knowledge
status: available
```

Classify one explicit durable-knowledge candidate, report its correct canonical destination, and prepare an exact reviewed Markdown note or update only when it belongs in the Knowledge Vault.

### `knowledge.vault.search`

```text
name: knowledge.vault.search
category: knowledge
status: available
```

Search one configured external Markdown vault through a bounded foreground read that treats note content as untrusted context.

### `local.search`

```text
name: local.search
category: knowledge
status: available
```

Search reviewed repository documentation, Knowledge Vault notes, and canonical Music and Visual project briefs in one bounded source-attributed foreground read.

### `project.timeline.inspect`

```text
name: project.timeline.inspect
category: project_coordination
status: available
```

Read the shared owner-local implementation ledger, including explicit horizons, states, priorities, and review criteria.

### `project.timeline.update`

```text
name: project.timeline.update
category: project_coordination
status: available
```

Create or revise one explicitly named implementation-ledger item through the Dashboard editor or an unmistakable timeline-item Chat command.

### `skill.brief.draft`

```text
name: skill.brief.draft
category: uncategorized
status: unknown
```

Draft a review-only Soul/ skill proposal using a configured cloud provider.

### `skill.brief.review`

```text
name: skill.brief.review
category: uncategorized
status: unknown
```

Review a Soul/ skill proposal and write a review-only artifact.

### `system.status`

```text
name: system.status
category: uncategorized
status: unknown
```

Read-only local system and Soul runtime status check.

### `weather.report`

```text
name: weather.report
category: uncategorized
status: unknown
```

Read-only weather report with temperature, humidity, air quality, and optional 3-day outlook.

### `web.lookup`

```text
name: web.lookup
category: uncategorized
status: unknown
```

Bounded DuckDuckGo Instant Answer lookup for narrow orientation; not a general research backend.

### `web.research`

```text
name: web.research
category: uncategorized
status: unknown
```

Bounded foreground public-web search and HTTPS source retrieval with provenance and SSRF protection.

### `youtube.song_search`

```text
name: youtube.song_search
category: uncategorized
status: unknown
```

Open a YouTube search for a requested song in the default Linux browser after confirmation.

### `youtube.video_resolve`

```text
name: youtube.video_resolve
category: uncategorized
status: unknown
```

Resolve a song/search query to a YouTube video candidate using the official YouTube Data API.

## Boundaries

This snapshot does not activate, disable, or modify any skill.

Refresh it with:

```bash
ruby bin/soul improve documentation-registry-refresh
```
