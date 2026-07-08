# Workflow Handler Response Phase 4

## Purpose

Phase 4 moves the `youtube.play` response path into the registered handler object.

Phase 3 moved workflow `run` into handler dispatch.

Phase 4 adds:

```text
handler.respond(state:, text:)
handler-owned rendering methods
WorkflowSession handler dispatch
```

## Files

```text
lib/soul_core/workflows/base_handler.rb
lib/soul_core/workflows/youtube_play_handler.rb
lib/soul_core/workflow_handler_registry.rb
lib/soul_core/workflow_session_handler_dispatch.rb
```

## Flow

Run:

```text
ruby bin/soul do "play Folsom Prison Blues on YouTube"
-> intent youtube.play
-> registry execution guard
-> WorkflowHandlerRegistry
-> Workflows::YouTubePlayHandler#run
```

Respond:

```text
ruby bin/soul respond "yes"
-> WorkflowSession
-> WorkflowSessionHandlerDispatchPatch
-> WorkflowHandlerRegistry
-> Workflows::YouTubePlayHandler#respond
```

## Metadata

Handler-run sessions include:

```text
handler_execution.checked
handler_execution.handler
handler_execution.intent
handler_execution.delegated_to_existing_workflow_method = false
registry_execution.registered = true
```

Handler-response sessions include:

```text
handler_response.checked
handler_response.handler
handler_response.intent
handler_response.action
handler_response.handled_at
```

## Boundary

This phase does not remove `youtube_play_workflow.rb` yet.

The old file still provides intent routing compatibility. A later phase can reduce that file to routing only, then eventually move intent extraction into the registry/handler layer.

## Verification

```bash
ruby scripts/verify-workflow-handler-response-phase4.rb
```
