# YouTube Workflow Boot Cleanup Phase 7

## Purpose

Phase 7 retires the last YouTube workflow compatibility file.

The compatibility file retired in this phase is:

```text
lib/soul_core/youtube_play_workflow.rb
```

## Before

Application boot loaded:

```ruby
require_relative "youtube_play_workflow"
```

That file became a compatibility require path during phase 6.

## After

Application boot loads handler intent dispatch directly:

```ruby
require_relative "workflow_intent_handler_dispatch"
```

The old file is deleted.

## CLI compatibility repair

`bin/soul` constructs the app with positional arguments:

```ruby
SoulCore::App.new(ARGV)
```

So `SoulCore::App#initialize` must support the positional form.

The phase 7 repair keeps both supported forms:

```ruby
SoulCore::App.new(ARGV)
SoulCore::App.new(argv: ARGV)
```

## Current YouTube workflow architecture

Intent matching:

```text
IntentRouter
-> WorkflowIntentHandlerDispatchPatch
-> WorkflowHandlerRegistry#match_intent
-> Workflows::YouTubePlayHandler#match_intent
```

Workflow execution:

```text
WorkflowRegistryExecution
-> WorkflowHandlerRegistry
-> Workflows::YouTubePlayHandler#run
```

Workflow response handling:

```text
WorkflowSessionHandlerDispatchPatch
-> WorkflowHandlerRegistry
-> Workflows::YouTubePlayHandler#respond
```

## Boundary retained

The YouTube workflow still does not:

```text
open a browser before confirmation
download media
scrape YouTube
bypass ads
claim playback started
```

## Verification

```bash
ruby scripts/verify-youtube-workflow-boot-cleanup-phase7.rb
```
