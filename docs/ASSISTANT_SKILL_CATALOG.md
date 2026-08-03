# Assistant Skill Catalog

Generated: 2026-08-02T20:02:46-04:00

Source registry:

```text
Soul/skills/registry.yaml
```

This catalog explains registered Soul skills in language suitable for chat, intent routing, and safe skill invocation planning.

It does not activate, disable, or modify any skill.

## Skill count

```text
36
```

## Skills

### Chats Clear

```text
id: chats.clear
category: uncategorized
status: unknown
risk: approval_required
confirmation_required: true
required_core: none
core_transition_authority: not_applicable
```

Preview and archive active conversations by exact title or all conversations so they leave the active list without deleting transcripts.

Example ways the owner might ask for this:

- use chats clear
- run chats.clear
- prepare this first and ask before changing anything

### Chats Forget

```text
id: chats.forget
category: uncategorized
status: unknown
risk: approval_required
confirmation_required: true
required_core: none
core_transition_authority: not_applicable
```

Permanently delete one exact local conversation and logically forget shared memories derived from it.

Example ways the owner might ask for this:

- use chats forget
- run chats.forget
- prepare this first and ask before changing anything

### Cloud Providers List

```text
id: cloud.providers.list
category: uncategorized
status: unknown
risk: read_only
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

List configured cloud LLM providers without making network calls.

Example ways the owner might ask for this:

- list cloud providers
- what cloud providers are configured

### Cloud Providers Test

```text
id: cloud.providers.test
category: uncategorized
status: unknown
risk: network_or_provider_check
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Run bounded smoke tests for configured cloud LLM providers.

Example ways the owner might ask for this:

- test cloud providers
- check provider connectivity

### Cores Activate

```text
id: cores.activate
category: runtime_control
status: available
risk: approval_required
confirmation_required: true
required_core: none
core_transition_authority: not_applicable
```

Preview and activate one configured Core without rebooting while preserving active-work, lease, digest, and exact click-approval checks.

Example ways the owner might ask for this:

- switch to Creative Core
- activate Soul-Lite Core
- prepare this first and ask before changing anything

### Creative Companion Production

```text
id: creative.companion_production
category: creative_studios
status: available
risk: approval_required
confirmation_required: true
required_core: dynamic_by_generation_operation
core_transition_authority: exact_action_click
```

Coordinate supported reviewed music, still, and native-motion work through exact generation, lineage binding, static presentation when needed, full-duration rendering, kept-song export, and local upload-package export; image-guided motion, destructive visual actions, and external publication retain their dedicated boundaries.

Example ways the owner might ask for this:

- make a song and image, then prepare the video
- use this kept image with that kept song
- prepare this first and ask before changing anything

### Creative Music Production

```text
id: creative.music_production
category: creative_studios
status: available
risk: approval_required
confirmation_required: true
required_core: music
core_transition_authority: exact_action_click
```

Gather a music brief through chat, preserve user-required decisions, generate and review candidates, translate recorded revision feedback, and prepare exact kept-song export or rejected-candidate deletion gates.

Example ways the owner might ask for this:

- make a song
- help me compose a local music candidate
- prepare this first and ask before changing anything

### Creative Visual Production

```text
id: creative.visual_production
category: creative_studios
status: available
risk: approval_required
confirmation_required: true
required_core: amd-free
core_transition_authority: exact_action_click
```

Gather or draft a visual brief through chat, generate and review a local still, translate a recorded revise review into one guided edit, and continue a kept visual context into exact native text-to-video generation or a review-led native revision.

Example ways the owner might ask for this:

- make an image
- create cover artwork with me
- prepare this first and ask before changing anything

### Dashboard Capabilities Inspect

```text
id: dashboard.capabilities.inspect
category: project_coordination
status: available
risk: read_only
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Explain which Dashboard surfaces currently have bounded conversational mappings, their required inputs, Core needs, and retained human gates without invoking them.

Example ways the owner might ask for this:

- use dashboard capabilities inspect
- run dashboard.capabilities.inspect

### Dashboard Invocations Inspect

```text
id: dashboard.invocations.inspect
category: project_coordination
status: available
risk: read_only
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Read the curated invocation guide, including required inputs, Core needs, approval behavior, outputs, and retained authority boundaries, without invoking anything.

Example ways the owner might ask for this:

- use dashboard invocations inspect
- run dashboard.invocations.inspect

### Downloads Cleanup Plan

