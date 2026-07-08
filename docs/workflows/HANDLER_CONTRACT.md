# Workflow Handler Contract

## Purpose

Workflow handlers are the stable home for workflow-specific behavior.

A workflow handler owns:

```text
intent matching
workflow execution
workflow response handling
workflow-specific rendering
workflow state metadata
verification boundaries
```

The goal is to add new workflows without monkey patching `WorkflowRunner`, `WorkflowSession`, `ResponseRenderer`, or `IntentRouter` directly.

No green lights without gauges.

## Required handler shape

A handler should live under:

```text
lib/soul_core/workflows/<workflow_name>_handler.rb
```

A handler must inherit from:

```ruby
SoulCore::Workflows::BaseHandler
```

A handler must implement:

```ruby
def run(parameters:, original_text:)
end
```

A handler that owns natural-language routing should implement:

```ruby
def match_intent(text, result_class:)
end
```

A handler that supports follow-up responses should implement:

```ruby
def responds_to_status?(status)
end

def respond(state:, text:)
end
```

## Required `run` return shape

```ruby
{
  ok: true,
  workflow_path: "Soul/workflows/sessions/...",
  state: state_hash,
  user_message: "Message shown to the user"
}
```

## Required `respond` return shape

```ruby
{
  ok: true,
  message: "Message shown to the user",
  state: state_hash
}
```

## Required workflow state fields

Workflow session state must include:

```text
workflow
status
generated_at
updated_at
original_text
parameters
skill_runs
next_expected
verification
workflow_path
```

`verification` must contain deterministic evidence about what did or did not happen.

## Recommended metadata

Handler run metadata:

```text
handler_execution.checked
handler_execution.handler
handler_execution.intent
handler_execution.delegated_to_existing_workflow_method
```

Handler response metadata:

```text
handler_response.checked
handler_response.handler
handler_response.intent
handler_response.action
handler_response.handled_at
```

Registry metadata:

```text
registry_execution.checked
registry_execution.registered
registry_execution.intent
registry_execution.runner
registry_execution.requires_confirmation
registry_execution.write_capable
```

## Confirmation rule

Write-capable handlers must not perform a write action during initial `run` unless the user has already explicitly confirmed that write.

For workflows that need confirmation, initial `run` should stage a session with a waiting status and return instructions for `ruby bin/soul respond`.

## Boundary rule

A handler must not claim a write action occurred unless deterministic evidence says it occurred.

Examples:

```text
browser_launch_attempted
files_moved_to_trash
restore_completed
network_used
```

## Registry registration

Handlers are registered in:

```text
lib/soul_core/workflow_handler_registry.rb
```

The registry entry must correspond to a workflow listed in:

```text
lib/soul_core/workflow_registry.rb
```

## Intent matching

Handler-owned intent matching should return an `IntentRouter::Result` object using the supplied `result_class`.

Example shape:

```ruby
result_class.new(
  ok: true,
  intent: intent,
  parameters: { "query" => "Folsom Prison Blues" },
  confidence: 0.91,
  reason: "Matched workflow-specific phrasing.",
  source: "workflow_handler"
)
```

A handler should return `nil` when it does not match.

## Adding a new handler checklist

Use `docs/workflows/HANDLER_CONTRACT_CHECKLIST.md` and `templates/workflows/handler_template.rb`.

## Current reference implementation

The current reference handler is:

```text
SoulCore::Workflows::YouTubePlayHandler
```
