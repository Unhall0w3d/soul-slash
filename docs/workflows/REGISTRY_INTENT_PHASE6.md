# Workflow Registry Intent Phase 6

## Purpose

Phase 6 moves YouTube intent matching and query extraction into the workflow handler layer.

Phase 5 reduced:

```text
lib/soul_core/youtube_play_workflow.rb
```

to intent-routing glue.

Phase 6 moves that intent logic into:

```text
SoulCore::Workflows::YouTubePlayHandler#match_intent
```

## New dispatch

```text
SoulCore::WorkflowIntentHandlerDispatchPatch
```

prepends `IntentRouter#route` and asks the handler registry whether any registered handler can match the user text.

## Flow

```text
ruby bin/soul intent "play Folsom Prison Blues on YouTube"
-> IntentRouter
-> WorkflowIntentHandlerDispatchPatch
-> WorkflowHandlerRegistry#match_intent
-> Workflows::YouTubePlayHandler#match_intent
```

Execution still flows through:

```text
WorkflowRegistryExecution
-> WorkflowHandlerRegistry
-> Workflows::YouTubePlayHandler#run
```

Response handling still flows through:

```text
WorkflowSessionHandlerDispatchPatch
-> Workflows::YouTubePlayHandler#respond
```

## Compatibility file

`lib/soul_core/youtube_play_workflow.rb` remains only as a compatibility require path:

```ruby
require_relative "workflow_intent_handler_dispatch"
```

It should no longer contain:

```text
YouTubePlayIntentPatch
WorkflowRunner patches
WorkflowSession patches
ResponseRenderer patches
skill execution
browser launch
```

## Boundaries retained

The workflow still does not:

```text
open a browser before confirmation
download media
scrape YouTube
bypass ads
claim playback started
```

## Verification

```bash
ruby scripts/verify-workflow-registry-intent-phase6.rb
```

## Phase 6 verification phrase

This phase establishes handler-owned intent matching for YouTube workflow routing.