```text
id: downloads.cleanup_plan
category: uncategorized
status: unknown
risk: read_only
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Read-only human-oriented cleanup plan based on downloads.inspect.

Example ways the owner might ask for this:

- plan a downloads cleanup
- what can be cleaned up safely

### Downloads Inspect

```text
id: downloads.inspect
category: uncategorized
status: unknown
risk: read_only
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Read-only Downloads inspection and cleanup-candidate planning.

Example ways the owner might ask for this:

- inspect my downloads
- show me what is in downloads

### Downloads Move To Trash

```text
id: downloads.move_to_trash
category: uncategorized
status: unknown
risk: approval_required
confirmation_required: true
required_core: none
core_transition_authority: not_applicable
```

Approval-gated move-to-trash execution based on a verified downloads.cleanup_plan.

Example ways the owner might ask for this:

- move approved downloads to trash
- execute the cleanup plan
- prepare this first and ask before changing anything

### Downloads Restore Last Cleanup

```text
id: downloads.restore_last_cleanup
category: uncategorized
status: unknown
risk: approval_required
confirmation_required: true
required_core: none
core_transition_authority: not_applicable
```

Approval-gated restore of the latest successful Downloads cleanup from Trash.

Example ways the owner might ask for this:

- restore the last downloads cleanup
- undo the last cleanup
- prepare this first and ask before changing anything

### Files Inspect

```text
id: files.inspect
category: knowledge
status: available
risk: read_only
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

List one directory, stat one path, or read one bounded text file beneath an explicitly configured approved local root without mutation.

Example ways the owner might ask for this:

- use files inspect
- run files.inspect

### Knowledge Vault Conversation Reflect

```text
id: knowledge.vault.conversation_reflect
category: knowledge
status: available
risk: approval_required
confirmation_required: true
required_core: none
core_transition_authority: not_applicable
```

Explicitly inspect one bounded local conversation, draft one review-only reusable-knowledge candidate, and offer the existing exact Knowledge Vault write gate only when deterministic policy permits it.

Example ways the owner might ask for this:

- use knowledge vault conversation reflect
- run knowledge.vault.conversation_reflect
- prepare this first and ask before changing anything

### Knowledge Vault Initialize

```text
id: knowledge.vault.initialize
category: knowledge
status: available
risk: approval_required
confirmation_required: true
required_core: none
core_transition_authority: not_applicable
```

Create the reviewed portable starter structure in one configured external Markdown vault without overwriting conflicting files.

Example ways the owner might ask for this:

- use knowledge vault initialize
- run knowledge.vault.initialize
- prepare this first and ask before changing anything

### Knowledge Vault Memory Export

```text
id: knowledge.vault.memory_export
category: knowledge
status: available
risk: approval_required
confirmation_required: true
required_core: none
core_transition_authority: not_applicable
```

Project approved canonical Soul memory into a clearly marked generated Markdown index without changing canonical memory.

Example ways the owner might ask for this:

- use knowledge vault memory export
- run knowledge.vault.memory_export
- prepare this first and ask before changing anything

### Knowledge Vault Memory Import

```text
id: knowledge.vault.memory_import
category: knowledge
status: available
risk: approval_required
confirmation_required: true
required_core: none
core_transition_authority: not_applicable
```

Import one explicitly selected bounded Markdown note as a candidate in Soul's existing shared memory ledger.

Example ways the owner might ask for this:

- use knowledge vault memory import
- run knowledge.vault.memory_import
- prepare this first and ask before changing anything

### Knowledge Vault Reflect

```text
id: knowledge.vault.reflect
category: knowledge
status: available
risk: approval_required
confirmation_required: true
required_core: none
core_transition_authority: not_applicable
```

Classify one explicit durable-knowledge candidate, report its correct canonical destination, and prepare an exact reviewed Markdown note or update only when it belongs in the Knowledge Vault.

Example ways the owner might ask for this:

- use knowledge vault reflect
- run knowledge.vault.reflect
- prepare this first and ask before changing anything

### Knowledge Vault Search

```text
id: knowledge.vault.search
category: knowledge
status: available
risk: read_only
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Search one configured external Markdown vault through a bounded foreground read that treats note content as untrusted context.

Example ways the owner might ask for this:

- use knowledge vault search
- run knowledge.vault.search

### Local Search

