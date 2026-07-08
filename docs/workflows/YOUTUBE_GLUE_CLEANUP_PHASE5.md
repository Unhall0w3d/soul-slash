# YouTube Workflow Glue Cleanup Phase 5

## Purpose

Phase 5 reduces:

```text
lib/soul_core/youtube_play_workflow.rb
```

to **intent routing only**.

The actual workflow behavior now lives in:

```text
lib/soul_core/workflows/youtube_play_handler.rb
```

## Before

`youtube_play_workflow.rb` owned several monkey patches:

```text
IntentRouter
WorkflowRunner
WorkflowSession
ResponseRenderer
```

## After

`youtube_play_workflow.rb` only owns:

```text
YouTubePlayIntentPatch
```

This keeps natural language routing for requests such as:

```bash
ruby bin/soul do "play Folsom Prison Blues on YouTube"
```

Execution and response handling flow through registered handler objects:

```text
IntentRouter
-> WorkflowRegistryExecution
-> WorkflowHandlerRegistry
-> Workflows::YouTubePlayHandler#run
-> Workflows::YouTubePlayHandler#respond
```

## Behavior retained

The workflow still:

```text
extracts a YouTube query
resolves a video candidate
shows title/channel/watch URL
requires confirmation before opening
opens only through youtube.song_search
records handler_execution metadata
records registry_execution metadata
records handler_response metadata
```

## Boundary

The workflow still does not:

```text
download media
scrape YouTube
bypass ads
claim playback started
open the browser before confirmation
```

## Verification

```bash
ruby scripts/verify-youtube-workflow-glue-cleanup-phase5.rb
```
