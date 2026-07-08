# Workflow Handler Objects Phase 3

## Purpose

This phase introduces explicit workflow handler objects.

Phase 1 added a workflow registry inventory.

Phase 2 added a registry execution guard.

Phase 3 adds a handler registry and a first handler object for:

```text
youtube.play
```

## New files

```text
lib/soul_core/workflows/base_handler.rb
lib/soul_core/workflows/youtube_play_handler.rb
lib/soul_core/workflow_handler_registry.rb
```

## Flow

```text
intent
-> WorkflowRegistryExecution
-> WorkflowHandlerRegistry
-> handler object if one exists
-> legacy runner fallback otherwise
```

For this phase:

```text
youtube.play
-> Workflows::YouTubePlayHandler
-> delegates to existing run_youtube_play implementation
```

## Why delegation still exists

This phase intentionally avoids removing the existing YouTube workflow patch.

The handler object wraps the existing implementation first. That lets us verify the handler path before moving response handling and rendering behind a full registered workflow interface.

Refactors that try to do everything at once are how software becomes a cautionary tale with a README.

## Verification metadata

A workflow state staged through a handler records:

```text
handler_execution.checked = true
handler_execution.handler = SoulCore::Workflows::YouTubePlayHandler
handler_execution.intent = youtube.play
registry_execution.registered = true
```

## Commands

Verify:

```bash
ruby scripts/verify-workflow-handler-objects-phase3.rb
```

Manual check:

```bash
ruby bin/soul do "play Folsom Prison Blues on YouTube"
ruby bin/soul workflow status latest
ruby bin/soul respond "cancel"
```

## Next phase

Move response handling and rendering into handler objects.

Target interface:

```text
handler.run(parameters:, original_text:)
handler.respond(state:, text:)
handler.render(state:)
```

After that, `youtube_play_workflow.rb` can be reduced or retired.