```text
id: local.search
category: knowledge
status: available
risk: read_only
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Search reviewed repository documentation, Knowledge Vault notes, and canonical Music and Visual project briefs in one bounded source-attributed foreground read.

Example ways the owner might ask for this:

- use local search
- run local.search

### Maintenance Device

```text
id: maintenance.device
category: administration
status: available
risk: approval_required
confirmation_required: true
required_core: none
core_transition_authority: not_applicable
```

Resolve one exact managed device, prepare its fixed package-maintenance plan, accept one short-lived authenticated conversational confirmation, execute through the existing device controller, and report refreshed evidence and receipt.

Example ways the owner might ask for this:

- use maintenance device
- run maintenance.device
- prepare this first and ask before changing anything

### Network Diagnose

```text
id: network.diagnose
category: knowledge
status: available
risk: network_or_provider_check
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Inspect bounded local address and route evidence, resolve one target, send one reachability probe, or test one TCP socket without scanning or mutation.

Example ways the owner might ask for this:

- use network diagnose
- run network.diagnose

### Project Timeline Inspect

```text
id: project.timeline.inspect
category: project_coordination
status: available
risk: read_only
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Read the shared owner-local implementation ledger, including explicit horizons, states, priorities, and review criteria.

Example ways the owner might ask for this:

- show project timeline
- what is next on the project timeline

### Project Timeline Update

```text
id: project.timeline.update
category: project_coordination
status: available
risk: write_local_state
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Create or revise one explicitly named implementation-ledger item through the Dashboard editor or an unmistakable timeline-item Chat command.

Example ways the owner might ask for this:

- mark timeline item <ID> as needs review
- add timeline item: <structured fields>

### Repository Inspect

```text
id: repository.inspect
category: knowledge
status: available
risk: read_only
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Inspect bounded branch, HEAD, status, recent-log, staged-diff, and working-tree-diff evidence from one explicitly configured local Git repository without mutation.

Example ways the owner might ask for this:

- use repository inspect
- run repository.inspect

### Skill Brief Draft

```text
id: skill.brief.draft
category: uncategorized
status: unknown
risk: network_or_provider_check
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Draft a review-only Soul/ skill proposal using a configured cloud provider.

Example ways the owner might ask for this:

- draft a skill brief
- help me design a new skill

### Skill Brief Review

```text
id: skill.brief.review
category: uncategorized
status: unknown
risk: approval_required
confirmation_required: true
required_core: none
core_transition_authority: not_applicable
```

Review a Soul/ skill proposal and write a review-only artifact.

Example ways the owner might ask for this:

- review this skill brief
- check whether this skill proposal is safe
- prepare this first and ask before changing anything

### Skill Studio Inspect

```text
id: skill_studio.inspect
category: project_coordination
status: available
risk: read_only
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Inspect current Skill Studio proposals, Beta evidence, stages, and production registry entries without authorizing or executing a Studio gate.

Example ways the owner might ask for this:

- use skill studio inspect
- run skill_studio.inspect

### System Status

```text
id: system.status
category: uncategorized
status: unknown
risk: read_only
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Read-only local system and Soul runtime status check.

Example ways the owner might ask for this:

- check system status
- how is the system doing

### Weather Report

```text
id: weather.report
category: uncategorized
status: unknown
risk: network_or_provider_check
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Read-only weather report with temperature, humidity, air quality, and optional 3-day outlook.

Example ways the owner might ask for this:

- get the weather
- what is the weather report

### Web Lookup

```text
id: web.lookup
category: uncategorized
status: unknown
risk: network_or_provider_check
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Bounded DuckDuckGo Instant Answer lookup for narrow orientation; not a general research backend.

Example ways the owner might ask for this:

- use web lookup
- run web.lookup

### Web Research

```text
id: web.research
category: uncategorized
status: unknown
risk: network_or_provider_check
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Bounded foreground public-web search and HTTPS source retrieval with provenance and SSRF protection.

Example ways the owner might ask for this:

- use web research
- run web.research

### Youtube Song Search

```text
id: youtube.song_search
category: uncategorized
status: unknown
risk: low
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Open a YouTube search for a requested song in the default Linux browser after confirmation.

Example ways the owner might ask for this:

- search YouTube for a song
- find this song on YouTube

### Youtube Video Resolve

```text
id: youtube.video_resolve
category: uncategorized
status: unknown
risk: low
confirmation_required: false
required_core: none
core_transition_authority: not_applicable
```

Resolve a song/search query to a YouTube video candidate using the official YouTube Data API.

Example ways the owner might ask for this:

- resolve a YouTube video
- find the best YouTube video candidate

## Risk language

```text
read_only: can inspect or report without changing local state
review_only: drafts or reviews artifacts without promotion
network_or_provider_check: may involve configured provider/API testing
approval_required: must ask before changing local state
unknown: needs routing caution until classified
```

## Future use

This catalog should feed chat explanations, intent routing, and skill invocation planning.
